// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.26;

import {UtilsLib} from "../src/libraries/UtilsLib.sol";

import "./helpers/BaseTest.sol";
import {EulerEarnMock} from "./mocks/EulerEarnMock.sol";

contract EulerEarnInternalTest is BaseTest {
    using UtilsLib for uint256;
    using MathLib for uint256;

    EulerEarnMock internal eulerEarnMock;

    function setUp() public virtual override {
        super.setUp();

        eulerEarnMock =
            new EulerEarnMock(OWNER, address(evc), permit2, 1 days, address(loanToken), "EulerEarn Vault", "EEV");

        vm.startPrank(OWNER);
        eulerEarnMock.setCurator(CURATOR);
        eulerEarnMock.setIsAllocator(ALLOCATOR, true);
        vm.stopPrank();

        vm.startPrank(SUPPLIER);
        loanToken.approve(address(eulerEarnMock), type(uint256).max);
        collateralToken.approve(address(eulerEarnMock), type(uint256).max);
        vm.stopPrank();
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testSetCapMaxQueueLengthExcedeed() public {
        for (uint256 i; i < NB_MARKETS - 1; ++i) {
            eulerEarnMock.mockSetCap(allMarkets[i], CAP);
        }

        vm.expectRevert(ErrorsLib.MaxQueueLengthExceeded.selector);
        eulerEarnMock.mockSetCap(allMarkets[NB_MARKETS - 1], CAP);
    }

    function testSimulateWithdraw(uint256 suppliedAmount, uint256 borrowedAmount, uint256 assets) public {
        suppliedAmount = bound(suppliedAmount, MIN_TEST_ASSETS, MAX_TEST_ASSETS);
        borrowedAmount = bound(borrowedAmount, MIN_TEST_ASSETS, suppliedAmount);

        eulerEarnMock.mockSetCap(allMarkets[0], CAP);

        IERC4626[] memory ids = new IERC4626[](1);
        ids[0] = allMarkets[0];
        eulerEarnMock.mockSetSupplyQueue(ids);

        loanToken.setBalance(SUPPLIER, suppliedAmount);
        vm.prank(SUPPLIER);
        eulerEarnMock.deposit(suppliedAmount, SUPPLIER);
        uint256 ltvWithExtra = _toEVault(allMarkets[0]).LTVBorrow(address(collateralVault)) - 1;
        uint256 collateral = suppliedAmount.mulDivUp(1e4, ltvWithExtra);

        collateralToken.setBalance(BORROWER, collateral);

        vm.startPrank(BORROWER);
        collateralVault.deposit(collateral, BORROWER);
        evc.enableController(BORROWER, address(allMarkets[0]));
        _toEVault(allMarkets[0]).borrow(borrowedAmount, BORROWER);
        vm.stopPrank();

        uint256 remaining = eulerEarnMock.mockSimulateWithdrawStrategy(assets);

        uint256 expectedWithdrawable = _expectedSupplyAssets(allMarkets[0], address(eulerEarnMock)) - borrowedAmount;
        uint256 expectedRemaining = assets.zeroFloorSub(expectedWithdrawable);

        assertEq(remaining, expectedRemaining, "remaining");
    }
}
