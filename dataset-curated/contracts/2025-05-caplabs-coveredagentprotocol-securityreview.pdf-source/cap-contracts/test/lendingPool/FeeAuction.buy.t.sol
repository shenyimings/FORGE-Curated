// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IFeeAuction } from "../../contracts/interfaces/IFeeAuction.sol";
import { TestDeployer } from "../deploy/TestDeployer.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract FeeAuctionBuyTest is TestDeployer {
    address realizer;

    function setUp() public {
        _deployCapTestEnvironment();
        _initTestVaultLiquidity(usdVault);
        _initSymbioticVaultsLiquidity(env);

        // initialize the realizer
        realizer = makeAddr("interest_realizer");
        _initTestUserMintCapToken(usdVault, realizer, 1000e18);

        // Have a random agent borrow to generate fees
        address borrower = _getRandomAgent();
        vm.startPrank(borrower);
        lender.borrow(address(usdc), 1000e6, borrower);
        vm.stopPrank();

        _timeTravel(20 days);
    }

    function test_fee_auction_buy() public {
        // do a first buy to reset the auction timestamp
        {
            vm.startPrank(realizer);
            lender.realizeInterest(address(usdc));
            uint256 price = cUSDFeeAuction.currentPrice();
            cUSD.approve(address(cUSDFeeAuction), type(uint256).max);
            cUSDFeeAuction.buy(price, usdVault.assets, new uint256[](usdVault.assets.length), realizer, block.timestamp);
            usdc.transfer(makeAddr("burn"), usdc.balanceOf(address(realizer)));
            vm.stopPrank();
        }

        // ensure the auction timestamp is reset
        assertEq(cUSDFeeAuction.startTimestamp(), block.timestamp);

        // ensure the fee auction and realizer have nothing in it
        assertEq(usdc.balanceOf(address(cUSDFeeAuction)), 0);
        assertEq(usdc.balanceOf(address(realizer)), 0);

        // ensure the auction price is the minimum start price
        assertEq(cUSDFeeAuction.currentPrice(), 1e18);
        assertEq(cUSDFeeAuction.paymentToken(), address(cUSD));
        assertEq(cUSDFeeAuction.paymentRecipient(), address(scUSD));
        assertEq(cUSDFeeAuction.startPrice(), 1e18);
        assertEq(cUSDFeeAuction.minStartPrice(), 1e18);
        assertEq(cUSDFeeAuction.duration(), 3 hours);

        _timeTravel(1 hours);

        assertEq(
            cUSDFeeAuction.currentPrice(), cUSDFeeAuction.minStartPrice() * (1e27 - (1 hours * 0.9e27 / 3 hours)) / 1e27
        ); // fee auction is 3h long

        // Save balances before buying
        uint256 usdcInterest = usdc.balanceOf(address(cUSDFeeAuction));
        assertEq(usdcInterest, 0, "Fee auction should be empty before realizing interest");

        uint256 priceBeforeBuy = cUSDFeeAuction.currentPrice();

        {
            vm.startPrank(realizer);

            // realize everything
            lender.realizeInterest(address(usdc));

            // realising interest should have created some fees
            assertGt(usdc.balanceOf(address(cUSDFeeAuction)), 0, "Fee auction should have some fees");

            // Approve payment token (cUSD) for fee auction
            cUSD.approve(address(cUSDFeeAuction), type(uint256).max);
            uint256 price = cUSDFeeAuction.currentPrice();
            cUSDFeeAuction.buy(price, usdVault.assets, new uint256[](usdVault.assets.length), realizer, block.timestamp);

            // ensure realizer balance increased by the expected amount
            assertGt(usdc.balanceOf(address(realizer)), 0, "Realizer USDC balance should have increased");

            vm.stopPrank();
        }

        // fee auction price doubles after buy
        assertEq(cUSDFeeAuction.currentPrice(), priceBeforeBuy * 2);
    }

    function test_setStartPrice() public {
        uint256 newStartPrice = 2000e18;

        // Non-admin should not be able to set start price
        vm.prank(makeAddr("non_admin"));
        vm.expectRevert();
        cUSDFeeAuction.setStartPrice(newStartPrice);

        // Admin should be able to set start price
        vm.prank(env.users.fee_auction_admin);
        vm.expectEmit(false, false, false, true);
        emit IFeeAuction.SetStartPrice(newStartPrice);
        cUSDFeeAuction.setStartPrice(newStartPrice);

        assertEq(cUSDFeeAuction.startPrice(), newStartPrice);
    }

    function test_setDuration() public {
        uint256 newDuration = 4 hours;

        // Non-admin should not be able to set duration
        vm.prank(makeAddr("non_admin"));
        vm.expectRevert();
        cUSDFeeAuction.setDuration(newDuration);

        // Admin should be able to set duration
        vm.prank(env.users.fee_auction_admin);
        vm.expectEmit(false, false, false, true);
        emit IFeeAuction.SetDuration(newDuration);
        cUSDFeeAuction.setDuration(newDuration);

        assertEq(cUSDFeeAuction.duration(), newDuration);

        // Should revert when trying to set duration to 0
        vm.prank(env.users.fee_auction_admin);
        vm.expectRevert(IFeeAuction.NoDuration.selector);
        cUSDFeeAuction.setDuration(0);
    }

    function test_setMinStartPrice() public {
        uint256 newMinStartPrice = 500e18;

        // Non-admin should not be able to set min start price
        vm.prank(makeAddr("non_admin"));
        vm.expectRevert();
        cUSDFeeAuction.setMinStartPrice(newMinStartPrice);

        // Admin should be able to set min start price
        vm.prank(env.users.fee_auction_admin);
        vm.expectEmit(false, false, false, true);
        emit IFeeAuction.SetMinStartPrice(newMinStartPrice);
        cUSDFeeAuction.setMinStartPrice(newMinStartPrice);

        assertEq(cUSDFeeAuction.minStartPrice(), newMinStartPrice);
    }
}
