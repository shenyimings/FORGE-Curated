// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { Lender } from "../../contracts/lendingPool/Lender.sol";
import { Vault } from "../../contracts/vault/Vault.sol";

import { DebtToken } from "../../contracts/lendingPool/tokens/DebtToken.sol";

import { ValidationLogic } from "../../contracts/lendingPool/libraries/ValidationLogic.sol";
import { TestDeployer } from "../deploy/TestDeployer.sol";
import { MockERC20 } from "../mocks/MockERC20.sol";
import { console } from "forge-std/console.sol";

contract LenderBorrowTest is TestDeployer {
    address user_agent;

    DebtToken debtToken;

    function setUp() public {
        _deployCapTestEnvironment();
        _initTestVaultLiquidity(usdVault);
        _initSymbioticVaultsLiquidity(env);

        user_agent = _getRandomAgent();

        vm.startPrank(env.symbiotic.users.vault_admin);
        _symbioticVaultDelegateToAgent(symbioticWethVault, env.symbiotic.networkAdapter, user_agent, 2e18);

        uint256 assetIndex = _getAssetIndex(usdVault, address(usdc));
        debtToken = DebtToken(usdVault.debtTokens[assetIndex]);
    }

    function test_lender_borrow_and_repay() public {
        vm.startPrank(user_agent);

        uint256 backingBefore = usdc.balanceOf(address(cUSD));

        vm.expectRevert(ValidationLogic.MinBorrowAmount.selector);
        lender.borrow(address(usdc), 99e6, user_agent);

        lender.borrow(address(usdc), 1000e6, user_agent);
        assertEq(usdc.balanceOf(user_agent), 1000e6);

        // simulate yield
        usdc.mint(user_agent, 1000e6);

        // repay the debt
        usdc.approve(env.infra.lender, 1000e6 + 10e6);
        lender.repay(address(usdc), 1000e6, user_agent);
        assertGe(usdc.balanceOf(address(cUSD)), backingBefore);

        assertDebtEq(0);
    }

    function test_lender_borrow_and_repay_with_another_asset() public {
        vm.startPrank(user_agent);

        lender.borrow(address(usdc), 1000e6, user_agent);
        assertEq(usdc.balanceOf(user_agent), 1000e6);

        // simulate yield
        usdt.mint(user_agent, 1000e6);

        // repay the debt
        usdt.approve(env.infra.lender, 1000e6 + 10e6);
        vm.expectRevert();
        lender.repay(address(usdt), 1000e6, user_agent);
    }

    function test_lender_borrow_and_repay_more_than_borrowed() public {
        vm.startPrank(user_agent);

        lender.borrow(address(usdc), 1000e6, user_agent);
        assertEq(usdc.balanceOf(user_agent), 1000e6);

        // simulate yield
        usdc.mint(user_agent, 1000e6);

        // repay the debt
        usdc.approve(env.infra.lender, 2000e6 + 10e6);
        lender.repay(address(usdc), 2000e6, user_agent);

        assertEq(usdc.balanceOf(user_agent), 1000e6);
    }

    function test_borrow_an_invalid_asset() public {
        vm.startPrank(user_agent);

        vm.expectRevert();
        lender.borrow(address(0), 1000e6, user_agent);

        MockERC20 invalidAsset = new MockERC20("InvalidAsset", "INV", 18);

        invalidAsset.mint(user_agent, 1000e6);

        vm.expectRevert();
        lender.borrow(address(invalidAsset), 1000e6, user_agent);
    }

    function test_borrow_more_than_one_asset() public {
        vm.startPrank(user_agent);

        lender.borrow(address(usdc), 1000e6, user_agent);
        assertEq(usdc.balanceOf(user_agent), 1000e6);

        lender.borrow(address(usdt), 1000e6, user_agent);
        assertEq(usdt.balanceOf(user_agent), 1000e6);
    }

    function test_lender_realize_interest() public {
        vm.startPrank(user_agent);

        lender.borrow(address(usdc), 300e6, user_agent);
        assertEq(usdc.balanceOf(user_agent), 300e6);

        _timeTravel(1 days);

        uint256 debt = debtToken.balanceOf(user_agent);
        assertGt(debt, 300e6);

        uint256 feeAuctionBalBefore = usdc.balanceOf(address(cUSDFeeAuction));

        lender.realizeInterest(address(usdc));

        uint256 feeAuctionBalAfter = usdc.balanceOf(address(cUSDFeeAuction));

        assertEq(feeAuctionBalAfter - feeAuctionBalBefore, debt - 300e6);
    }

    function test_realize_restaker_interest() public {
        vm.startPrank(user_agent);

        lender.borrow(address(usdc), 300e6, user_agent);
        assertEq(usdc.balanceOf(user_agent), 300e6);

        _timeTravel(1 days);

        address networkRewards = env.symbiotic.networkRewards[0];

        uint256 restakerInterestBefore = lender.accruedRestakerInterest(user_agent, address(usdc));

        lender.realizeRestakerInterest(user_agent, address(usdc));

        uint256 rewardsBalance = usdc.balanceOf(networkRewards);
        assertEq(rewardsBalance, restakerInterestBefore);

        uint256 totalDebt = debtToken.balanceOf(user_agent) + restakerInterestBefore;

        usdc.mint(user_agent, totalDebt);
        usdc.approve(address(lender), totalDebt);
        lender.repay(address(usdc), totalDebt, user_agent);

        uint256 restakerInterest = lender.accruedRestakerInterest(user_agent, address(usdc));
        uint256 unrealizedInterest = lender.unrealizedInterest(user_agent, address(usdc));

        /// There should be no restaker interest left
        assertEq(restakerInterest, 0);
        /// There should be no unrealized interest left
        assertEq(unrealizedInterest, 0);
        /// Rewards should not have increased
        assertEq(rewardsBalance, restakerInterestBefore);
    }

    function test_borrow_payback_debt_tokens() public {
        vm.startPrank(user_agent);

        lender.borrow(address(usdc), 300e6, user_agent);
        assertEq(usdc.balanceOf(user_agent), 300e6);

        _timeTravel(1 days);

        uint256 totalDebt = lender.debt(address(user_agent), address(usdc));
        uint256 debt = debtToken.balanceOf(user_agent);
        uint256 restakerInterest = lender.accruedRestakerInterest(user_agent, address(usdc));

        console.log("Principal Debt tokens:", debt);
        console.log("Restaker Debt tokens:", restakerInterest);

        assertEq(totalDebt, debt + restakerInterest);

        usdc.mint(user_agent, totalDebt);

        // repay the debt
        usdc.approve(address(lender), totalDebt);
        lender.repay(address(usdc), debt, user_agent);

        lender.repay(address(usdc), restakerInterest, user_agent);

        assertDebtEq(0);
    }

    function test_borrow_utilization() public {
        vm.startPrank(env.symbiotic.users.vault_admin);
        _symbioticVaultDelegateToAgent(symbioticWethVault, env.symbiotic.networkAdapter, user_agent, 2e27);
        vm.stopPrank();

        vm.startPrank(user_agent);

        uint256 totalSupply = cUSD.totalSupplies(address(usdt));

        lender.borrow(address(usdt), totalSupply, user_agent);
        assertEq(usdt.balanceOf(user_agent), totalSupply);

        assertEq(cUSD.utilization(address(usdt)), 1e27);
        assertEq(cUSD.totalBorrows(address(usdt)), totalSupply);
        assertEq(cUSD.availableBalance(address(usdt)), 0);

        usdt.approve(address(lender), totalSupply);
        lender.repay(address(usdt), totalSupply, user_agent);

        assertEq(cUSD.utilization(address(usdt)), 0);
        assertEq(cUSD.totalBorrows(address(usdt)), 0);
        assertEq(cUSD.availableBalance(address(usdt)), totalSupply);

        lender.borrow(address(usdt), totalSupply / 2, user_agent);
        assertEq(cUSD.utilization(address(usdt)), 0.5e27);
        assertEq(cUSD.totalBorrows(address(usdt)), totalSupply / 2);
        assertEq(cUSD.availableBalance(address(usdt)), totalSupply / 2);

        // since we updated the index current should be 0
        assertEq(cUSD.currentUtilizationIndex(address(usdt)), 0);
    }

    function assertDebtEq(uint256 totalDebt) internal view {
        assertEq(debtToken.balanceOf(user_agent) + lender.accruedRestakerInterest(user_agent, address(usdc)), totalDebt);
    }
}
