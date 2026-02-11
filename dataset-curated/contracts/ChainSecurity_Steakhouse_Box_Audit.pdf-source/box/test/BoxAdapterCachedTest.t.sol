// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Morpho Association, Steakhouse Financial
pragma solidity ^0.8.28;

import "../lib/forge-std/src/Test.sol";

import {IERC4626} from "../lib/vault-v2/src/interfaces/IERC4626.sol";
import {ERC20Mock} from "../lib/vault-v2/test/mocks/ERC20Mock.sol";
import {ERC4626Mock} from "../lib/vault-v2/test//mocks/ERC4626Mock.sol";
import {VaultV2Mock} from "../lib/vault-v2/test//mocks/VaultV2Mock.sol";
import {WAD} from "../lib/vault-v2/src/VaultV2.sol";
import {IERC20} from "../lib/vault-v2/src/interfaces/IERC20.sol";
import {IERC20 as IERC20OZ} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IVaultV2} from "../lib/vault-v2/src/interfaces/IVaultV2.sol";
import {MathLib} from "../lib/vault-v2/src/libraries/MathLib.sol";

import {Box} from "../src/Box.sol";
import {IBox, IBoxFlashCallback} from "../src/interfaces/IBox.sol";
import {IBoxAdapter} from "../src/interfaces/IBoxAdapter.sol";
import {BoxAdapterCached} from "../src/BoxAdapterCached.sol";
import {IBoxAdapterFactory} from "../src/interfaces/IBoxAdapterFactory.sol";
import {BoxAdapterCachedFactory} from "../src/factories/BoxAdapterCachedFactory.sol";
import {BoxLib} from "../src/periphery/BoxLib.sol";
import {MAX_SHUTDOWN_WARMUP} from "../src/libraries/Constants.sol";
import {ErrorsLib} from "../src/libraries/ErrorsLib.sol";

contract BoxAdapterCachedTest is Test {
    using MathLib for uint256;
    using BoxLib for Box;

    IERC20 internal asset;
    IERC20 internal rewardToken;
    VaultV2Mock internal parentVault;
    Box internal box;
    IBoxAdapterFactory internal factory;
    IBoxAdapter internal adapter;
    address internal owner;
    address internal recipient;
    address internal allocator;
    address internal sentinel;
    bytes32[] internal expectedIds;

    uint256 internal constant MAX_TEST_ASSETS = 1e36;
    uint256 internal constant EXCHANGE_RATE = 42;

    function setUp() public {
        owner = makeAddr("owner");
        recipient = makeAddr("recipient");
        allocator = makeAddr("allocator");
        sentinel = makeAddr("sentinel");

        asset = IERC20(address(new ERC20Mock(18)));
        rewardToken = IERC20(address(new ERC20Mock(18)));
        box = new Box(address(asset), owner, owner, "Box", "BOX", 0, 1, 1, MAX_SHUTDOWN_WARMUP);

        parentVault = new VaultV2Mock(address(asset), owner, address(0), allocator, sentinel);

        factory = new BoxAdapterCachedFactory();
        adapter = IBoxAdapter(factory.createBoxAdapter(address(parentVault), box));

        vm.prank(owner);
        box.addFeederInstant(address(adapter));

        deal(address(asset), address(this), type(uint256).max);
        asset.approve(address(box), type(uint256).max);

        deal(address(asset), address(box), 1);

        // Increase the exchange rate to make so 1 asset is worth EXCHANGE_RATE shares.
        deal(address(box), address(0), EXCHANGE_RATE, true);
        assertEq(box.convertToShares(1), 21, "exchange rate not set correctly");

        expectedIds = new bytes32[](1);
        expectedIds[0] = keccak256(abi.encode("this", address(adapter)));
    }

    function testFactoryAndParentVaultAndAssetSet() public view {
        assertEq(adapter.factory(), address(factory), "Incorrect factory set");
        assertEq(adapter.parentVault(), address(parentVault), "Incorrect parent vault set");
        assertEq(address(adapter.box()), address(box), "Incorrect box vault set");
    }

    function testAllocateNotAuthorizedReverts(uint256 assets) public {
        assets = bound(assets, 0, MAX_TEST_ASSETS);
        vm.expectRevert(IBoxAdapter.NotAuthorized.selector);
        adapter.allocate(hex"", assets, bytes4(0), address(0));
    }

    function testDeallocateNotAuthorizedReverts(uint256 assets) public {
        assets = bound(assets, 0, MAX_TEST_ASSETS);
        vm.expectRevert(IBoxAdapter.NotAuthorized.selector);
        adapter.deallocate(hex"", assets, bytes4(0), address(0));
    }

    function testAllocate(uint256 assets) public {
        assets = bound(assets, 0, MAX_TEST_ASSETS);
        deal(address(asset), address(adapter), assets);

        (bytes32[] memory ids, int256 change) = parentVault.allocateMocked(address(adapter), hex"", assets);

        uint256 adapterShares = box.balanceOf(address(adapter));
        uint256 expectedShares = box.convertToShares(assets);
        assertEq(adapterShares, expectedShares, "Incorrect share balance after deposit");
        assertEq(asset.balanceOf(address(adapter)), 0, "Underlying tokens not transferred to vault");
        assertEq(ids, expectedIds, "Incorrect ids returned");
        // Allow for 1 wei rounding due to virtual shares
        assertApproxEqAbs(uint256(change), assets, 1, "Incorrect change returned");
    }

    function testDeallocate(uint256 initialAssets, uint256 withdrawAssets) public {
        initialAssets = bound(initialAssets, 0, MAX_TEST_ASSETS);

        deal(address(asset), address(adapter), initialAssets);
        parentVault.allocateMocked(address(adapter), hex"", initialAssets);

        uint256 beforeShares = box.balanceOf(address(adapter));
        uint256 expectedInitialShares = box.convertToShares(initialAssets);
        assertEq(beforeShares, expectedInitialShares, "Precondition failed: shares not set");

        // Get the actual redeemable assets to account for rounding with virtual shares
        uint256 actualRedeemableAssets = box.previewRedeem(beforeShares);
        withdrawAssets = bound(withdrawAssets, 0, actualRedeemableAssets);

        (bytes32[] memory ids, int256 change) = parentVault.deallocateMocked(address(adapter), hex"", withdrawAssets);

        // Allow for 1 wei rounding due to virtual shares
        assertApproxEqAbs(adapter.allocation(), actualRedeemableAssets - withdrawAssets, 1, "incorrect allocation");
        uint256 afterShares = box.balanceOf(address(adapter));
        uint256 remainingAssets = actualRedeemableAssets - withdrawAssets;
        uint256 expectedRemainingShares = remainingAssets == 0 ? 0 : box.convertToShares(remainingAssets);
        // Allow approximate equality due to rounding with small amounts and virtual shares
        assertApproxEqAbs(afterShares, expectedRemainingShares, beforeShares, "Share balance not decreased correctly");

        uint256 adapterBalance = asset.balanceOf(address(adapter));
        assertEq(adapterBalance, withdrawAssets, "Adapter did not receive withdrawn tokens");
        assertEq(ids, expectedIds, "Incorrect ids returned");
        // Allow for 1 wei rounding due to virtual shares
        assertApproxEqAbs(uint256(-change), withdrawAssets, 1, "Incorrect change returned");
    }

    function testFactoryCreateAdapter() public {
        VaultV2Mock newParentVault = new VaultV2Mock(address(asset), owner, address(0), address(0), address(0));
        Box newBox = new Box(address(asset), owner, owner, "Box2", "BOX2", 0, 1, 1, MAX_SHUTDOWN_WARMUP);

        vm.expectEmit(true, true, false, false);
        emit IBoxAdapterFactory.CreateBoxAdapter(address(newParentVault), address(newBox), IBoxAdapter(address(0)));
        address newAdapter = address(factory.createBoxAdapter(address(newParentVault), newBox));

        expectedIds[0] = keccak256(abi.encode("this", address(newAdapter)));

        assertTrue(newAdapter != address(0), "Adapter not created");
        assertEq(IBoxAdapter(newAdapter).factory(), address(factory), "Incorrect factory");
        assertEq(IBoxAdapter(newAdapter).parentVault(), address(newParentVault), "Incorrect parent vault");
        assertEq(address(IBoxAdapter(newAdapter).box()), address(newBox), "Incorrect Box");
        assertEq(IBoxAdapter(newAdapter).adapterId(), expectedIds[0], "Incorrect adapterId");
        assertEq(address(factory.boxAdapter(address(newParentVault), newBox)), newAdapter, "Adapter not tracked correctly");
        assertTrue(factory.isBoxAdapter(address(newAdapter)), "Adapter not tracked correctly");
    }

    function testSetSkimRecipient(address newRecipient, address caller) public {
        vm.assume(newRecipient != address(0));
        vm.assume(caller != address(0));
        vm.assume(caller != owner);

        // Access control
        vm.prank(caller);
        vm.expectRevert(IBoxAdapter.NotAuthorized.selector);
        adapter.setSkimRecipient(newRecipient);

        // Normal path
        vm.prank(owner);
        vm.expectEmit();
        emit IBoxAdapter.SetSkimRecipient(newRecipient);
        adapter.setSkimRecipient(newRecipient);
        assertEq(adapter.skimRecipient(), newRecipient, "Skim recipient not set correctly");
    }

    function testSkim(uint256 assets) public {
        assets = bound(assets, 0, MAX_TEST_ASSETS);

        ERC20Mock token = new ERC20Mock(18);

        // Setup
        vm.prank(owner);
        adapter.setSkimRecipient(recipient);
        deal(address(token), address(adapter), assets);
        assertEq(token.balanceOf(address(adapter)), assets, "Adapter did not receive tokens");

        // Normal path
        vm.expectEmit();
        emit IBoxAdapter.Skim(address(token), assets);
        vm.prank(recipient);
        adapter.skim(address(token));
        assertEq(token.balanceOf(address(adapter)), 0, "Tokens not skimmed from adapter");
        assertEq(token.balanceOf(recipient), assets, "Recipient did not receive tokens");

        // Access control
        vm.expectRevert(IBoxAdapter.NotAuthorized.selector);
        adapter.skim(address(token));

        // Can't skim morphoVaultV1
        vm.prank(recipient);
        vm.expectRevert(IBoxAdapter.CannotSkimBoxShares.selector);
        adapter.skim(address(box));
    }

    function testIds() public view {
        assertEq(adapter.ids(), expectedIds);
    }

    function testInvalidData(bytes memory data) public {
        vm.assume(data.length > 0);

        vm.expectRevert(IBoxAdapter.InvalidData.selector);
        adapter.allocate(data, 0, bytes4(0), address(0));

        vm.expectRevert(IBoxAdapter.InvalidData.selector);
        adapter.deallocate(data, 0, bytes4(0), address(0));
    }

    function testDifferentAssetReverts(address randomAsset) public {
        vm.assume(randomAsset != parentVault.asset());
        vm.assume(randomAsset != address(0));

        // Mock the decimals() call to return 18 so Box constructor doesn't revert
        vm.mockCall(randomAsset, abi.encodeWithSignature("decimals()"), abi.encode(uint8(18)));

        Box newBox = new Box(randomAsset, owner, owner, "Box2", "BOX2", 0, 1, 1, MAX_SHUTDOWN_WARMUP);

        vm.clearMockedCalls();

        vm.expectRevert(IBoxAdapter.AssetMismatch.selector);
        new BoxAdapterCached(address(parentVault), newBox);
    }

    function testDonationResistance(uint256 deposit, uint256 donation) public {
        deposit = bound(deposit, 0, MAX_TEST_ASSETS);
        donation = bound(donation, 1, MAX_TEST_ASSETS);

        Box otherBox = new Box(address(asset), owner, owner, "Box Mock Extended", "BOX_MOCK_EXTENDED", 0, 1, 1, MAX_SHUTDOWN_WARMUP);

        // Deposit some assets
        deal(address(asset), address(adapter), deposit * 2);
        parentVault.allocateMocked(address(adapter), hex"", deposit);

        uint256 realAssetsBefore = adapter.realAssets();

        // Donate to adapter
        address donor = makeAddr("donor");

        vm.startPrank(owner);
        otherBox.addFeederInstant(donor);
        otherBox.addFeederInstant(address(adapter));
        vm.stopPrank();

        assertTrue(otherBox.isFeeder(donor), "Donor is not a feeder");

        deal(address(asset), donor, donation);
        vm.startPrank(donor);
        asset.approve(address(otherBox), type(uint256).max);
        otherBox.deposit(donation, address(adapter));
        vm.stopPrank();

        uint256 realAssetsAfter = adapter.realAssets();

        assertEq(realAssetsAfter, realAssetsBefore, "realAssets should not change");
    }

    function testLoss(uint256 deposit, uint256 loss) public {
        deposit = bound(deposit, 1, MAX_TEST_ASSETS);
        loss = bound(loss, 1, deposit);

        deal(address(asset), address(adapter), deposit);
        parentVault.allocateMocked(address(adapter), hex"", deposit);

        vm.startPrank(address(box));
        asset.transfer(address(0xdead), loss);
        vm.stopPrank();

        // Allow for 1 wei rounding due to virtual shares
        assertApproxEqAbs(adapter.realAssets(), deposit, 1, "No loss yet seen");

        vm.prank(allocator);
        BoxAdapterCached(address(adapter)).updateTotalAssets();

        // Allow for rounding due to virtual shares +1 in totalAssets
        assertApproxEqAbs(adapter.realAssets(), deposit - loss, 1, "After update, the loss is recognized");
    }

    function testInterest(uint256 deposit, uint256 interest) public {
        deposit = bound(deposit, 1, MAX_TEST_ASSETS);
        interest = bound(interest, 1, deposit);

        deal(address(asset), address(adapter), deposit);
        parentVault.allocateMocked(address(adapter), hex"", deposit);

        asset.transfer(address(box), interest);

        uint256 realAssetsBefore = adapter.realAssets();
        // Allow for 1 wei rounding due to virtual shares
        assertApproxEqAbs(realAssetsBefore, deposit, 1, "Only see deposit, no interests");

        vm.prank(allocator);
        BoxAdapterCached(address(adapter)).updateTotalAssets();

        uint256 realAssetsAfter = adapter.realAssets();
        // Handle rounding - may be slightly less than expected due to virtual shares
        if (realAssetsAfter >= deposit) {
            assertApproxEqAbs(realAssetsAfter - deposit, interest - 1, 1, "Also see interests");
        } else {
            assertApproxEqAbs(realAssetsAfter, deposit + interest - 1, 2, "Also see interests with rounding");
        }
    }

    function testUpdateAssets(uint256 deposit, uint256 interest) public {
        deposit = bound(deposit, 1, MAX_TEST_ASSETS);
        interest = bound(interest, 1, deposit);

        assertEq(adapter.realAssets(), 0, "Starts empty");

        deal(address(asset), address(adapter), deposit);
        parentVault.allocateMocked(address(adapter), hex"", deposit);

        uint256 realAssetsAfterDeposit = adapter.realAssets();
        // Allow for 1 wei rounding due to virtual shares
        assertApproxEqAbs(realAssetsAfterDeposit, deposit, 1, "Deposit recognized");

        asset.transfer(address(box), interest);

        uint256 realAssetsBeforeUpdate = adapter.realAssets();
        assertApproxEqAbs(realAssetsBeforeUpdate, deposit, 1, "Interest not seen yet");

        vm.prank(allocator);
        BoxAdapterCached(address(adapter)).updateTotalAssets();

        uint256 realAssetsAfterUpdate = adapter.realAssets();
        // Handle rounding - may be slightly less than expected due to virtual shares
        if (realAssetsAfterUpdate >= deposit) {
            assertApproxEqAbs(realAssetsAfterUpdate - deposit, interest - 1, 1, "Also see interests");
        } else {
            assertApproxEqAbs(realAssetsAfterUpdate, deposit + interest - 1, 2, "Also see interests with rounding");
        }

        // Just also check the guardian can update
        vm.prank(sentinel);
        BoxAdapterCached(address(adapter)).updateTotalAssets();
    }

    function testUpdateAssetsNotAllowed(address unknown) public {
        vm.assume(unknown != address(sentinel));
        vm.assume(unknown != address(allocator));

        vm.startPrank(unknown);
        vm.expectRevert(IBoxAdapter.NotAuthorized.selector);
        BoxAdapterCached(address(adapter)).updateTotalAssets();
        vm.stopPrank();
    }

    /// @notice Test that VaultV2 forceDeallocate during a flash operation is prevented
    /// @dev This tests the attack scenario where an attacker could:
    ///      1. Call flash() on the Box - which caches NAV with flash tokens temporarily in Box
    ///      2. In the callback, trigger forceDeallocate on VaultV2 -> BoxAdapterCached.deallocate -> Box.withdraw
    ///      3. The inflated cached NAV would give more shares than deserved
    ///      Solution: Box.withdraw reverts with ReentryNotAllowed during flash operations
    function testFlashWithVaultV2WithdrawRevertsReentryNotAllowed() public {
        uint256 depositAmount = 1000e18;

        // Setup: deposit some assets through the adapter
        deal(address(asset), address(adapter), depositAmount);
        parentVault.allocateMocked(address(adapter), hex"", depositAmount);

        // Create a malicious flash callback that tries to withdraw via adapter during flash
        MaliciousVaultV2FlashCallback maliciousCallback = new MaliciousVaultV2FlashCallback(
            box,
            IERC20OZ(address(asset)),
            parentVault,
            adapter
        );

        // Make the malicious callback an allocator so it can call flash
        vm.prank(owner);
        box.setIsAllocator(address(maliciousCallback), true);

        // Give the callback some asset tokens for the flash operation
        deal(address(asset), address(maliciousCallback), 100e18);

        // The flash callback will attempt to deallocate from VaultV2 during flash
        // This should revert with ReentryNotAllowed because Box.withdraw is blocked during flash
        vm.expectRevert(ErrorsLib.ReentryNotAllowed.selector);
        vm.prank(address(maliciousCallback));
        maliciousCallback.executeFlashAttack(100e18);
    }
}

/// @notice Malicious flash callback that attempts to deallocate from VaultV2 during a Box flash operation
contract MaliciousVaultV2FlashCallback is IBoxFlashCallback {
    IBox public immutable box;
    IERC20OZ public immutable asset;
    VaultV2Mock public immutable parentVault;
    IBoxAdapter public immutable adapter;

    constructor(Box _box, IERC20OZ _asset, VaultV2Mock _parentVault, IBoxAdapter _adapter) {
        box = IBox(address(_box));
        asset = _asset;
        parentVault = _parentVault;
        adapter = _adapter;
    }

    function executeFlashAttack(uint256 flashAmount) external {
        asset.approve(address(box), flashAmount);
        box.flash(IERC20OZ(address(asset)), flashAmount, "");
    }

    function onBoxFlash(IERC20OZ, uint256, bytes calldata) external override {
        // During flash, try to deallocate from VaultV2 which would call Box.withdraw
        // This simulates the attack scenario described in the audit
        parentVault.deallocateMocked(address(adapter), hex"", 100e18);
    }
}

function zeroFloorSub(uint256 a, uint256 b) pure returns (uint256) {
    if (a < b) return 0;
    return a - b;
}
