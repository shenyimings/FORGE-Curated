// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { Delegation } from "../../contracts/delegation/Delegation.sol";

import { IMinter } from "../../contracts/interfaces/IMinter.sol";
import { IOracle } from "../../contracts/interfaces/IOracle.sol";
import { Lender } from "../../contracts/lendingPool/Lender.sol";
import { TestDeployer } from "../deploy/TestDeployer.sol";
import { MockChainlinkPriceFeed } from "../mocks/MockChainlinkPriceFeed.sol";
import { console } from "forge-std/console.sol";

contract ScenarioBasicTest is TestDeployer {
    address user_agent;

    function setUp() public {
        _deployCapTestEnvironment();
        _initTestVaultLiquidity(usdVault);
        _initSymbioticVaultsLiquidity(env);

        user_agent = _getRandomAgent();

        vm.startPrank(env.symbiotic.users.vault_admin);
        _symbioticVaultDelegateToAgent(symbioticWethVault, env.symbiotic.networkAdapter, user_agent, 3e18);
        vm.stopPrank();

        vm.startPrank(env.users.lender_admin);

        IMinter.FeeData memory feeData = IMinter.FeeData({
            minMintFee: 0.005e27,
            slope0: 0.0001e27,
            slope1: 0.1e27,
            mintKinkRatio: 0.85e27,
            burnKinkRatio: 0.15e27,
            optimalRatio: 0.33e27
        });

        cUSD.setFeeData(address(usdt), feeData);
        cUSD.setFeeData(address(usdc), feeData);
        cUSD.setFeeData(address(usdx), feeData);

        cUSD.setRedeemFee(0.001e27); // 0.1%

        vm.stopPrank();

        _setAssetOraclePrice(address(usdc), 0.99985e8);
    }

    function test_everyday_functionality() public {
        uint256 alice_cUSD_balance;
        address alice = makeAddr("Alice");
        address bob = makeAddr("Bob");
        {
            /// Alice and Bob get some CAP tokens

            /// Alice and Bob have 10000 USDT and USDC
            deal(address(usdt), alice, 10000e6);
            deal(address(usdc), bob, 10000e6);

            console.log("");
            console.log("--------------------------------");
            console.log("Alice and Bob Lifecycle Test");
            console.log("--------------------------------");
            console.log("");

            console.log("Price of USDT in 8 decimals", uint256(1e8));
            console.log("Price of USDC in 8 decimals", uint256(0.99985e8));
            console.log("");

            console.log("Alice's USDT balance", usdt.balanceOf(alice));
            console.log("Bob's USDC balance", usdc.balanceOf(bob));
            console.log("");

            vm.startPrank(alice);

            uint256 usdt_total_supplies = cUSD.totalSupplies(address(usdt));
            console.log("USDT total supplies", usdt_total_supplies);
            uint256 usdc_total_supplies = cUSD.totalSupplies(address(usdc));
            console.log("USDC total supplies", usdc_total_supplies);
            uint256 usdx_total_supplies = cUSD.totalSupplies(address(usdx));
            console.log("USDX total supplies", usdx_total_supplies);

            (uint256 cUSD_price,) = IOracle(env.infra.oracle).getPrice(address(cUSD));
            console.log("cUSD price", cUSD_price);

            uint256 cap_token_supply = cUSD.totalSupply();
            console.log("cUSD total supply", cap_token_supply);

            /// Alice is deposting 2000 USDT but since USDC is off peg she gets more than 2000 cUSD
            usdt.approve(address(cUSD), 10000e6);

            vm.expectRevert();

            /// Slippage
            cUSD.mint(address(usdt), 2000e6, 3000e18, alice, block.timestamp + 1 hours);
            vm.expectRevert();
            /// Time
            cUSD.mint(address(usdt), 2000e6, 1990e18, alice, block.timestamp - 1);
            cUSD.mint(address(usdt), 2000e6, 1990e18, alice, block.timestamp + 1 hours);
            assertGt(cUSD.balanceOf(alice), 1990e18);

            vm.stopPrank();

            vm.startPrank(bob);

            usdc.approve(address(cUSD), 10000e6);
            cUSD.mint(address(usdc), 2000e6, 1990e6, bob, block.timestamp + 1 hours);

            assertLt(cUSD.balanceOf(bob), 2000e18);

            alice_cUSD_balance = cUSD.balanceOf(alice);
            uint256 bob_cUSD_balance = cUSD.balanceOf(bob);

            console.log("Alice's cUSD balance", alice_cUSD_balance);
            console.log("Bob's cUSD balance", bob_cUSD_balance);
            console.log("");

            console.log("Alice's USDT balance", usdt.balanceOf(alice));
            console.log("Bob's USDC balance", usdc.balanceOf(bob));
            console.log("");

            vm.stopPrank();

            vm.startPrank(alice);

            alice_cUSD_balance = cUSD.balanceOf(alice);
            cUSD.approve(address(scUSD), alice_cUSD_balance);
            scUSD.deposit(alice_cUSD_balance, alice);

            console.log("Alice's scUSD balance", scUSD.balanceOf(alice));
            assertEq(scUSD.balanceOf(alice), alice_cUSD_balance);
            console.log("");

            vm.stopPrank();
        }

        address mev_bot = makeAddr("Mev Bot");
        deal(address(usdt), mev_bot, 4000e6);
        address[] memory assets = new address[](1);
        assets[0] = address(usdt);

        {
            vm.startPrank(env.users.vault_config_admin);
            cUSD.pause(address(usdt));
            vm.stopPrank();

            /// An Operater comes to borrow USDT
            vm.startPrank(user_agent);

            /// Start with 1000 USDT in the operator's wallet
            deal(address(usdt), user_agent, 1000e6);
            vm.expectRevert();
            lender.borrow(address(usdt), 1000e6, user_agent);

            vm.startPrank(env.users.vault_config_admin);
            cUSD.unpause(address(usdt));
            vm.stopPrank();

            vm.startPrank(user_agent);
            lender.borrow(address(usdt), 1000e6, user_agent);
            assertEq(usdt.balanceOf(user_agent), 2000e6);

            console.log("Operator Borrowed 1000 USDT");
            console.log("Move time forward 10 days");
            console.log("");
            _timeTravel(10 days);

            /// Lets get the fee auction started
            vm.startPrank(mev_bot);

            usdt.approve(address(cUSD), 4000e6);
            cUSD.mint(address(usdt), 1000e6, 0, mev_bot, block.timestamp + 1 hours);

            lender.realizeInterest(address(usdt));

            cUSD.approve(address(cUSDFeeAuction), 1000e18);
            uint256 startPrice = cUSDFeeAuction.currentPrice();
            console.log("Start price of fee auction", startPrice);
            cUSDFeeAuction.buy(startPrice, assets, new uint256[](assets.length), mev_bot, block.timestamp);

            vm.stopPrank();
        }

        {
            /// The operator repays the debt
            vm.startPrank(user_agent);
            uint256 debt = lender.debt(user_agent, address(usdt));
            console.log("Debt in USDT 6 Decimals");
            console.log("Total Debt", debt);
            console.log("Agent balance of USDT", usdt.balanceOf(user_agent));
            console.log("");

            usdt.approve(address(lender), debt);
            console.log("Operator Repays", debt);

            lender.repay(address(usdt), debt, user_agent);
            console.log("");

            debt = lender.debt(user_agent, address(usdt));
            assertEq(debt, 0);
            vm.stopPrank();
        }

        {
            /// The fee auction is started and we send cUSD to scUSD
            vm.startPrank(mev_bot);

            usdt.approve(address(cUSD), 1000e6);
            cUSD.mint(address(usdt), 1000e6, 0, mev_bot, block.timestamp + 1 hours);

            cUSD.approve(address(cUSDFeeAuction), 1000e18);
            uint256 usdt_balance_before = usdt.balanceOf(address(cUSDFeeAuction));
            uint256 cUSD_balance_before = cUSD.balanceOf(address(scUSD));
            console.log("USDT balance of fee auction before buy", usdt_balance_before);
            console.log("cUSD balance of scUSD before buy", cUSD_balance_before);

            // Cheat a bit and get the price to match the assets in the auction
            vm.startPrank(env.users.fee_auction_admin);
            uint256 minStartPrice = cUSDFeeAuction.minStartPrice();
            cUSDFeeAuction.setStartPrice(minStartPrice * 10);
            vm.stopPrank();

            vm.startPrank(mev_bot);

            uint256 startPrice = cUSDFeeAuction.startPrice();
            assertEq(startPrice, minStartPrice * 10);
            uint256 price = cUSDFeeAuction.currentPrice();
            // console.log("Start price of fee auction", startPrice);
            cUSDFeeAuction.buy(price, assets, new uint256[](assets.length), mev_bot, block.timestamp);
            uint256 usdt_balance_after = usdt.balanceOf(address(cUSDFeeAuction));
            uint256 cUSD_balance_after = cUSD.balanceOf(address(scUSD));
            console.log("USDT balance of fee auction after buy", usdt_balance_after);
            console.log("cUSD balance of scUSD after buy", cUSD_balance_after);

            scUSD.notify();

            console.log("Mev Bot's cUSD balance", cUSD.balanceOf(mev_bot));
            console.log("");

            vm.stopPrank();
        }

        {
            /// Alice wants to withdraw her scUSD and should have more cUSD than before
            vm.startPrank(alice);
            _timeTravel(1 days);

            console.log("Locked profit of scUSD", scUSD.lockedProfit());
            uint256 alice_scUSD_balance = scUSD.balanceOf(alice);
            console.log("Alice's scUSD balance", alice_scUSD_balance);
            console.log("");

            vm.stopPrank();

            vm.startPrank(bob);

            /// Bob is being malicious and trying to withdraw Alice's cUSD
            vm.expectRevert();
            scUSD.withdraw(alice_scUSD_balance, bob, alice);

            vm.stopPrank();

            vm.startPrank(alice);
            scUSD.redeem(alice_scUSD_balance, alice, alice);
            console.log("Alice's cUSD balance after 11 day in scUSD and a borrow", cUSD.balanceOf(alice));
            console.log("");

            assertGt(cUSD.balanceOf(alice), alice_cUSD_balance);

            vm.stopPrank();
        }
        uint256[] memory minAmountsOut = new uint256[](3);
        uint256 alice_usdt_balance_after;
        {
            /// Alice redeems and burns her cUSD
            vm.startPrank(bob);
            cUSD.approve(address(scUSD), cUSD.balanceOf(bob));
            scUSD.deposit(cUSD.balanceOf(bob), bob);
            vm.stopPrank();

            vm.startPrank(alice);

            /// Alice trying to borrow USDT but shes not allowed to
            vm.expectRevert();
            lender.borrow(address(usdt), 1000e6, alice);

            minAmountsOut[0] = 0;
            minAmountsOut[1] = 10000000000e18;
            minAmountsOut[2] = 0;

            console.log("minAmountsOut length", minAmountsOut.length);
            uint256 alice_usdc_balance_before = usdc.balanceOf(alice);
            uint256 alice_usdt_balance_before = usdt.balanceOf(alice);
            /// Alice wants to redeem half her cUSD
            uint256 redeemBal = cUSD.balanceOf(alice) / 2;
            vm.expectRevert();
            /// Slippage
            cUSD.redeem(redeemBal, minAmountsOut, alice, block.timestamp + 1 hours);
            minAmountsOut[1] = 0;
            vm.expectRevert();
            /// Time
            cUSD.redeem(redeemBal, minAmountsOut, alice, block.timestamp - 1);
            cUSD.redeem(redeemBal, minAmountsOut, alice, block.timestamp + 1 hours);

            uint256 alice_usdc_balance_after = usdc.balanceOf(alice);
            alice_usdt_balance_after = usdt.balanceOf(alice);
            uint256 alice_usdx_balance_after = usdx.balanceOf(alice);

            assertGt(alice_usdc_balance_after, alice_usdc_balance_before);
            assertGt(alice_usdt_balance_after, alice_usdt_balance_before);

            console.log("Alice's USDC balance after redeeming half her cUSD", alice_usdc_balance_after);
            console.log("Alice's USDT balance after redeeming half her cUSD", alice_usdt_balance_after);
            console.log("Alice's USDx balance after redeeming half her cUSD", alice_usdx_balance_after);

            vm.stopPrank();
        }
        {
            /// Alice decides to burn the rest of her cUSD
            vm.startPrank(alice);

            uint256 withdrawBal = cUSD.balanceOf(alice);
            vm.expectRevert();
            /// Slippage
            cUSD.burn(address(usdt), withdrawBal, 10000000000e18, alice, block.timestamp + 1 hours);
            vm.expectRevert();
            /// Time
            cUSD.burn(address(usdt), withdrawBal, 0, alice, block.timestamp - 1);

            cUSD.burn(address(usdt), withdrawBal, 0, alice, block.timestamp + 1 hours);

            console.log("Alice's USDT balance after burning the rest of her cUSD", usdt.balanceOf(alice));
            console.log(
                "Alice's equivalent balance of USDT after everything",
                usdt.balanceOf(alice) + usdc.balanceOf(alice) + (usdx.balanceOf(alice)) / 1e12
            );

            assertEq(cUSD.balanceOf(alice), 0);
            assertGt(usdt.balanceOf(alice), alice_usdt_balance_after);

            assertGt(
                usdt.balanceOf(alice) + usdc.balanceOf(alice) + (usdx.balanceOf(alice)) / 1e12,
                (10000e6 * 0.998e27 / 1e27)
            ); // Less redeem fee

            /// USDC goes over peg now
            console.log("");
            console.log("USDC is over peg now", uint256(1.01e8));
            console.log("");
            _setAssetOraclePrice(address(usdc), 1.01e8);
        }
        {
            vm.startPrank(alice);
            usdt.approve(address(cUSD), 1000e6);
            cUSD.mint(address(usdt), 1000e6, 0, alice, block.timestamp + 1 hours);

            alice_cUSD_balance = cUSD.balanceOf(alice);

            cUSD.burn(address(usdt), cUSD.balanceOf(alice), 0, alice, block.timestamp + 1 hours);
            console.log("Alice's cUSD balance after burning the rest of her cUSD", alice_cUSD_balance);
            console.log("");
            vm.stopPrank();
        }

        {
            /// The operator borrows and gets liquidated
            vm.startPrank(user_agent);

            console.log("");
            console.log("Operator borrows and gets liquidated");
            lender.borrow(address(usdc), 3000e6, user_agent);

            uint256 total_borrows = cUSD.totalBorrows(address(usdc));
            assertEq(total_borrows, 3000e6);

            uint256 utilization = cUSD.utilization(address(usdc));
            assertLt(utilization, 1e27);

            uint256 current_utilization_index = cUSD.currentUtilizationIndex(address(usdc));
            console.log("Current utilization index of USDC", current_utilization_index);

            console.log("");
            console.log("Operator's debt as he borrows 3000 USDC", usdc.balanceOf(user_agent));
            console.log("");

            console.log("Move time forward 10 days");
            _timeTravel(10 days);
            console.log("");

            vm.stopPrank();

            vm.startPrank(env.users.delegation_admin);

            (uint256 totalDelegation,, uint256 totalDebt, uint256 ltv, uint256 liquidationThreshold, uint256 health) =
                lender.agent(user_agent);
            console.log("Total delegation of the operator", totalDelegation);
            console.log("Total debt of the operator", totalDebt);
            console.log("LTV of the operator", ltv);
            console.log("Liquidation threshold of the operator", liquidationThreshold);
            console.log("Health of the operator", health);
            /// Bad actor so we set his liquidation threshold to 1%
            Delegation(env.infra.delegation).modifyAgent(user_agent, 0, 0.01e27);
            vm.stopPrank();

            vm.startPrank(env.testUsers.liquidator);
            deal(address(usdc), env.testUsers.liquidator, 4000e6);
            usdc.approve(address(lender), 4000e6);
            lender.initiateLiquidation(user_agent);

            vm.expectRevert();
            lender.cancelLiquidation(user_agent);

            vm.expectRevert();
            lender.initiateLiquidation(user_agent);
            _timeTravel(lender.grace() + 1);
            lender.liquidate(user_agent, address(usdc), 4000e6);

            lender.cancelLiquidation(user_agent);
            vm.stopPrank();

            (totalDelegation,, totalDebt, ltv, liquidationThreshold, health) = lender.agent(user_agent);
            console.log("");
            console.log("Total delegation of the operator after liquidation", totalDelegation);
            console.log("Total debt of the operator after liquidation", totalDebt);
            console.log("LTV of the operator after liquidation", ltv);
            console.log("Liquidation threshold of the operator after liquidation", liquidationThreshold);
            console.log("Health of the operator after liquidation", health);

            console.log(
                "Liquidator's USDC balance after liquidating the operator", usdc.balanceOf(env.testUsers.liquidator)
            );
        }
    }
}
