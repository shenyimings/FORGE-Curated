// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { Test } from "forge-std/Test.sol";

import { IERC20Metadata } from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";

import {
    ControlledERC7575Vault as Vault,
    IController,
    IERC20,
    IERC7575Vault,
    IControlledVault,
    ReentrancyGuardTransient
} from "../../../src/vault/ControlledERC7575Vault.sol";

import { ControlledERC7575VaultHarness as VaultHarness } from "../../harness/ControlledERC7575VaultHarness.sol";
import { ReentrancySpy } from "../../helper/ReentrancySpy.sol";

abstract contract ControlledERC7575VaultTest is Test {
    VaultHarness vault;

    address asset = makeAddr("asset");
    address controller = makeAddr("controller");

    function _mockDecimals(uint256 decimals) internal returns (uint256) {
        decimals = bound(decimals, 0, 18);
        vm.mockCall(asset, abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(decimals));
        vault = new VaultHarness(IERC20(asset), IController(controller));
        return decimals;
    }

    function setUp() public virtual {
        vm.mockCall(asset, abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(18));

        vm.mockCall(asset, abi.encodeWithSelector(IERC20.balanceOf.selector), abi.encode(0));
        vm.mockCall(asset, abi.encodeWithSelector(IERC20.transfer.selector), abi.encode(true));
        vm.mockCall(asset, abi.encodeWithSelector(IERC20.transferFrom.selector), abi.encode(true));

        vault = new VaultHarness(IERC20(asset), IController(controller));
    }
}

contract ControlledERC7575Vault_Constructor_Test is ControlledERC7575VaultTest {
    function test_shouldSetInitialValues() public view {
        assertEq(vault.asset(), asset);
        assertEq(vault.controller(), controller);
    }

    function test_shouldRevert_whenZeroAsset() public {
        vm.expectRevert(Vault.ZeroAsset.selector);
        new Vault(IERC20(address(0)), IController(controller));
    }

    function test_shouldRevert_whenZeroController() public {
        vm.expectRevert(Vault.ZeroController.selector);
        new Vault(IERC20(asset), IController(address(0)));
    }

    function test_shouldRevert_whenNoDecimals() public {
        vm.mockCall(asset, abi.encodeWithSelector(IERC20Metadata.decimals.selector), "");

        vm.expectRevert(Vault.NoDecimals.selector);
        new Vault(IERC20(asset), IController(controller));
    }

    function testFuzz_shouldRevert_whenAssetDecimalsTooHigh(uint256 decimals) public {
        decimals = bound(decimals, vault.NORMALIZED_ASSET_DECIMALS() + 1, type(uint8).max);
        vm.mockCall(asset, abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(decimals));

        vm.expectRevert(Vault.AssetDecimalsTooHigh.selector);
        new Vault(IERC20(asset), IController(controller));
    }

    function testFuzz_shouldSetDecimalsOffset(uint256 decimals) public {
        decimals = _mockDecimals(decimals);

        assertEq(vault.exposed_decimalsOffset(), 18 - decimals);
    }
}

contract ControlledERC7575Vault_TotalAssets_Test is ControlledERC7575VaultTest {
    function testFuzz_shouldReturnTotalAssets_whenNoAdditionalOwnedAssets(uint256 balance) public {
        vm.mockCall(asset, abi.encodeWithSelector(IERC20.balanceOf.selector, address(vault)), abi.encode(balance));

        assertEq(vault.totalAssets(), balance);
    }

    function testFuzz_shouldReturnTotalAssets_whenWithAdditionalOwnedAssets(
        uint256 balance,
        uint256 additional
    )
        public
    {
        vm.assume(type(uint256).max - balance >= additional); // prevent overflow

        vm.mockCall(asset, abi.encodeWithSelector(IERC20.balanceOf.selector, address(vault)), abi.encode(balance));
        vault.workaround_setAdditionalOwnedAssets(additional);

        assertEq(vault.totalAssets(), balance + additional);
    }
}

contract ControlledERC7575Vault_TotalNormalizedAssets_Test is ControlledERC7575VaultTest {
    function testFuzz_shouldReturnTotalNormalizedAssets_whenNoAdditionalOwnedAssets(uint256 decimals) public {
        decimals = _mockDecimals(decimals);

        uint256 balance = 420;
        vm.mockCall(
            asset,
            abi.encodeWithSelector(IERC20.balanceOf.selector, address(vault)),
            abi.encode(balance * 10 ** decimals)
        );

        assertEq(vault.totalNormalizedAssets(), balance * 10 ** 18);
    }

    function testFuzz_shouldReturnTotalNormalizedAssets_whenWithAdditionalOwnedAssets(uint256 decimals) public {
        decimals = _mockDecimals(decimals);

        uint256 balance = 420;
        vm.mockCall(
            asset,
            abi.encodeWithSelector(IERC20.balanceOf.selector, address(vault)),
            abi.encode(balance * 10 ** decimals)
        );
        uint256 additional = 180;
        vault.workaround_setAdditionalOwnedAssets(additional * 10 ** decimals);

        assertEq(vault.totalNormalizedAssets(), uint256(balance + additional) * 10 ** 18);
    }
}

contract ControlledERC7575Vault_ConvertToShares_Test is ControlledERC7575VaultTest {
    function testFuzz_shouldReturnShares(uint256 assets, uint256 decimals) public {
        assets = bound(assets, 1, type(uint256).max / 10 ** 18);
        decimals = _mockDecimals(decimals);

        assertEq(vault.convertToShares(assets), assets * 10 ** (18 - decimals));
    }
}

contract ControlledERC7575Vault_ConvertToAssets_Test is ControlledERC7575VaultTest {
    function testFuzz_shouldReturnAssets(uint256 shares, uint256 decimals) public {
        shares = bound(shares, 1, type(uint256).max / 10 ** 18);
        decimals = _mockDecimals(decimals);

        assertEq(vault.convertToAssets(shares), shares / 10 ** (18 - decimals));
    }
}

contract ControlledERC7575Vault_Deposit_Test is ControlledERC7575VaultTest {
    address caller = makeAddr("caller");
    address receiver = makeAddr("receiver");
    uint256 assets = 420e18;
    uint256 shares = 2 * assets;

    function setUp() public override {
        super.setUp();

        vm.mockCall(controller, abi.encodeWithSelector(IController.deposit.selector), abi.encode(shares));
    }

    function testFuzz_shouldCallControllerDeposit_withNormalizedAssets(uint256 decimals) public {
        decimals = _mockDecimals(decimals);
        uint256 normalizedAssets = assets * 10 ** (18 - decimals);

        vm.expectCall(controller, abi.encodeWithSelector(IController.deposit.selector, normalizedAssets, receiver));

        vm.prank(caller);
        vault.deposit(assets, receiver);
    }

    function test_shouldRevert_whenZeroAssets() public {
        vm.prank(caller);
        vm.expectRevert(Vault.ZeroAssetsOrShares.selector);
        vault.deposit(0, receiver);
    }

    function test_shouldRevert_whenZeroShares() public {
        vm.mockCall(controller, abi.encodeWithSelector(IController.deposit.selector), abi.encode(0));

        vm.prank(caller);
        vm.expectRevert(Vault.ZeroAssetsOrShares.selector);
        vault.deposit(assets, receiver);
    }

    function test_shouldTransferAssetsToVault() public {
        vm.expectCall(asset, abi.encodeWithSelector(IERC20.transferFrom.selector, caller, address(vault), assets));

        vm.prank(caller);
        vault.deposit(assets, receiver);
    }

    function test_shouldCallDepositCallback() public {
        vm.prank(caller);
        vault.deposit(assets, receiver);

        (bool called, uint256 callbackAssets) = vault.afterDepositCallback();
        assertTrue(called);
        assertEq(callbackAssets, assets);
    }

    function test_shouldEmit_Deposit() public {
        vm.expectEmit();
        emit IERC7575Vault.Deposit(caller, receiver, assets, shares);

        vm.prank(caller);
        vault.deposit(assets, receiver);
    }

    function test_shouldReturnShares() public {
        vm.prank(caller);
        assertEq(vault.deposit(assets, receiver), shares);
    }

    function test_shouldRevert_whenReentrant() public {
        ReentrancySpy spy = new ReentrancySpy();

        vm.mockFunction(controller, address(spy), abi.encodeWithSelector(ReentrancySpy.reenter.selector));
        vm.mockFunction(controller, address(spy), abi.encodeWithSelector(IController.deposit.selector));
        ReentrancySpy(controller)
            .reenter(address(vault), abi.encodeWithSelector(Vault.deposit.selector, assets, receiver));

        vm.expectRevert(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector);
        vm.prank(caller);
        vault.deposit(assets, receiver);
    }
}

contract ControlledERC7575Vault_Mint_Test is ControlledERC7575VaultTest {
    address caller = makeAddr("caller");
    address receiver = makeAddr("receiver");
    uint256 assets = 420e18;
    uint256 shares = 2 * assets;

    function setUp() public override {
        super.setUp();

        vm.mockCall(controller, abi.encodeWithSelector(IController.mint.selector), abi.encode(assets));
    }

    function test_shouldCallControllerMint() public {
        vm.expectCall(controller, abi.encodeWithSelector(IController.mint.selector, shares, receiver));

        vm.prank(caller);
        vault.mint(shares, receiver);
    }

    function test_shouldRevert_whenZeroAssets() public {
        vm.mockCall(controller, abi.encodeWithSelector(IController.mint.selector), abi.encode(0));

        vm.prank(caller);
        vm.expectRevert(Vault.ZeroAssetsOrShares.selector);
        vault.mint(shares, receiver);
    }

    function test_shouldRevert_whenZeroShares() public {
        vm.prank(caller);
        vm.expectRevert(Vault.ZeroAssetsOrShares.selector);
        vault.mint(0, receiver);
    }

    function testFuzz_shouldTransferOriginalAssetsToVault(uint256 decimals) public {
        decimals = _mockDecimals(decimals);
        uint256 originalAssets = assets / 10 ** (18 - decimals);

        vm.expectCall(
            asset, abi.encodeWithSelector(IERC20.transferFrom.selector, caller, address(vault), originalAssets)
        );

        vm.prank(caller);
        vault.mint(shares, receiver);
    }

    function test_shouldCallDepositCallback() public {
        vm.prank(caller);
        vault.mint(shares, receiver);

        (bool called, uint256 callbackAssets) = vault.afterDepositCallback();
        assertTrue(called);
        assertEq(callbackAssets, assets);
    }

    function test_shouldEmit_Deposit() public {
        vm.expectEmit();
        emit IERC7575Vault.Deposit(caller, receiver, assets, shares);

        vm.prank(caller);
        vault.mint(shares, receiver);
    }

    function test_shouldReturnAssets() public {
        vm.prank(caller);
        assertEq(vault.mint(shares, receiver), assets);
    }

    function testFuzz_shouldApplyCeilRounding_whenRemainderAfterDecimalsDownScaling(uint256 decimals) public {
        decimals = _mockDecimals(decimals);
        vm.assume(decimals < 18);

        vm.mockCall(controller, abi.encodeWithSelector(IController.mint.selector), abi.encode(10 ** 18 + 1));

        vm.prank(caller);
        assertEq(vault.mint(shares, receiver), 10 ** decimals + 1);
    }

    function test_shouldRevert_whenReentrant() public {
        ReentrancySpy spy = new ReentrancySpy();

        vm.mockFunction(controller, address(spy), abi.encodeWithSelector(ReentrancySpy.reenter.selector));
        vm.mockFunction(controller, address(spy), abi.encodeWithSelector(IController.mint.selector));
        ReentrancySpy(controller).reenter(address(vault), abi.encodeWithSelector(Vault.mint.selector, shares, receiver));

        vm.expectRevert(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector);
        vm.prank(caller);
        vault.mint(shares, receiver);
    }
}

contract ControlledERC7575Vault_Withdraw_Test is ControlledERC7575VaultTest {
    address caller = makeAddr("caller");
    address receiver = makeAddr("receiver");
    address owner = makeAddr("owner");
    uint256 assets = 420e18;
    uint256 shares = 2 * assets;

    function setUp() public override {
        super.setUp();

        vm.mockCall(controller, abi.encodeWithSelector(IController.withdraw.selector), abi.encode(shares));
    }

    function testFuzz_shouldCallControllerWithdraw_withNormalizedAssets(uint256 decimals) public {
        decimals = _mockDecimals(decimals);
        uint256 normalizedAssets = assets * 10 ** (18 - decimals);

        vm.expectCall(
            controller, abi.encodeWithSelector(IController.withdraw.selector, normalizedAssets, caller, owner)
        );

        vm.prank(caller);
        vault.withdraw(assets, receiver, owner);
    }

    function test_shouldRevert_whenZeroAssets() public {
        vm.prank(caller);
        vm.expectRevert(Vault.ZeroAssetsOrShares.selector);
        vault.withdraw(0, receiver, owner);
    }

    function test_shouldRevert_whenZeroShares() public {
        vm.mockCall(controller, abi.encodeWithSelector(IController.withdraw.selector), abi.encode(0));

        vm.prank(caller);
        vm.expectRevert(Vault.ZeroAssetsOrShares.selector);
        vault.withdraw(assets, receiver, owner);
    }

    function test_shouldTransferAssetsToReceiver() public {
        vm.expectCall(asset, abi.encodeWithSelector(IERC20.transfer.selector, receiver, assets));

        vm.prank(caller);
        vault.withdraw(assets, receiver, owner);
    }

    function test_shouldCallWithdrawCallback() public {
        vm.prank(caller);
        vault.withdraw(assets, receiver, owner);

        (bool called, uint256 callbackAssets) = vault.beforeWithdrawCallback();
        assertTrue(called);
        assertEq(callbackAssets, assets);
    }

    function test_shouldEmit_Withdraw() public {
        vm.expectEmit();
        emit IERC7575Vault.Withdraw(caller, receiver, owner, assets, shares);

        vm.prank(caller);
        vault.withdraw(assets, receiver, owner);
    }

    function test_shouldReturnShares() public {
        vm.prank(caller);
        assertEq(vault.withdraw(assets, receiver, owner), shares);
    }

    function test_shouldRevert_whenReentrant() public {
        ReentrancySpy spy = new ReentrancySpy();

        vm.mockFunction(controller, address(spy), abi.encodeWithSelector(ReentrancySpy.reenter.selector));
        vm.mockFunction(controller, address(spy), abi.encodeWithSelector(IController.withdraw.selector));
        ReentrancySpy(controller)
            .reenter(address(vault), abi.encodeWithSelector(Vault.withdraw.selector, assets, receiver, owner));

        vm.expectRevert(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector);
        vm.prank(caller);
        vault.withdraw(assets, receiver, owner);
    }
}

contract ControlledERC7575Vault_Redeem_Test is ControlledERC7575VaultTest {
    address caller = makeAddr("caller");
    address receiver = makeAddr("receiver");
    address owner = makeAddr("owner");
    uint256 assets = 420e18;
    uint256 shares = 2 * assets;

    function setUp() public override {
        super.setUp();

        vm.mockCall(controller, abi.encodeWithSelector(IController.redeem.selector), abi.encode(assets));
    }

    function test_shouldCallControllerRedeem() public {
        vm.expectCall(controller, abi.encodeWithSelector(IController.redeem.selector, shares, caller, owner));

        vm.prank(caller);
        vault.redeem(shares, receiver, owner);
    }

    function test_shouldRevert_whenZeroAssets() public {
        vm.mockCall(controller, abi.encodeWithSelector(IController.redeem.selector), abi.encode(0));

        vm.prank(caller);
        vm.expectRevert(Vault.ZeroAssetsOrShares.selector);
        vault.redeem(shares, receiver, owner);
    }

    function test_shouldRevert_whenZeroShares() public {
        vm.prank(caller);
        vm.expectRevert(Vault.ZeroAssetsOrShares.selector);
        vault.redeem(0, receiver, owner);
    }

    function testFuzz_shouldTransferOriginalAssetsToReceiver(uint256 decimals) public {
        decimals = _mockDecimals(decimals);
        uint256 originalAssets = assets / 10 ** (18 - decimals);

        vm.expectCall(asset, abi.encodeWithSelector(IERC20.transfer.selector, receiver, originalAssets));

        vm.prank(caller);
        vault.redeem(shares, receiver, owner);
    }

    function test_shouldCallWithdrawCallback() public {
        vm.prank(caller);
        vault.redeem(shares, receiver, owner);

        (bool called, uint256 callbackAssets) = vault.beforeWithdrawCallback();
        assertTrue(called);
        assertEq(callbackAssets, assets);
    }

    function test_shouldEmit_Withdraw() public {
        vm.expectEmit();
        emit IERC7575Vault.Withdraw(caller, receiver, owner, assets, shares);

        vm.prank(caller);
        vault.redeem(shares, receiver, owner);
    }

    function test_shouldReturnAssets() public {
        vm.prank(caller);
        assertEq(vault.redeem(shares, receiver, owner), assets);
    }

    function testFuzz_shouldApplyFloorRounding_whenRemainderAfterDecimalsDownScaling(uint256 decimals) public {
        decimals = _mockDecimals(decimals);
        vm.assume(decimals < 18);

        vm.mockCall(controller, abi.encodeWithSelector(IController.redeem.selector), abi.encode(10 ** 18 + 1));

        vm.prank(caller);
        assertEq(vault.redeem(shares, receiver, owner), 10 ** decimals);
    }

    function test_shouldRevert_whenReentrant() public {
        ReentrancySpy spy = new ReentrancySpy();

        vm.mockFunction(controller, address(spy), abi.encodeWithSelector(ReentrancySpy.reenter.selector));
        vm.mockFunction(controller, address(spy), abi.encodeWithSelector(IController.redeem.selector));
        ReentrancySpy(controller)
            .reenter(address(vault), abi.encodeWithSelector(Vault.redeem.selector, shares, receiver, owner));

        vm.expectRevert(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector);
        vm.prank(caller);
        vault.redeem(shares, receiver, owner);
    }
}

contract ControlledERC7575Vault_PreviewDeposit_Test is ControlledERC7575VaultTest {
    uint256 assets = 420e18;
    uint256 shares = 2 * assets;

    function setUp() public override {
        super.setUp();

        vm.mockCall(controller, abi.encodeWithSelector(IController.previewDeposit.selector), abi.encode(shares));
    }

    function testFuzz_shouldCallControllerPreviewDeposit_withNormalizedAssets(uint256 decimals) public {
        decimals = _mockDecimals(decimals);
        uint256 normalizedAssets = assets * 10 ** (18 - decimals);

        vm.expectCall(controller, abi.encodeWithSelector(IController.previewDeposit.selector, normalizedAssets));

        vault.previewDeposit(assets);
    }

    function test_shouldReturnShares() public view {
        assertEq(vault.previewDeposit(assets), shares);
    }
}

contract ControlledERC7575Vault_PreviewMint_Test is ControlledERC7575VaultTest {
    uint256 assets = 420e18;
    uint256 shares = 2 * assets;

    function setUp() public override {
        super.setUp();

        vm.mockCall(controller, abi.encodeWithSelector(IController.previewMint.selector), abi.encode(assets));
    }

    function test_shouldCallControllerPreviewMint_withShares() public {
        vm.expectCall(controller, abi.encodeWithSelector(IController.previewMint.selector, shares));

        vault.previewMint(shares);
    }

    function testFuzz_shouldReturnOriginalAssets(uint256 decimals) public {
        decimals = _mockDecimals(decimals);
        uint256 originalAssets = assets / 10 ** (18 - decimals);

        assertEq(vault.previewMint(shares), originalAssets);
    }

    function testFuzz_shouldApplyCeilRounding_whenRemainderAfterDecimalsDownScaling(uint256 decimals) public {
        decimals = _mockDecimals(decimals);
        vm.assume(decimals < 18);

        vm.mockCall(controller, abi.encodeWithSelector(IController.previewMint.selector), abi.encode(10 ** 18 + 1));

        assertEq(vault.previewMint(shares), 10 ** decimals + 1);
    }
}

contract ControlledERC7575Vault_PreviewWithdraw_Test is ControlledERC7575VaultTest {
    uint256 assets = 420e18;
    uint256 shares = 2 * assets;

    function setUp() public override {
        super.setUp();

        vm.mockCall(controller, abi.encodeWithSelector(IController.previewWithdraw.selector), abi.encode(shares));
    }

    function testFuzz_shouldCallControllerPreviewWithdraw_withNormalizedAssets(uint256 decimals) public {
        decimals = _mockDecimals(decimals);
        uint256 normalizedAssets = assets * 10 ** (18 - decimals);

        vm.expectCall(controller, abi.encodeWithSelector(IController.previewWithdraw.selector, normalizedAssets));

        vault.previewWithdraw(assets);
    }

    function test_shouldReturnShares() public view {
        assertEq(vault.previewWithdraw(assets), shares);
    }
}

contract ControlledERC7575Vault_PreviewRedeem_Test is ControlledERC7575VaultTest {
    uint256 assets = 420e18;
    uint256 shares = 2 * assets;

    function setUp() public override {
        super.setUp();

        vm.mockCall(controller, abi.encodeWithSelector(IController.previewRedeem.selector), abi.encode(assets));
    }

    function test_shouldCallControllerPreviewRedeem_withShares() public {
        vm.expectCall(controller, abi.encodeWithSelector(IController.previewRedeem.selector, shares));

        vault.previewRedeem(shares);
    }

    function testFuzz_shouldReturnOriginalAssets(uint256 decimals) public {
        decimals = _mockDecimals(decimals);
        uint256 originalAssets = assets / 10 ** (18 - decimals);

        assertEq(vault.previewRedeem(shares), originalAssets);
    }

    function testFuzz_shouldApplyFloorRounding_whenRemainderAfterDecimalsDownScaling(uint256 decimals) public {
        decimals = _mockDecimals(decimals);
        vm.assume(decimals < 18);

        vm.mockCall(controller, abi.encodeWithSelector(IController.previewRedeem.selector), abi.encode(10 ** 18 + 1));

        assertEq(vault.previewRedeem(shares), 10 ** decimals);
    }
}

contract ControlledERC7575Vault_MaxDeposit_Test is ControlledERC7575VaultTest {
    address receiver = makeAddr("receiver");

    function testFuzz_shouldReturnControllerMaxDeposit(uint256 decimals) public {
        decimals = _mockDecimals(decimals);

        uint256 normalizedAssets = 420e18;
        uint256 originalAssets = normalizedAssets / 10 ** (18 - decimals);

        vm.mockCall(controller, abi.encodeWithSelector(IController.maxDeposit.selector), abi.encode(normalizedAssets));

        vm.expectCall(controller, abi.encodeWithSelector(IController.maxDeposit.selector, receiver));

        assertEq(vault.maxDeposit(receiver), originalAssets);
    }

    function testFuzz_shouldApplyFloorRounding_whenRemainderAfterDecimalsDownScaling(uint256 decimals) public {
        decimals = _mockDecimals(decimals);
        vm.assume(decimals < 18);

        vm.mockCall(controller, abi.encodeWithSelector(IController.maxDeposit.selector), abi.encode(10 ** 18 + 1));

        assertEq(vault.maxDeposit(receiver), 10 ** decimals);
    }
}

contract ControlledERC7575Vault_MaxMint_Test is ControlledERC7575VaultTest {
    function test_shouldReturnControllerMaxMint() public {
        address receiver = makeAddr("receiver");
        uint256 shares = 420e18;

        vm.mockCall(controller, abi.encodeWithSelector(IController.maxMint.selector), abi.encode(shares));

        vm.expectCall(controller, abi.encodeWithSelector(IController.maxMint.selector, receiver));

        assertEq(vault.maxMint(receiver), shares);
    }
}

contract ControlledERC7575Vault_MaxWithdraw_Test is ControlledERC7575VaultTest {
    address owner = makeAddr("owner");

    function testFuzz_shouldReturnControllerMaxWithdraw_withAvailableBalance(uint256 decimals) public {
        decimals = _mockDecimals(decimals);

        uint256 availableAssets = 1000e18;
        vm.mockCall(
            asset, abi.encodeWithSelector(IERC20.balanceOf.selector, address(vault)), abi.encode(availableAssets)
        );
        uint256 additionalBalance = 500e18;
        vault.workaround_setAdditionalAvailableAssets(additionalBalance);

        uint256 normalizedAvailableAssets = (availableAssets + additionalBalance) * 10 ** (18 - decimals);
        vm.expectCall(
            controller, abi.encodeWithSelector(IController.maxWithdraw.selector, owner, normalizedAvailableAssets)
        );

        uint256 normalizedAssets = 420e18;
        vm.mockCall(controller, abi.encodeWithSelector(IController.maxWithdraw.selector), abi.encode(normalizedAssets));

        uint256 assets = normalizedAssets / 10 ** (18 - decimals);
        assertEq(vault.maxWithdraw(owner), assets);
    }

    function testFuzz_shouldApplyFloorRounding_whenRemainderAfterDecimalsDownScaling(uint256 decimals) public {
        decimals = _mockDecimals(decimals);
        vm.assume(decimals < 18);

        vm.mockCall(controller, abi.encodeWithSelector(IController.maxWithdraw.selector), abi.encode(10 ** 18 + 1));

        assertEq(vault.maxWithdraw(owner), 10 ** decimals);
    }
}

contract ControlledERC7575Vault_MaxRedeem_Test is ControlledERC7575VaultTest {
    function testFuzz_shouldReturnControllerMaxRedeem_withAvailableBalance(uint256 decimals) public {
        decimals = _mockDecimals(decimals);

        uint256 availableAssets = 1000e18;
        vm.mockCall(
            asset, abi.encodeWithSelector(IERC20.balanceOf.selector, address(vault)), abi.encode(availableAssets)
        );
        uint256 additionalBalance = 500e18;
        vault.workaround_setAdditionalAvailableAssets(additionalBalance);

        uint256 shares = 420e18;
        vm.mockCall(controller, abi.encodeWithSelector(IController.maxRedeem.selector), abi.encode(shares));

        address owner = makeAddr("owner");
        uint256 normalizedAvailableAssets = (availableAssets + additionalBalance) * 10 ** (18 - decimals);
        vm.expectCall(
            controller, abi.encodeWithSelector(IController.maxRedeem.selector, owner, normalizedAvailableAssets)
        );

        assertEq(vault.maxRedeem(owner), shares);
    }
}

contract ControlledERC7575Vault_ControllerWithdraw_Test is ControlledERC7575VaultTest {
    uint256 assets = 420e18;
    address receiver = makeAddr("receiver");

    function test_shouldRevert_whenCallerNotController() public {
        vm.prank(makeAddr("notController"));
        vm.expectRevert(IControlledVault.CallerNotController.selector);
        vault.controllerWithdraw(asset, assets, receiver);
    }

    function test_shouldCallBeforeWithdrawCallback_whenAssetIsVaultAsset() public {
        vm.prank(controller);
        vault.controllerWithdraw(asset, assets, receiver);

        (bool called, uint256 callbackAssets) = vault.beforeWithdrawCallback();
        assertTrue(called);
        assertEq(callbackAssets, assets);
    }

    function test_shouldNotCallBeforeWithdrawCallback_whenAssetIsNotVaultAsset() public {
        address notVaultAsset = makeAddr("notVaultAsset");
        vm.mockCall(notVaultAsset, abi.encodeWithSelector(IERC20.transfer.selector), abi.encode(true));

        vm.prank(controller);
        vault.controllerWithdraw(notVaultAsset, assets, receiver);

        (bool called,) = vault.beforeWithdrawCallback();
        assertFalse(called);
    }

    function test_shouldTransferAssetsToReceiver() public {
        vm.expectCall(asset, abi.encodeWithSelector(IERC20.transfer.selector, receiver, assets));

        vm.prank(controller);
        vault.controllerWithdraw(asset, assets, receiver);
    }

    function test_shouldEmit_ControllerWithdraw() public {
        vm.expectEmit();
        emit IControlledVault.ControllerWithdraw(asset, assets, receiver);

        vm.prank(controller);
        vault.controllerWithdraw(asset, assets, receiver);
    }
}

contract ControlledERC7575Vault_ControllerDeposit_Test is ControlledERC7575VaultTest {
    uint256 assets = 420e18;

    function test_shouldRevert_whenCallerNotController() public {
        vm.prank(makeAddr("notController"));
        vm.expectRevert(IControlledVault.CallerNotController.selector);
        vault.controllerDeposit(assets);
    }

    function test_shouldCallAfterDepositCallback() public {
        vm.prank(controller);
        vault.controllerDeposit(assets);

        (bool called, uint256 callbackAssets) = vault.afterDepositCallback();
        assertTrue(called);
        assertEq(callbackAssets, assets);
    }

    function test_shouldEmit_ControllerDeposit() public {
        vm.expectEmit();
        emit IControlledVault.ControllerDeposit(assets);

        vm.prank(controller);
        vault.controllerDeposit(assets);
    }
}
