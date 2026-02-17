// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { Lender } from "../../contracts/lendingPool/Lender.sol";

import { InterestDebtToken } from "../../contracts/lendingPool/tokens/InterestDebtToken.sol";
import { PrincipalDebtToken } from "../../contracts/lendingPool/tokens/PrincipalDebtToken.sol";
import { RestakerDebtToken } from "../../contracts/lendingPool/tokens/RestakerDebtToken.sol";
import { TestDeployer } from "../deploy/TestDeployer.sol";
import { console } from "forge-std/console.sol";

contract LenderBorrowTest is TestDeployer {
    address user_agent;

    PrincipalDebtToken principalDebtToken;
    RestakerDebtToken restakerDebtToken;
    InterestDebtToken interestDebtToken;

    function setUp() public {
        _deployCapTestEnvironment();
        _initTestVaultLiquidity(usdVault);
        _initSymbioticVaultsLiquidity(env);

        user_agent = _getRandomAgent();

        vm.startPrank(env.symbiotic.users.vault_admin);
        _symbioticVaultDelegateToAgent(symbioticWethVault, env.symbiotic.networkAdapter, user_agent, 2e18);
        _symbioticVaultDelegateToAgent(symbioticUsdtVault, env.symbiotic.networkAdapter, user_agent, 1000e6);

        uint256 assetIndex = _getAssetIndex(usdVault, address(usdc));
        principalDebtToken = PrincipalDebtToken(usdVault.principalDebtTokens[assetIndex]);
        restakerDebtToken = RestakerDebtToken(usdVault.restakerDebtTokens[assetIndex]);
        interestDebtToken = InterestDebtToken(usdVault.interestDebtTokens[assetIndex]);
    }

    function test_lender_borrow_and_repay() public {
        vm.startPrank(user_agent);

        uint256 backingBefore = usdc.balanceOf(address(cUSD));

        lender.borrow(address(usdc), 1000e6, user_agent);
        assertEq(usdc.balanceOf(user_agent), 1000e6);

        // simulate yield
        usdc.mint(user_agent, 1000e6);

        // repay the debt
        usdc.approve(env.infra.lender, 1000e6 + 10e6);
        lender.repay(address(usdc), 1000e6, user_agent);
        assertGe(usdc.balanceOf(address(cUSD)), backingBefore);

        assertDebtEq(0, 0, 0);
    }

    function test_lender_borrow_and_repay_debt_tokens() public {
        // ensure reward targets are empty
        assertEq(usdc.balanceOf(symbioticUsdtNetworkRewards.stakerRewarder), 0);
        assertEq(usdc.balanceOf(usdVault.feeAuction), 0);

        vm.startPrank(user_agent);

        lender.borrow(address(usdc), 1000e6, user_agent);
        uint256 principalDebt = principalDebtToken.balanceOf(user_agent);
        assertEq(usdc.balanceOf(user_agent), 1000e6);

        // we should have some debt tokens attached to the user
        assertDebtEq(1000e6, 0, 0);

        // check on the view functions
        (uint256 interestPerSecond, uint256 lastUpdate) = restakerDebtToken.agent(user_agent);
        assertEq(lastUpdate, block.timestamp);

        (uint256 storedIndex, uint256 lastUpdateInterest) = interestDebtToken.agent(user_agent);
        assertEq(storedIndex, 1e27);
        assertEq(lastUpdateInterest, block.timestamp);

        _timeTravel(3 hours);

        uint256 currentIndex = interestDebtToken.currentIndex();
        uint256 indx = currentIndex - storedIndex;

        uint256 interestDebt = indx * 1000e6 / 1e27;
        console.log("Interest debt", interestDebt);

        uint256 restakerDebt = interestPerSecond * 3 hours / 1e27;
        console.log("Restaker debt", restakerDebt);

        // balances should accrue interest over time
        assertDebtEq(principalDebt, interestDebt, restakerDebt);

        // check on the view functions
        (interestPerSecond, lastUpdate) = restakerDebtToken.agent(user_agent);
      //  assertEq(interestPerSecond, 50e27);
        assertEq(lastUpdate, block.timestamp - 3 hours);

        (storedIndex, lastUpdateInterest) = interestDebtToken.agent(user_agent);
        assertEq(storedIndex, 1e27);
        assertEq(lastUpdateInterest, block.timestamp - 3 hours);

        // simulate yield
        usdc.mint(user_agent, 1_000_000e6);
        usdc.approve(env.infra.lender, 1_000_000e6);

        // principal debt should be repaid first
        lender.repay(address(usdc), 100e6, user_agent);
        assertDebtEq(principalDebt - 100e6, interestDebt, restakerDebt);

        // restaker debt should be repaid next
        lender.repay(address(usdc), 900e6 + restakerDebt, user_agent);
        assertDebtEq(0, interestDebt, 0);

        // interest continue to accrue when principal debt is repaid but restaker debt is not
        _timeTravel(10 days);
        uint256 currentInterestDebt = interestDebtToken.balanceOf(user_agent);
        assertGt(currentInterestDebt, interestDebt);

        // repay more than the debt just repays the debt
        uint256 balanceBefore = usdc.balanceOf(user_agent);
        lender.repay(address(usdc), 100e6, user_agent);
        assertEq(usdc.balanceOf(user_agent), balanceBefore - currentInterestDebt);

        // all square now
        assertDebtEq(0, 0, 0);

        // restaker rewards should be distributed to the networks
       // assertEq(usdc.balanceOf(symbioticUsdtNetworkRewards.stakerRewarder), restakerDebt);

        // interest rewards should be distributed to fee auction
        assertEq(usdc.balanceOf(usdVault.feeAuction), currentInterestDebt);
    }

    function assertDebtEq(uint256 principalDebt, uint256 interestDebt, uint256 restakerDebt) internal view {
        (uint256 principalDebtView, uint256 interestDebtView, uint256 restakerDebtView) =
            lender.debt(user_agent, address(usdc));
        assertEq(principalDebtView, principalDebt);
        assertEq(interestDebtView, interestDebt);
        assertEq(restakerDebtView, restakerDebt);

        assertEq(principalDebtToken.balanceOf(user_agent), principalDebt);
        assertEq(interestDebtToken.balanceOf(user_agent), interestDebt);
        assertEq(restakerDebtToken.balanceOf(user_agent), restakerDebt);
    }
}
