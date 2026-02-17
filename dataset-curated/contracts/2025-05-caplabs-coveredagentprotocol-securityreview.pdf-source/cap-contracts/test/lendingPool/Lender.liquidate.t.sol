// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { Delegation } from "../../contracts/delegation/Delegation.sol";
import { Lender } from "../../contracts/lendingPool/Lender.sol";
import { ILender } from "../../contracts/interfaces/ILender.sol";
import { TestDeployer } from "../deploy/TestDeployer.sol";
import { MockChainlinkPriceFeed } from "../mocks/MockChainlinkPriceFeed.sol";
import { console } from "forge-std/console.sol";

contract LenderLiquidateTest is TestDeployer {
    address user_agent;

    function setUp() public {
        _deployCapTestEnvironment();
        _initTestVaultLiquidity(usdVault);
        _initSymbioticVaultsLiquidity(env);

        user_agent = _getRandomAgent();

        vm.startPrank(env.symbiotic.users.vault_admin);
        _symbioticVaultDelegateToAgent(symbioticWethVault, env.symbiotic.networkAdapter, user_agent, 2e18);
        _symbioticVaultDelegateToAgent(symbioticUsdtVault, env.symbiotic.networkAdapter, user_agent, 1000e6);
        vm.stopPrank();

        vm.startPrank(env.users.lender_admin);
          // Try removing and re-adding the asset 
        lender.removeAsset(address(usdt));
        lender.addAsset(
                ILender.AddAssetParams({
                    asset: address(usdt),
                    vault: address(cUSD),
                    principalDebtToken: env.usdVault.principalDebtTokens[0],
                    restakerDebtToken: env.usdVault.restakerDebtTokens[0],
                    interestDebtToken: env.usdVault.interestDebtTokens[0],
                    interestReceiver: env.usdVault.feeAuction,
                    restakerInterestReceiver: env.infra.delegation,
                    bonusCap: 0.1e27
                })
            );
        lender.pauseAsset(address(usdt), false);
        vm.stopPrank();
    }

    function test_lender_liquidate_in_case_coverage_is_equal_to_debt() public {
        // borrow some assets
        {
            vm.startPrank(user_agent);
            lender.borrow(address(usdc), 3000e6, user_agent);
            assertEq(usdc.balanceOf(user_agent), 3000e6);

            vm.stopPrank();
        }

        // Modify the agent to have 0.01 liquidation threshold
        {
            vm.startPrank(env.users.delegation_admin);
            Delegation(env.infra.delegation).modifyAgent(user_agent, 0.5e27, 0.01e27);
            vm.stopPrank();
        }

        // change eth oracle price
        _setAssetOraclePrice(address(weth), 1000e8);

        // anyone can liquidate the debt
        {
            vm.startPrank(env.testUsers.liquidator);

            deal(address(usdc), env.testUsers.liquidator, 3000e6);

            // start the first liquidation
            lender.initiateLiquidation(user_agent);
            uint256 gracePeriod = lender.grace();

            console.log("Starting Liquidations");
            console.log("");
            _timeTravel(gracePeriod + 1);
            // approve repay amount for liquidation
            usdc.approve(address(lender), 3000e6);
            lender.liquidate(user_agent, address(usdc), 1000e6);

            (, uint256 totalDebt,,,) = lender.agent(user_agent);
            console.log("Debt prior to liquidation", totalDebt);

            console.log("Liquidator usdt balance after first liquidation", usdt.balanceOf(env.testUsers.liquidator));
            console.log("Liquidator weth balance after first liquidation", weth.balanceOf(env.testUsers.liquidator));
            console.log("");

            // start the second liquidation
            lender.liquidate(user_agent, address(usdc), 1000e6);

            console.log("Liquidator usdt balance after second liquidation", usdt.balanceOf(env.testUsers.liquidator));
            console.log("Liquidator weth balance after second liquidation", weth.balanceOf(env.testUsers.liquidator));
            console.log("");
            // start the third liquidation
            lender.liquidate(user_agent, address(usdc), 1000e6);

            console.log("Liquidator usdt balance after third liquidation", usdt.balanceOf(env.testUsers.liquidator));
            console.log("Liquidator weth balance after third liquidation", weth.balanceOf(env.testUsers.liquidator));
            console.log("");
            console.log("Liquidator usdc balance after third liquidation", usdc.balanceOf(env.testUsers.liquidator));
            console.log("");

            assertEq(usdc.balanceOf(env.testUsers.liquidator), 0);
            assertEq(usdt.balanceOf(env.testUsers.liquidator), 1000e6);
            assertEq(weth.balanceOf(env.testUsers.liquidator), 2e18);

            uint256 coverage = Delegation(env.infra.delegation).coverage(user_agent);
            console.log("Coverage after liquidations", coverage);
            console.log("");
            assertEq(coverage, 0);

            (uint256 totalDelegation, uint256 afterTotalDebt,,,) = lender.agent(user_agent);

            console.log("Total delegation", totalDelegation);
            console.log("Total debt", afterTotalDebt);
            assertEq(totalDelegation, 0);

            /// We should only have interest let to pay back
            assertEq(afterTotalDebt, totalDebt - 2000e8);

            vm.stopPrank();
        }
    }

    function test_lender_liquidate_to_health_is_less_than_liquidation_threshold() public {
        // borrow some assets
        {
            vm.startPrank(user_agent);
            lender.borrow(address(usdc), 3000e6, user_agent);
            assertEq(usdc.balanceOf(user_agent), 3000e6);

            vm.stopPrank();
        }

        // Modify the agent to have 0.01 liquidation threshold
        {
            vm.startPrank(env.users.delegation_admin);
            Delegation(env.infra.delegation).modifyAgent(user_agent, 0.5e27, 0.01e27);
            vm.stopPrank();
        }

        // change eth oracle price
        _setAssetOraclePrice(address(weth), 2000e8);

        // anyone can liquidate the debt
        {
            vm.startPrank(env.testUsers.liquidator);

            deal(address(usdc), env.testUsers.liquidator, 3000e6);

            // start the first liquidation
            lender.initiateLiquidation(user_agent);
            uint256 gracePeriod = lender.grace();

            console.log("Starting Liquidations");
            console.log("");
            _timeTravel(gracePeriod + 1);
            // approve repay amount for liquidation
            usdc.approve(address(lender), 3000e6);
            lender.liquidate(user_agent, address(usdc), 1000e6);

            console.log("Liquidator usdt balance after first liquidation", usdt.balanceOf(env.testUsers.liquidator));
            console.log("Liquidator weth balance after first liquidation", weth.balanceOf(env.testUsers.liquidator));
            console.log("");

            // start the second liquidation
            lender.liquidate(user_agent, address(usdc), 1000e6);

            console.log("Liquidator usdt balance after second liquidation", usdt.balanceOf(env.testUsers.liquidator));
            console.log("Liquidator weth balance after second liquidation", weth.balanceOf(env.testUsers.liquidator));
            console.log("");
            // start the third liquidation
            lender.liquidate(user_agent, address(usdc), 1000e6);

            console.log("Liquidator usdt balance after third liquidation", usdt.balanceOf(env.testUsers.liquidator));
            console.log("Liquidator weth balance after third liquidation", weth.balanceOf(env.testUsers.liquidator));
            console.log("");
            console.log("Liquidator usdc balance after third liquidation", usdc.balanceOf(env.testUsers.liquidator));
            console.log("");

            //    assertEq(usdc.balanceOf(env.testUsers.liquidator), 0);
            //    assertEq(usdt.balanceOf(env.testUsers.liquidator), 1000e6);
            //    assertEq(weth.balanceOf(env.testUsers.liquidator), 2e18);

            uint256 coverage = Delegation(env.infra.delegation).coverage(user_agent);
            console.log("Coverage after liquidations", coverage);
            console.log("");
            //     assertEq(coverage, 0);

            (uint256 totalDelegation, uint256 totalDebt,,, uint256 health) = lender.agent(user_agent);

            console.log("Total debt after liquidations", totalDebt);
            console.log("Total delegation after liquidations", totalDelegation);
            console.log("Health after liquidations", health);
            assertGt(health, 1e27);
            //    assertEq(totalDelegation, 0);
            //    assertEq(totalDebt, 0);

            vm.stopPrank();
        }
    }

    function test_lender_liquidate_in_the_future() public {
        // borrow some assets
        {
            vm.startPrank(user_agent);
            lender.borrow(address(usdc), 3000e6, user_agent);
            assertEq(usdc.balanceOf(user_agent), 3000e6);

            /// well past all epochs
            _timeTravel(60 days);

            vm.stopPrank();
        }

        // Modify the agent to have 0.01 liquidation threshold
        {
            vm.startPrank(env.users.delegation_admin);
            Delegation(env.infra.delegation).modifyAgent(user_agent, 0.5e27, 0.01e27);
            vm.stopPrank();
        }

        // change eth oracle price
        _setAssetOraclePrice(address(weth), 2000e8);

        // anyone can liquidate the debt
        {
            vm.startPrank(env.testUsers.liquidator);

            // dealing a bit more since now we cover the interest
            deal(address(usdc), env.testUsers.liquidator, 3200e6);

            // start the first liquidation
            lender.initiateLiquidation(user_agent);
            uint256 gracePeriod = lender.grace();

            console.log("Starting Liquidations");
            console.log("");
            _timeTravel(gracePeriod + 1);

            (uint256 totalDelegation, uint256 totalDebt, uint256 ltv, uint256 liquidationThreshold, uint256 health) =
                lender.agent(user_agent);

            console.log("Total debt after 60 days", totalDebt);
            console.log("Total delegation after 60 days", totalDelegation);
            console.log("LTV after 60 days", ltv);
            console.log("Liquidation threshold after 60 days", liquidationThreshold);
            console.log("Health after 60 days", health);

            // approve repay amount for liquidation
            usdc.approve(address(lender), 3200e6);
            lender.liquidate(user_agent, address(usdc), 1000e6);

            console.log("Liquidator usdt balance after first liquidation", usdt.balanceOf(env.testUsers.liquidator));
            console.log("Liquidator weth balance after first liquidation", weth.balanceOf(env.testUsers.liquidator));
            console.log("");

            // start the second liquidation
            lender.liquidate(user_agent, address(usdc), 1000e6);

            console.log("Liquidator usdt balance after second liquidation", usdt.balanceOf(env.testUsers.liquidator));
            console.log("Liquidator weth balance after second liquidation", weth.balanceOf(env.testUsers.liquidator));
            console.log("");
            // start the third liquidation
            lender.liquidate(user_agent, address(usdc), 1200e6);

            console.log("Liquidator usdt balance after third liquidation", usdt.balanceOf(env.testUsers.liquidator));
            console.log("Liquidator weth balance after third liquidation", weth.balanceOf(env.testUsers.liquidator));
            console.log("");
            console.log("Liquidator usdc balance after third liquidation", usdc.balanceOf(env.testUsers.liquidator));
            console.log("");

            //    assertEq(usdc.balanceOf(env.testUsers.liquidator), 0);
            //    assertEq(usdt.balanceOf(env.testUsers.liquidator), 1000e6);
            //    assertEq(weth.balanceOf(env.testUsers.liquidator), 2e18);

            uint256 coverage = Delegation(env.infra.delegation).coverage(user_agent);
            console.log("Coverage after liquidations", coverage);
            console.log("");
            //     assertEq(coverage, 0);

            (totalDelegation, totalDebt, ltv, liquidationThreshold, health) = lender.agent(user_agent);

            console.log("Health after liquidations", health);

            console.log("Total debt after liquidations", totalDebt);
            console.log("Total delegation after liquidations", totalDelegation);
            assertGt(health, 1e27);
            //    assertEq(totalDelegation, 0);
            //    assertEq(totalDebt, 0);

            vm.stopPrank();
        }
    }
}
