// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.26;

import "./helpers/IntegrationTest.sol";

contract LostAssetsTest is IntegrationTest {
    using stdStorage for StdStorage;
    using MathLib for uint256;

    address internal LIQUIDATOR;

    function setUp() public override {
        super.setUp();

        _setCap(allMarkets[0], CAP);
        _sortSupplyQueueIdleLast();

        LIQUIDATOR = makeAddr("Liquidator");
    }

    function accrueInterestBySettingFeeRecipient() internal {
        vm.startPrank(OWNER);
        vault.setFeeRecipient(address(uint160(uint256(keccak256(abi.encode(vault.feeRecipient()))))));
        vm.stopPrank();
    }

    function testWriteTotalSupplyAssets(uint112 newValue) public {
        _toEVaultMock(allMarkets[0]).mockSetTotalSupply(newValue);

        assertEq(_toEVaultMock(allMarkets[0]).totalAssets(), newValue);
    }

    function testTotalAssetsNoDecrease(uint256 assets, uint112 expectedLostAssets) public {
        assets = bound(assets, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        loanToken.setBalance(SUPPLIER, assets);

        vm.prank(SUPPLIER);
        vault.deposit(assets, ONBEHALF);

        uint256 totalAssetsBeforeVault = allMarkets[0].totalAssets();
        expectedLostAssets = uint112(bound(expectedLostAssets, 0, totalAssetsBeforeVault));

        uint256 totalAssetsBefore = vault.totalAssets();
        _toEVaultMock(allMarkets[0]).mockSetTotalSupply(uint112(totalAssetsBeforeVault - expectedLostAssets));

        uint256 totalAssetsAfter = vault.totalAssets();

        assertEq(totalAssetsAfter, totalAssetsBefore, "totalAssets decreased");
    }

    function testLastTotalAssetsNoDecrease(uint256 assets, uint112 expectedLostAssets) public {
        assets = bound(assets, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        loanToken.setBalance(SUPPLIER, assets);

        vm.prank(SUPPLIER);
        vault.deposit(assets, ONBEHALF);

        uint256 totalAssetsBeforeVault = allMarkets[0].totalAssets();
        expectedLostAssets = uint112(bound(expectedLostAssets, 0, totalAssetsBeforeVault));

        uint256 lastTotalAssetsBefore = vault.lastTotalAssets();
        _toEVaultMock(allMarkets[0]).mockSetTotalSupply(uint112(totalAssetsBeforeVault - expectedLostAssets));
        accrueInterestBySettingFeeRecipient(); // update lostAssets.
        uint256 lastTotalAssetsAfter = vault.lastTotalAssets();

        assertGe(lastTotalAssetsAfter, lastTotalAssetsBefore, "totalAssets decreased");
    }

    function testLostAssetsValue() public {
        loanToken.setBalance(SUPPLIER, 1 ether);

        vm.prank(SUPPLIER);
        vault.deposit(1 ether, ONBEHALF);

        _toEVaultMock(allMarkets[0]).mockSetTotalSupply(0.5 ether);

        accrueInterestBySettingFeeRecipient(); // update lostAssets.

        // virtual deposit will be entitled to part of the remaining assets
        assertApproxEqAbs(vault.lostAssets(), 0.5 ether, 0.5e6, "expected lostAssets");
    }

    function testLostAssetsValueFuzz(uint256 assets, uint112 expectedLostAssets) public returns (uint112, uint256) {
        assets = bound(assets, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        loanToken.setBalance(SUPPLIER, assets);

        vm.prank(SUPPLIER);
        vault.deposit(assets, ONBEHALF);

        uint256 totalAssetsBeforeVault = allMarkets[0].totalAssets();
        expectedLostAssets = uint112(bound(expectedLostAssets, 0, totalAssetsBeforeVault));

        _toEVaultMock(allMarkets[0]).mockSetTotalSupply(uint112(totalAssetsBeforeVault - expectedLostAssets));

        accrueInterestBySettingFeeRecipient(); // update lostAssets.

        assertApproxEqAbs(
            vault.lostAssets(),
            expectedLostAssets,
            uint256(expectedLostAssets) * 1e6 / totalAssetsBeforeVault,
            "expected lostAssets"
        );

        return (expectedLostAssets, totalAssetsBeforeVault);
    }

    function testResupplyOnLostAssets(uint256 assets, uint112 expectedLostAssets, uint256 assets2) public {
        uint256 totalAssetsBeforeVault;
        (expectedLostAssets, totalAssetsBeforeVault) = testLostAssetsValueFuzz(assets, expectedLostAssets);

        assets2 = bound(assets2, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        loanToken.setBalance(SUPPLIER, assets2);

        vm.prank(SUPPLIER);
        vault.deposit(assets2, ONBEHALF);

        assertApproxEqAbs(
            vault.lostAssets(),
            expectedLostAssets,
            uint256(expectedLostAssets) * 1e6 / totalAssetsBeforeVault,
            "lostAssets after resupply"
        );
    }

    function testNewLostAssetsOnLostAssets(
        uint256 firstSupply,
        uint112 firstLostAssets,
        uint256 secondSupply,
        uint112 secondLostAssets
    ) public {
        uint256 totalAssetsBeforeVault;
        (firstLostAssets, totalAssetsBeforeVault) = testLostAssetsValueFuzz(firstSupply, firstLostAssets);

        secondSupply = bound(secondSupply, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        loanToken.setBalance(SUPPLIER, secondSupply);

        vm.prank(SUPPLIER);
        vault.deposit(secondSupply, ONBEHALF);

        uint256 totalAssetsBeforeVaultSecond = allMarkets[0].totalAssets();
        secondLostAssets = uint112(bound(secondLostAssets, 0, totalAssetsBeforeVaultSecond));

        _toEVaultMock(allMarkets[0]).mockSetTotalSupply(uint112(totalAssetsBeforeVaultSecond - secondLostAssets));

        accrueInterestBySettingFeeRecipient(); // update lostAssets.

        assertApproxEqAbs(
            vault.lostAssets(),
            firstLostAssets + secondLostAssets,
            uint256(firstLostAssets + secondLostAssets) * 1e6 / totalAssetsBeforeVault,
            "lostAssets after new loss"
        );
    }

    function testLostAssetsEvent(uint256 assets, uint112 expectedLostAssets) public {
        assets = bound(assets, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        loanToken.setBalance(SUPPLIER, assets);

        vm.prank(SUPPLIER);
        vault.deposit(assets, ONBEHALF);

        uint256 totalAssetsBeforeVault = allMarkets[0].totalAssets();
        expectedLostAssets = uint112(bound(expectedLostAssets, 0, totalAssetsBeforeVault));

        _toEVaultMock(allMarkets[0]).mockSetTotalSupply(uint112(totalAssetsBeforeVault - expectedLostAssets));

        uint256 snapshotId = vm.snapshotState();
        accrueInterestBySettingFeeRecipient(); // update lostAssets.
        uint256 actuallyLost = vault.lostAssets();
        vm.revertToState(snapshotId);

        vm.expectEmit();
        emit EventsLib.UpdateLostAssets(actuallyLost);
        accrueInterestBySettingFeeRecipient(); // update lostAssets.

        assertApproxEqAbs(
            vault.lostAssets(),
            expectedLostAssets,
            uint256(expectedLostAssets) * 1e6 / totalAssetsBeforeVault,
            "lostAssets after resupply"
        );
    }

    function testMaxWithdrawWithLostAssets(uint256 assets, uint112 expectedLostAssets) public {
        assets = bound(assets, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        loanToken.setBalance(SUPPLIER, assets);

        vm.prank(SUPPLIER);
        vault.deposit(assets, ONBEHALF);

        uint256 totalAssetsBeforeVault = allMarkets[0].totalAssets();
        expectedLostAssets = uint112(bound(expectedLostAssets, 1, totalAssetsBeforeVault));

        assertEq(vault.maxWithdraw(ONBEHALF), totalAssetsBeforeVault);

        _toEVaultMock(allMarkets[0]).mockSetTotalSupply(uint112(totalAssetsBeforeVault - expectedLostAssets));

        accrueInterestBySettingFeeRecipient(); // update lostAssets.

        assertApproxEqAbs(vault.maxWithdraw(ONBEHALF), totalAssetsBeforeVault - expectedLostAssets, 1);
    }

    function testInterestAccrualWithLostAssets(uint256 assets, uint112 expectedLostAssets, uint112 interest) public {
        uint256 totalAssetsBeforeFirst;
        (expectedLostAssets, totalAssetsBeforeFirst) = testLostAssetsValueFuzz(assets, expectedLostAssets);

        uint256 totalAssetsBeforeVault = allMarkets[0].totalAssets();
        interest = uint112(bound(interest, 1, type(uint112).max - totalAssetsBeforeVault));

        _toEVaultMock(allMarkets[0]).mockSetTotalSupply(uint112(totalAssetsBeforeVault + interest));

        uint256 expectedTotalAssets = _expectedSupplyAssets(allMarkets[0], address(vault));
        uint256 totalAssetsAfter = vault.totalAssets();

        assertApproxEqAbs(
            totalAssetsAfter,
            expectedTotalAssets + expectedLostAssets,
            uint256(expectedLostAssets) * 1e6 / totalAssetsBeforeFirst
        );
    }

    function testDonationWithLostAssets(uint256 assets, uint112 expectedLostAssets, uint256 donation) public {
        uint256 totalAssetsBeforeVault;
        (expectedLostAssets, totalAssetsBeforeVault) = testLostAssetsValueFuzz(assets, expectedLostAssets);

        donation = bound(donation, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        uint256 totalAssetsBefore = vault.totalAssets();

        loanToken.setBalance(SUPPLIER, donation);
        vm.prank(SUPPLIER);
        allMarkets[0].deposit(donation, address(vault));

        uint256 totalAssetsAfter = vault.totalAssets();

        // internal balance tracking does not recognize the donation
        assertApproxEqAbs(totalAssetsAfter, totalAssetsBefore, 1);
    }

    function testForcedMarketRemoval(uint256 assets0, uint256 assets1) public {
        assets0 = bound(assets0, MIN_TEST_ASSETS, MAX_TEST_ASSETS);
        assets1 = bound(assets1, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        _setCap(allMarkets[0], type(uint112).max);
        IERC4626[] memory supplyQueue = new IERC4626[](1);
        supplyQueue[0] = allMarkets[0];
        vm.prank(CURATOR);
        vault.setSupplyQueue(supplyQueue);

        loanToken.setBalance(SUPPLIER, assets0);
        vm.prank(SUPPLIER);
        vault.deposit(assets0, address(vault));

        _setCap(allMarkets[1], type(uint112).max);
        supplyQueue[0] = allMarkets[1];
        vm.prank(CURATOR);
        vault.setSupplyQueue(supplyQueue);

        loanToken.setBalance(SUPPLIER, assets1);
        vm.prank(SUPPLIER);
        vault.deposit(assets1, address(vault));

        _setCap(allMarkets[0], 0);
        vm.prank(CURATOR);
        vault.submitMarketRemoval(allMarkets[0]);
        vm.warp(block.timestamp + vault.timelock());

        uint256 totalAssetsBefore = vault.totalAssets();

        uint256[] memory withdrawQueue = new uint256[](2);
        withdrawQueue[0] = 0;
        withdrawQueue[1] = 2;
        vm.prank(CURATOR);
        vault.updateWithdrawQueue(withdrawQueue);

        uint256 totalAssetsAfter = vault.totalAssets();

        accrueInterestBySettingFeeRecipient(); // update lostAssets.

        assertEq(totalAssetsBefore, totalAssetsAfter);
        assertEq(vault.lostAssets(), assets0);
    }

    function testLostAssetsAfterBadDebt(uint256 borrowed, uint256 collateral, uint256 deposit) public {
        borrowed = bound(borrowed, MIN_TEST_ASSETS, MAX_TEST_ASSETS);
        collateral = bound(
            collateral,
            borrowed.mulDivUp(1e4, _toEVault(allMarkets[0]).LTVBorrow(address(collateralVault))) + 0.01e4,
            type(uint112).max - 1
        );
        deposit = bound(deposit, borrowed, MAX_TEST_ASSETS);

        collateralToken.setBalance(BORROWER, collateral);
        collateralToken.setBalance(LIQUIDATOR, collateral);
        loanToken.setBalance(LIQUIDATOR, borrowed);
        loanToken.setBalance(SUPPLIER, deposit);

        vm.prank(SUPPLIER);
        vault.deposit(deposit, ONBEHALF);

        vm.startPrank(BORROWER);
        collateralVault.deposit(collateral, BORROWER);
        evc.enableController(BORROWER, address(allMarkets[0]));
        _toEVault(allMarkets[0]).borrow(borrowed, BORROWER);

        vm.stopPrank();

        oracle.setPrice(address(collateralToken), unitOfAccount, 0);

        vm.startPrank(LIQUIDATOR);
        collateralToken.approve(address(collateralVault), type(uint256).max);
        collateralVault.deposit(1, LIQUIDATOR); // collateral value must be strictly gt than liability
        evc.enableController(LIQUIDATOR, address(allMarkets[0]));
        evc.enableCollateral(LIQUIDATOR, address(collateralVault));

        _toEVault(allMarkets[0]).liquidate(BORROWER, address(collateralVault), 0, 0);
        vm.stopPrank();

        uint256 totalAssetsBefore = vault.totalAssets();

        assertEq(vault.lostAssets(), 0);

        accrueInterestBySettingFeeRecipient(); // update lostAssets.

        assertApproxEqAbs(vault.lostAssets(), borrowed, 1e6);
        assertEq(totalAssetsBefore, vault.totalAssets());
    }

    function testCoverLostAssets(uint256 assets, uint112 expectedLostAssets) public {
        assets = bound(assets, MIN_TEST_ASSETS, MAX_TEST_ASSETS);

        loanToken.setBalance(SUPPLIER, assets);

        vm.prank(SUPPLIER);
        vault.deposit(assets, ONBEHALF);

        uint256 totalAssetsBeforeVault = allMarkets[0].totalAssets();
        expectedLostAssets = uint112(bound(expectedLostAssets, 0, totalAssetsBeforeVault));

        _toEVaultMock(allMarkets[0]).mockSetTotalSupply(uint112(totalAssetsBeforeVault - expectedLostAssets));

        loanToken.setBalance(address(this), expectedLostAssets + 1);
        loanToken.approve(address(vault), expectedLostAssets + 1);
        vault.deposit(expectedLostAssets + 1, address(1));

        vm.prank(ONBEHALF);
        vault.withdraw(assets, ONBEHALF, ONBEHALF);
    }

    function testSupplyCanCreateLostAssets() public {
        _setCap(allMarkets[0], type(uint112).max);
        IERC4626[] memory supplyQueue = new IERC4626[](1);
        supplyQueue[0] = allMarkets[0];
        vm.prank(CURATOR);
        vault.setSupplyQueue(supplyQueue);

        uint256 assets0 = 1 ether;

        loanToken.setBalance(SUPPLIER, assets0);
        collateralToken.setBalance(BORROWER, type(uint112).max);

        vm.prank(SUPPLIER);
        allMarkets[0].deposit(assets0, SUPPLIER);

        vm.startPrank(BORROWER);
        collateralVault.deposit(type(uint256).max, BORROWER);
        evc.enableController(BORROWER, address(allMarkets[0]));
        _toEVault(allMarkets[0]).borrow(assets0, BORROWER);
        vm.stopPrank();

        // WARP
        // irm.setApr(1e18);
        vm.warp(block.timestamp + 1000);
        _toEVault(allMarkets[0]).touch();

        loanToken.setBalance(address(this), 2);
        vault.deposit(2, address(this));

        accrueInterestBySettingFeeRecipient();

        assertEq(vault.lostAssets(), 1);
    }

    function testWithdrawCanCreateLostAssets() public {
        uint256 assets = 1e6;
        uint112 newTotalSupplyAssets = 2e6;

        _setCap(allMarkets[0], type(uint112).max);
        IERC4626[] memory supplyQueue = new IERC4626[](1);
        supplyQueue[0] = allMarkets[0];
        vm.prank(CURATOR);
        vault.setSupplyQueue(supplyQueue);

        loanToken.setBalance(address(this), assets);
        vault.deposit(assets, address(this));

        _toEVaultMock(allMarkets[0]).mockSetTotalSupply(newTotalSupplyAssets);

        loanToken.setBalance(address(allMarkets[0]), type(uint112).max);
        uint256 maxWithdraw = vault.maxWithdraw(address(this));
        vault.withdraw(maxWithdraw, address(this), address(this));

        // Call to update lostAssets.
        accrueInterestBySettingFeeRecipient();

        assertEq(vault.lostAssets(), 1);
    }
}
