// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { Test } from "forge-std/Test.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {
    Controller,
    ConfigManager,
    PeripheryManager,
    EmergencyManager,
    IGenericShare,
    IYieldDistributor,
    ISwapper
} from "../../../src/controller/Controller.sol";
import { IControlledVault } from "../../../src/interfaces/IControlledVault.sol";
import { IChainlinkAggregatorLike } from "../../../src/interfaces/IChainlinkAggregatorLike.sol";
import { IERC20Mintable } from "../../../src/interfaces/IERC20Mintable.sol";

import { ControllerHarness } from "../../harness/ControllerHarness.sol";

abstract contract ControllerTest is Test {
    uint16 constant MAX_BPS = 10_000;

    ControllerHarness controller;

    address admin = makeAddr("admin");
    IGenericShare share = IGenericShare(makeAddr("share"));
    address rewardsCollector = makeAddr("rewardsCollector");
    ISwapper swapper = ISwapper(makeAddr("swapper"));
    IYieldDistributor yieldDistributor = IYieldDistributor(makeAddr("yieldDistributor"));

    function _mockVault(
        address vault,
        address asset,
        uint256 normalizedAssets,
        address priceFeed,
        uint256 price,
        uint256 decimals
    )
        internal
    {
        _mockVault(vault, asset, normalizedAssets, priceFeed, price, decimals, 0, 0, MAX_BPS);
    }

    function _mockVault(
        address vault,
        address asset,
        uint256 normalizedAssets,
        address priceFeed,
        uint256 price,
        uint256 decimals,
        uint224 maxCapacity,
        uint16 minProportionality,
        uint16 maxProportionality
    )
        internal
    {
        vm.mockCall(vault, abi.encodeWithSelector(IControlledVault.asset.selector), abi.encode(asset));
        vm.mockCall(
            vault, abi.encodeWithSelector(IControlledVault.totalNormalizedAssets.selector), abi.encode(normalizedAssets)
        );
        vm.mockCall(
            priceFeed,
            abi.encodeWithSelector(IChainlinkAggregatorLike.latestRoundData.selector),
            abi.encode(0, price, 0, block.timestamp, 0)
        );
        vm.mockCall(priceFeed, abi.encodeWithSelector(IChainlinkAggregatorLike.decimals.selector), abi.encode(decimals));

        controller.workaround_addVault(vault);
        controller.workaround_setPriceFeed(asset, priceFeed, 1 minutes);
        controller.workaround_setVaultSettings(vault, maxCapacity, minProportionality, maxProportionality);
    }

    function _resetInitializableStorageSlot() internal {
        // reset the Initializable storage slot to allow usage of deployed instance in tests
        vm.store(address(controller), controller.exposed_initializableStorageSlot(), bytes32(0));
    }

    function setUp() public virtual {
        controller = new ControllerHarness();
        _resetInitializableStorageSlot();
        controller.initialize(admin, share, rewardsCollector, swapper, yieldDistributor);
    }
}

contract Controller_Constructor_Test is ControllerTest {
    function test_shouldDisableInitializers() public {
        controller = new ControllerHarness();
        bytes32 initializableSlotValue = vm.load(address(controller), controller.exposed_initializableStorageSlot());
        assertEq(uint64(uint256(initializableSlotValue)), type(uint64).max);
    }
}

contract Controller_Initialize_Test is ControllerTest {
    function setUp() public override {
        controller = new ControllerHarness();
        _resetInitializableStorageSlot();
    }

    function test_shouldSetInitialValues() public {
        controller.initialize(admin, share, rewardsCollector, swapper, yieldDistributor);

        assertEq(controller.share(), address(share));
        assertEq(controller.swapper(), address(swapper));
        assertEq(controller.yieldDistributor(), address(yieldDistributor));
        assertEq(controller.hasRole(controller.DEFAULT_ADMIN_ROLE(), admin), true);
        assertEq(controller.exposed_getInitializedVersion(), 1);
    }

    function test_shouldRevert_whenAlreadyInitialized() public {
        controller.initialize(admin, share, rewardsCollector, swapper, yieldDistributor);

        vm.expectRevert();
        controller.initialize(admin, share, rewardsCollector, swapper, yieldDistributor);
    }

    function test_shouldRevert_whenZeroAdmin() public {
        vm.expectRevert(Controller.Controller_ZeroAdmin.selector);
        controller.initialize(address(0), share, rewardsCollector, swapper, yieldDistributor);
    }

    function test_shouldRevert_whenZeroShare() public {
        vm.expectRevert(Controller.Controller_ZeroShare.selector);
        controller.initialize(admin, IGenericShare(address(0)), rewardsCollector, swapper, yieldDistributor);
    }

    function test_shouldInitVaultsLinkedList() public {
        controller.initialize(admin, share, rewardsCollector, swapper, yieldDistributor);

        address sentinelVaults = controller.SENTINEL_VAULTS();
        assertEq(controller.exposed_vaultsLinkedList(sentinelVaults), sentinelVaults);
    }

    function test_shouldRevert_whenZeroRewardsCollector() public {
        vm.expectRevert(ConfigManager.Config_RewardsCollectorZeroAddress.selector);
        controller.initialize(admin, share, address(0), swapper, yieldDistributor);
    }

    function test_shouldRevert_whenZeroSwapper() public {
        vm.expectRevert(PeripheryManager.Periphery_ZeroSwapper.selector);
        controller.initialize(admin, share, rewardsCollector, ISwapper(address(0)), yieldDistributor);
    }

    function test_shouldRevert_whenZeroYieldDistributor() public {
        vm.expectRevert(PeripheryManager.Periphery_ZeroYieldDistributor.selector);
        controller.initialize(admin, share, rewardsCollector, swapper, IYieldDistributor(address(0)));
    }
}

contract Controller_MaxDeposit_Test is ControllerTest {
    address vault = makeAddr("vault");
    address asset = makeAddr("asset");
    address receiver = makeAddr("receiver");

    function setUp() public override {
        super.setUp();
        controller.workaround_setMainVaultFor(asset, vault);
    }

    function test_shouldRevert_whenCallerNotRegisteredVault() public {
        vm.expectRevert(Controller.Controller_CallerNotVault.selector);
        vm.prank(makeAddr("notVault"));
        controller.maxDeposit(receiver);
    }

    function test_shouldRevert_whenCallerNotMainVault() public {
        address notMainVault = makeAddr("notMainVault");
        _mockVault(notMainVault, asset, 1000e18, makeAddr("feed"), 1e8, 8, 0, 0, MAX_BPS);

        vm.expectRevert(Controller.Controller_CallerNotMainVault.selector);
        vm.prank(notMainVault);
        controller.maxDeposit(receiver);
    }

    function test_shouldReturnMaxDeposit_whenNoLimits() public {
        _mockVault(vault, asset, 1000e18, makeAddr("feed"), 1e8, 8, 0, 0, MAX_BPS);

        vm.prank(vault);
        assertEq(controller.maxDeposit(receiver), type(uint256).max);
    }

    function test_shouldReturnMaxDepositLimit_whenLimits() public {
        _mockVault(vault, asset, 1000e18, makeAddr("feed"), 0.9e8, 8, 10_000e18, 0, MAX_BPS);

        vm.prank(vault);
        assertEq(controller.maxDeposit(receiver), 9000e18);
    }
}

contract Controller_MaxMint_Test is ControllerTest {
    address vault = makeAddr("vault");
    address asset = makeAddr("asset");
    address feed = makeAddr("feed");
    address receiver = makeAddr("receiver");

    function setUp() public override {
        super.setUp();
        controller.workaround_setMainVaultFor(asset, vault);
    }

    function test_shouldRevert_whenCallerNotRegisteredVault() public {
        vm.expectRevert(Controller.Controller_CallerNotVault.selector);
        vm.prank(makeAddr("notVault"));
        assertEq(controller.maxMint(receiver), 0);
    }

    function test_shouldRevert_whenCallerNotMainVault() public {
        address notMainVault = makeAddr("notMainVault");
        _mockVault(notMainVault, asset, 1000e18, feed, 1e8, 8, 0, 0, MAX_BPS);

        vm.expectRevert(Controller.Controller_CallerNotMainVault.selector);
        vm.prank(notMainVault);
        controller.maxMint(receiver);
    }

    function test_shouldReturnMaxMint_whenNoLimits() public {
        _mockVault(vault, asset, 1000e18, feed, 1e8, 8, 0, 0, MAX_BPS);

        vm.prank(vault);
        assertEq(controller.maxMint(receiver), type(uint256).max);
    }

    function test_shouldReturnMaxMintLimit_whenLimits() public {
        _mockVault(vault, asset, 1000e18, feed, 0.9e8, 8, 10_000e18, 0, MAX_BPS);

        vm.prank(vault);
        assertEq(controller.maxMint(receiver), 9000e18 * 0.9); // capacity * price
    }

    function test_shouldRoundDown_whenMaxMintNotWholeNumber() public {
        _mockVault(vault, asset, 0, feed, 0.9e8, 8, 2, 0, MAX_BPS);

        vm.prank(vault);
        assertEq(controller.maxMint(receiver), 1); // 2 * 0.9 = 1.8
    }
}

contract Controller_MaxWithdraw_Test is ControllerTest {
    address vault = makeAddr("vault");
    address asset = makeAddr("asset");
    address feed = makeAddr("feed");
    address owner = makeAddr("owner");

    function test_shouldRevert_whenCallerNotRegisteredVault() public {
        vm.expectRevert(Controller.Controller_CallerNotVault.selector);
        vm.prank(makeAddr("notVault"));
        controller.maxWithdraw(owner, type(uint256).max);
    }

    function test_shouldReturnAvailableAssets_whenLessThanMaxLimit_whenLessThanOwnedAssets() public {
        _mockVault(vault, asset, 100_000e18, feed, 1.1e8, 8, 0, 0, MAX_BPS);
        vm.mockCall(address(share), abi.encodeWithSelector(IERC20.balanceOf.selector, owner), abi.encode(20_000e18));
        vm.mockCall(address(share), abi.encodeWithSelector(IERC20.totalSupply.selector), abi.encode(80_000e18));

        // min(20_000 / 1.1, 100_000, 10_000) = 10_000
        vm.prank(vault);
        assertEq(controller.maxWithdraw(owner, 10_000e18), 10_000e18);
    }

    function test_shouldReturnOwnedAssets_whenLessThanMaxLimit_whenLessThanAvailableAssets() public {
        _mockVault(vault, asset, 100_000e18, feed, 1.1e8, 8, 0, 0, MAX_BPS);
        vm.mockCall(address(share), abi.encodeWithSelector(IERC20.balanceOf.selector, owner), abi.encode(11_000e18));
        vm.mockCall(address(share), abi.encodeWithSelector(IERC20.totalSupply.selector), abi.encode(80_000e18));

        // min(11_000 / 1.1, 100_000, 50_000) = 10_000
        vm.prank(vault);
        assertEq(controller.maxWithdraw(owner, 50_000e18), 10_000e18);
    }

    function test_shouldReturnMaxLimit_whenLessThanOwnedAssets_whenLessThanAvailableAssets() public {
        _mockVault(vault, asset, 30_000e18, feed, 1.1e8, 8, 0, 0, MAX_BPS);
        _mockVault(makeAddr("vault2"), makeAddr("asset2"), 50_000e18, makeAddr("feed2"), 1e8, 8, 0, 0, MAX_BPS);
        vm.mockCall(address(share), abi.encodeWithSelector(IERC20.balanceOf.selector, owner), abi.encode(50_000e18));
        vm.mockCall(address(share), abi.encodeWithSelector(IERC20.totalSupply.selector), abi.encode(80_000e18));

        // min(50_000 / 1.1, 30_000, 60_000) = 30_000
        vm.prank(vault);
        assertEq(controller.maxWithdraw(owner, 60_000e18), 30_000e18);
    }

    function test_shouldRoundDown_whenMaxWithdrawNotWholeNumber() public {
        _mockVault(vault, asset, 60_000e18, feed, 1.1e8, 8, 0, 0, MAX_BPS);
        vm.mockCall(address(share), abi.encodeWithSelector(IERC20.balanceOf.selector, owner), abi.encode(2));
        vm.mockCall(address(share), abi.encodeWithSelector(IERC20.totalSupply.selector), abi.encode(80_000e18));

        vm.prank(vault);
        assertEq(controller.maxWithdraw(owner, 60_000e18), 1); // 2 / 1.1 = 1.818...
    }
}

contract Controller_MaxRedeemTest is ControllerTest {
    address vault = makeAddr("vault");
    address asset = makeAddr("asset");
    address feed = makeAddr("feed");
    address owner = makeAddr("owner");

    function test_shouldRevert_whenCallerNotRegisteredVault() public {
        vm.expectRevert(Controller.Controller_CallerNotVault.selector);
        vm.prank(makeAddr("notVault"));
        controller.maxRedeem(owner, type(uint256).max);
    }

    function test_shouldReturnAvailableAssets_whenLessThanMaxLimit_whenLessThanOwnedShares() public {
        _mockVault(vault, asset, 100_000e18, feed, 1.1e8, 8, 0, 0, MAX_BPS);
        vm.mockCall(address(share), abi.encodeWithSelector(IERC20.balanceOf.selector, owner), abi.encode(20_000e18));
        vm.mockCall(address(share), abi.encodeWithSelector(IERC20.totalSupply.selector), abi.encode(80_000e18));

        // min(20_000, 100_000 * 1.1, 10_000 * 1.1) = 11_000
        vm.prank(vault);
        assertEq(controller.maxRedeem(owner, 10_000e18), 11_000e18);
    }

    function test_shouldReturnOwnedShares_whenLessThanMaxLimit_whenLessThanAvailableAssets() public {
        _mockVault(vault, asset, 100_000e18, feed, 1.1e8, 8, 0, 0, MAX_BPS);
        vm.mockCall(address(share), abi.encodeWithSelector(IERC20.balanceOf.selector, owner), abi.encode(10_000e18));
        vm.mockCall(address(share), abi.encodeWithSelector(IERC20.totalSupply.selector), abi.encode(80_000e18));

        // min(10_000, 100_000 * 1.1, 50_000 * 1.1) = 10_000
        vm.prank(vault);
        assertEq(controller.maxRedeem(owner, 50_000e18), 10_000e18);
    }

    function test_shouldReturnMaxLimit_whenLessThanOwnedShares_whenLessThanAvailableAssets() public {
        _mockVault(vault, asset, 30_000e18, feed, 1.1e8, 8, 0, 0, MAX_BPS);
        _mockVault(makeAddr("vault2"), makeAddr("asset2"), 50_000e18, makeAddr("feed2"), 1e8, 8, 0, 0, MAX_BPS);
        vm.mockCall(address(share), abi.encodeWithSelector(IERC20.balanceOf.selector, owner), abi.encode(50_000e18));
        vm.mockCall(address(share), abi.encodeWithSelector(IERC20.totalSupply.selector), abi.encode(80_000e18));

        // min(50_000, 30_000 * 1.1, 60_000 * 1.1) = 33_000
        vm.prank(vault);
        assertEq(controller.maxRedeem(owner, 60_000e18), 33_000e18);
    }

    function test_shouldRoundDown_whenMaxRedeemNotWholeNumber() public {
        _mockVault(vault, asset, 30_000e18, feed, 1.1e8, 8, 0, 0, MAX_BPS);
        vm.mockCall(address(share), abi.encodeWithSelector(IERC20.balanceOf.selector, owner), abi.encode(50_000e18));
        vm.mockCall(address(share), abi.encodeWithSelector(IERC20.totalSupply.selector), abi.encode(80_000e18));

        vm.prank(vault);
        assertEq(controller.maxWithdraw(owner, 2), 2); // 2 * 1.1 = 2.2
    }
}

contract Controller_PreviewDeposit_Test is ControllerTest {
    address vault = makeAddr("vault");
    address asset = makeAddr("asset");
    address feed = makeAddr("feed");

    function setUp() public override {
        super.setUp();
        controller.workaround_setMainVaultFor(asset, vault);
    }

    function test_shouldRevert_whenCallerNotRegisteredVault() public {
        vm.expectRevert(Controller.Controller_CallerNotVault.selector);
        vm.prank(makeAddr("notVault"));
        controller.previewDeposit(1000e18);
    }

    function test_shouldRevert_whenCallerNotMainVault() public {
        address notMainVault = makeAddr("notMainVault");
        _mockVault(notMainVault, asset, 1000e18, makeAddr("feed"), 1e8, 8, 0, 0, MAX_BPS);

        vm.expectRevert(Controller.Controller_CallerNotMainVault.selector);
        vm.prank(notMainVault);
        controller.previewDeposit(1000e18);
    }

    function testFuzz_shouldReturnShares_whenAssetPriceAboveMax(
        uint256 price,
        uint256 normalizedAssets
    )
        public
    {
        normalizedAssets = bound(normalizedAssets, 0, type(uint256).max / 1e20);
        price = bound(price, 1e8 + 1, 10e8);
        _mockVault(vault, asset, 1, feed, price, 8);

        vm.prank(vault);
        assertEq(controller.previewDeposit(normalizedAssets), normalizedAssets);
    }

    function testFuzz_shouldReturnShares_whenAssetPriceBelowMax(
        uint256 price,
        uint256 normalizedAssets
    )
        public
    {
        normalizedAssets = bound(normalizedAssets, 0, type(uint256).max / 1e20);
        price = bound(price, 0.01e8, 1e8 - 1);
        _mockVault(vault, asset, 1, feed, price, 8);

        uint256 expectedShares = normalizedAssets * price / 1e8;

        vm.prank(vault);
        assertEq(controller.previewDeposit(normalizedAssets), expectedShares);
    }

    function test_shouldRoundDown_whenSharesNotWholeNumber() public {
        _mockVault(vault, asset, 1, feed, 0.8e8, 8);

        vm.prank(vault);
        assertEq(controller.previewDeposit(2), 1); // 2 * 0.8 = 1.6
    }
}

contract Controller_PreviewMint_Test is ControllerTest {
    address vault = makeAddr("vault");
    address asset = makeAddr("asset");
    address feed = makeAddr("feed");

    function setUp() public override {
        super.setUp();
        controller.workaround_setMainVaultFor(asset, vault);
    }

    function test_shouldRevert_whenCallerNotRegisteredVault() public {
        vm.expectRevert(Controller.Controller_CallerNotVault.selector);
        vm.prank(makeAddr("notVault"));
        controller.previewMint(1000e18);
    }

    function test_shouldRevert_whenCallerNotMainVault() public {
        address notMainVault = makeAddr("notMainVault");
        _mockVault(notMainVault, asset, 1000e18, makeAddr("feed"), 1e8, 8, 0, 0, MAX_BPS);

        vm.expectRevert(Controller.Controller_CallerNotMainVault.selector);
        vm.prank(notMainVault);
        controller.previewMint(1000e18);
    }

    function testFuzz_shouldReturnAssets_whenAssetPriceAboveMax(uint256 price, uint256 shares) public {
        shares = bound(shares, 0, type(uint256).max / 1e20);
        price = bound(price, 1e8 + 1, 10e8);
        _mockVault(vault, asset, 1, feed, price, 8);

        vm.prank(vault);
        assertEq(controller.previewMint(shares), shares);
    }

    function testFuzz_shouldReturnAssets_whenAssetPriceBelowMax(uint256 price, uint256 shares) public {
        shares = bound(shares, 0, type(uint256).max / 1e20);
        price = bound(price, 0.01e8, 1e8 - 1);
        _mockVault(vault, asset, 1, feed, price, 8);

        vm.prank(vault);
        assertApproxEqAbs(controller.previewMint(shares), shares * 1e8 / price, 1);
        // allow 1 wei difference due to rounding
    }

    function test_shouldRoundUp_whenAssetsNotWholeNumber() public {
        _mockVault(vault, asset, 1, feed, 0.8e8, 8);

        vm.prank(vault);
        assertEq(controller.previewMint(2), 3); // 2 / 0.8 = 2.5
    }
}

contract Controller_PreviewWithdraw_Test is ControllerTest {
    address vault = makeAddr("vault");
    address asset = makeAddr("asset");
    address feed = makeAddr("feed");

    function test_shouldRevert_whenCallerNotRegisteredVault() public {
        vm.expectRevert(Controller.Controller_CallerNotVault.selector);
        vm.prank(makeAddr("notVault"));
        controller.previewWithdraw(1000e18);
    }

    function testFuzz_shouldReturnShares_whenAssetPriceBelowMin_whenSharePriceOne(
        uint256 price,
        uint256 normalizedAssets
    )
        public
    {
        normalizedAssets = bound(normalizedAssets, 0, type(uint256).max / 1e20);
        price = bound(price, 0.01e8, 1e8 - 1);
        _mockVault(vault, asset, 100e18, feed, price, 8);
        vm.mockCall(address(share), abi.encodeWithSelector(IERC20.totalSupply.selector), abi.encode(1e18));

        vm.prank(vault);
        assertEq(controller.previewWithdraw(normalizedAssets), normalizedAssets);
    }

    function testFuzz_shouldReturnShares_whenAssetPriceBelowMin_whenSharePriceLessThanOne(
        uint256 price,
        uint256 normalizedAssets
    )
        public
    {
        normalizedAssets = bound(normalizedAssets, 0, type(uint256).max / 1e20);
        price = bound(price, 0.01e8, 1e8 - 1);
        _mockVault(vault, asset, 100e18, feed, price, 8);
        vm.mockCall(address(share), abi.encodeWithSelector(IERC20.totalSupply.selector), abi.encode(100e18));

        uint256 shareRedemptionPrice = controller.shareRedemptionPrice();
        assertLt(shareRedemptionPrice, 1e18);

        uint256 expectedShares = normalizedAssets * 1e18 / shareRedemptionPrice;
        vm.prank(vault);
        assertApproxEqAbs(controller.previewWithdraw(normalizedAssets), expectedShares, 1);
        // allow 1 wei difference due to rounding
    }

    function testFuzz_shouldReturnShares_whenAssetPriceAboveMin_whenSharePriceOne(
        uint256 price,
        uint256 normalizedAssets
    )
        public
    {
        normalizedAssets = bound(normalizedAssets, 0, type(uint256).max / 1e20);
        price = bound(price, 1e8 + 1, 10e8);
        _mockVault(vault, asset, 100e18, feed, price, 8);
        vm.mockCall(address(share), abi.encodeWithSelector(IERC20.totalSupply.selector), abi.encode(100e18));

        uint256 expectedShares = normalizedAssets * price / 1e8;
        vm.prank(vault);
        assertApproxEqAbs(controller.previewWithdraw(normalizedAssets), expectedShares, 1);
        // allow 1 wei difference due to rounding
    }

    function testFuzz_shouldReturnShares_whenAssetPriceAboveMin_whenSharePriceLessThanOne(
        uint256 price,
        uint256 normalizedAssets
    )
        public
    {
        normalizedAssets = bound(normalizedAssets, 0, type(uint256).max / 1e20);
        price = bound(price, 1e8 + 1, 10e8);
        _mockVault(vault, asset, 1e18, feed, price, 8);
        vm.mockCall(address(share), abi.encodeWithSelector(IERC20.totalSupply.selector), abi.encode(100e18));

        uint256 shareRedemptionPrice = controller.shareRedemptionPrice();
        assertLt(shareRedemptionPrice, 1e18);

        uint256 expectedShares = normalizedAssets * price * 1e10 / shareRedemptionPrice; // * 1e18 / 1e8 = 1e10
        vm.prank(vault);
        assertApproxEqAbs(controller.previewWithdraw(normalizedAssets), expectedShares, 1);
        // allow 1 wei difference due to rounding
    }

    function test_shouldRoundUp_whenSharesNotWholeNumber() public {
        _mockVault(vault, asset, 100e18, feed, 1.1e8, 8);
        vm.mockCall(address(share), abi.encodeWithSelector(IERC20.totalSupply.selector), abi.encode(100e18));

        vm.prank(vault);
        assertEq(controller.previewWithdraw(2), 3); // 2 * 1.1 = 2.2
    }
}

contract Controller_PreviewRedeem_Test is ControllerTest {
    address vault = makeAddr("vault");
    address asset = makeAddr("asset");
    address feed = makeAddr("feed");

    function test_shouldRevert_whenCallerNotRegisteredVault() public {
        vm.expectRevert(Controller.Controller_CallerNotVault.selector);
        vm.prank(makeAddr("notVault"));
        controller.previewRedeem(1000e18);
    }

    function testFuzz_shouldReturnAssets_whenAssetPriceBelowMin_whenSharePriceOne(
        uint256 price,
        uint256 shares
    )
        public
    {
        shares = bound(shares, 0, type(uint256).max / 1e20);
        price = bound(price, 0.01e8, 1e8 - 1);
        _mockVault(vault, asset, 100e18, feed, price, 8);
        vm.mockCall(address(share), abi.encodeWithSelector(IERC20.totalSupply.selector), abi.encode(1e18));

        vm.prank(vault);
        assertEq(controller.previewRedeem(shares), shares);
    }

    function testFuzz_shouldReturnAssets_whenAssetPriceBelowMin_whenSharePriceLessThanOne(
        uint256 price,
        uint256 shares
    )
        public
    {
        shares = bound(shares, 0, type(uint256).max / 1e20);
        price = bound(price, 0.01e8, 1e8 - 1);
        _mockVault(vault, asset, 100e18, feed, price, 8);
        vm.mockCall(address(share), abi.encodeWithSelector(IERC20.totalSupply.selector), abi.encode(100e18));

        uint256 shareRedemptionPrice = controller.shareRedemptionPrice();
        assertLt(shareRedemptionPrice, 1e18);

        uint256 expectedAssets = shares * shareRedemptionPrice / 1e18;
        vm.prank(vault);
        assertApproxEqAbs(controller.previewRedeem(shares), expectedAssets, 1);
        // allow 1 wei difference due to rounding
    }

    function testFuzz_shouldReturnAssets_whenAssetPriceAboveMin_whenSharePriceOne(
        uint256 price,
        uint256 shares
    )
        public
    {
        shares = bound(shares, 0, type(uint256).max / 1e20);
        price = bound(price, 1e8 + 1, 10e8);
        _mockVault(vault, asset, 100e18, feed, price, 8);
        vm.mockCall(address(share), abi.encodeWithSelector(IERC20.totalSupply.selector), abi.encode(100e18));

        uint256 expectedAssets = shares * 1e8 / price;
        vm.prank(vault);
        assertApproxEqAbs(controller.previewRedeem(shares), expectedAssets, 1);
        // allow 1 wei difference due to rounding
    }

    function testFuzz_shouldReturnAssets_whenAssetPriceAboveMin_whenSharePriceLessThanOne(
        uint256 price,
        uint256 shares
    )
        public
    {
        shares = bound(shares, 0, type(uint256).max / 1e20);
        price = bound(price, 1e8 + 1, 10e8);
        _mockVault(vault, asset, 1e18, feed, price, 8);
        vm.mockCall(address(share), abi.encodeWithSelector(IERC20.totalSupply.selector), abi.encode(100e18));

        uint256 shareRedemptionPrice = controller.shareRedemptionPrice();
        assertLt(shareRedemptionPrice, 1e18);

        uint256 expectedAssets = shares * shareRedemptionPrice / 1e10 / price; // / 1e18 * 1e8 = 1e10
        vm.prank(vault);
        assertApproxEqAbs(controller.previewRedeem(shares), expectedAssets, 1);
        // allow 1 wei difference due to rounding
    }

    function test_shouldRoundDown_whenAssetsNotWholeNumber() public {
        _mockVault(vault, asset, 100e18, feed, 1.1e8, 8);
        vm.mockCall(address(share), abi.encodeWithSelector(IERC20.totalSupply.selector), abi.encode(100e18));

        vm.prank(vault);
        assertEq(controller.previewRedeem(2), 1); // 2 / 1.1 = 1.818...
    }
}

contract Controller_Deposit_Test is ControllerTest {
    address vault = makeAddr("vault");
    address asset = makeAddr("asset");
    address feed = makeAddr("feed");
    address receiver = makeAddr("receiver");

    function setUp() public override {
        super.setUp();
        controller.workaround_setMainVaultFor(asset, vault);
        vm.mockCall(address(share), abi.encodeWithSelector(IERC20Mintable.mint.selector), "");
    }

    function test_shouldRevert_whenCallerNotRegisteredVault() public {
        vm.expectRevert(Controller.Controller_CallerNotVault.selector);
        vm.prank(makeAddr("notVault"));
        controller.deposit(1000e18, receiver);
    }

    function test_shouldRevert_whenCallerNotMainVault() public {
        address notMainVault = makeAddr("notMainVault");
        _mockVault(notMainVault, asset, 1000e18, makeAddr("feed"), 1e8, 8, 0, 0, MAX_BPS);

        vm.expectRevert(Controller.Controller_CallerNotMainVault.selector);
        vm.prank(notMainVault);
        controller.deposit(1000e18, receiver);
    }

    function test_shouldRevert_whenControllerPaused() public {
        _mockVault(vault, asset, 1000e18, feed, 1e8, 8, 0, 0, MAX_BPS);
        controller.workaround_setPaused(true);

        vm.expectRevert(EmergencyManager.EmergencyManager_ControllerPaused.selector);
        vm.prank(vault);
        controller.deposit(1000e18, receiver);
    }

    function test_shouldRevert_whenOverMaxDeposit() public {
        _mockVault(vault, asset, 1000e18, makeAddr("feed"), 0.9e8, 8, 10_000e18, 0, MAX_BPS);

        vm.expectRevert(Controller.Controller_DepositExceedsMax.selector);
        vm.prank(vault);
        controller.deposit(100_000e18, receiver);
    }

    function test_shouldRevert_whenOtherVaultBelowMinProportionality() public {
        _mockVault(vault, asset, 1000e18, feed, 1e8, 8, 0, 0, MAX_BPS);
        _mockVault(makeAddr("vault2"), asset, 1000e18, makeAddr("feed2"), 1e8, 8, 0, 6000, MAX_BPS);

        vm.mockCall(address(share), abi.encodeWithSelector(IERC20.totalSupply.selector), abi.encode(2000e18));

        vm.expectRevert(Controller.Controller_DepositExceedsMax.selector);
        vm.prank(vault);
        controller.deposit(1000e18, receiver);
    }

    function testFuzz_shouldReturnShares_whenAssetPriceAboveMax(
        uint256 price,
        uint256 normalizedAssets
    )
        public
    {
        normalizedAssets = bound(normalizedAssets, 0, type(uint256).max / 1e20);
        price = bound(price, 1e8 + 1, 10e8);
        _mockVault(vault, asset, 1, feed, price, 8);

        vm.prank(vault);
        assertEq(controller.deposit(normalizedAssets, receiver), normalizedAssets);
    }

    function testFuzz_shouldReturnShares_whenAssetPriceBelowMax(
        uint256 price,
        uint256 normalizedAssets
    )
        public
    {
        normalizedAssets = bound(normalizedAssets, 0, type(uint256).max / 1e20);
        price = bound(price, 0.01e8, 1e8 - 1);
        _mockVault(vault, asset, 1, feed, price, 8);

        uint256 expectedShares = normalizedAssets * price / 1e8;

        vm.prank(vault);
        assertEq(controller.deposit(normalizedAssets, receiver), expectedShares);
    }

    function test_shouldRoundDown_whenSharesNotWholeNumber() public {
        _mockVault(vault, asset, 1, feed, 0.8e8, 8);

        vm.prank(vault);
        assertEq(controller.deposit(2, receiver), 1); // 2 * 0.8 = 1.6
    }

    function test_shouldMintSharesToReceiver() public {
        _mockVault(vault, asset, 1, feed, 1e8, 8);

        vm.expectCall(address(share), abi.encodeWithSelector(IERC20Mintable.mint.selector, receiver, 1000e18));

        vm.prank(vault);
        controller.deposit(1000e18, receiver);
    }
}

contract Controller_Mint_Test is ControllerTest {
    address vault = makeAddr("vault");
    address asset = makeAddr("asset");
    address feed = makeAddr("feed");
    address receiver = makeAddr("receiver");

    function setUp() public override {
        super.setUp();
        controller.workaround_setMainVaultFor(asset, vault);
        vm.mockCall(address(share), abi.encodeWithSelector(IERC20Mintable.mint.selector), "");
    }

    function test_shouldRevert_whenCallerNotRegisteredVault() public {
        vm.expectRevert(Controller.Controller_CallerNotVault.selector);
        vm.prank(makeAddr("notVault"));
        controller.mint(1000e18, receiver);
    }

    function test_shouldRevert_whenCallerNotMainVault() public {
        address notMainVault = makeAddr("notMainVault");
        _mockVault(notMainVault, asset, 1000e18, makeAddr("feed"), 1e8, 8, 0, 0, MAX_BPS);

        vm.expectRevert(Controller.Controller_CallerNotMainVault.selector);
        vm.prank(notMainVault);
        controller.mint(1000e18, receiver);
    }

    function test_shouldRevert_whenControllerPaused() public {
        _mockVault(vault, asset, 1000e18, feed, 1e8, 8, 0, 0, MAX_BPS);
        controller.workaround_setPaused(true);

        vm.expectRevert(EmergencyManager.EmergencyManager_ControllerPaused.selector);
        vm.prank(vault);
        controller.mint(1000e18, receiver);
    }

    function test_shouldRevert_whenOverMaxMint() public {
        _mockVault(vault, asset, 1000e18, feed, 1e8, 8, 10_000e18, 0, MAX_BPS);

        vm.expectRevert(Controller.Controller_MintExceedsMax.selector);
        vm.prank(vault);
        controller.mint(100_000e18, receiver);
    }

    function test_shouldRevert_whenOtherVaultBelowMinProportionality() public {
        _mockVault(vault, asset, 1000e18, feed, 1e8, 8, 0, 0, MAX_BPS);
        _mockVault(makeAddr("vault2"), asset, 1000e18, makeAddr("feed2"), 1e8, 8, 0, 6000, MAX_BPS);

        vm.mockCall(address(share), abi.encodeWithSelector(IERC20.totalSupply.selector), abi.encode(2000e18));

        vm.expectRevert(Controller.Controller_MintExceedsMax.selector);
        vm.prank(vault);
        controller.mint(1000e18, receiver);
    }

    function testFuzz_shouldReturnAssets_whenAssetPriceAboveMax(uint256 price, uint256 shares) public {
        shares = bound(shares, 0, type(uint256).max / 1e20);
        price = bound(price, 1e8 + 1, 10e8);
        _mockVault(vault, asset, 1, feed, price, 8);

        vm.prank(vault);
        assertEq(controller.mint(shares, receiver), shares);
    }

    function testFuzz_shouldReturnAssets_whenAssetPriceBelowMax(uint256 price, uint256 shares) public {
        shares = bound(shares, 0, type(uint256).max / 1e20);
        price = bound(price, 0.01e8, 1e8 - 1);
        _mockVault(vault, asset, 1, feed, price, 8);

        vm.prank(vault);
        assertApproxEqAbs(controller.mint(shares, receiver), shares * 1e8 / price, 1);
        // allow 1 wei difference due to rounding
    }

    function test_shouldRoundUp_whenAssetsNotWholeNumber() public {
        _mockVault(vault, asset, 1, feed, 0.8e8, 8);

        vm.prank(vault);
        assertEq(controller.mint(2, receiver), 3); // 2 / 0.8 = 2.5
    }

    function test_shouldMintSharesToReceiver() public {
        _mockVault(vault, asset, 1, feed, 1e8, 8);

        vm.expectCall(address(share), abi.encodeWithSelector(IERC20Mintable.mint.selector, receiver, 1000e18));

        vm.prank(vault);
        controller.mint(1000e18, receiver);
    }
}

contract Controller_Withdraw_Test is ControllerTest {
    address vault = makeAddr("vault");
    address asset = makeAddr("asset");
    address feed = makeAddr("feed");
    address spender = makeAddr("spender");
    address owner = makeAddr("owner");

    function setUp() public override {
        super.setUp();
        vm.mockCall(address(share), abi.encodeWithSelector(IERC20Mintable.burn.selector), "");
        vm.mockCall(address(share), abi.encodeWithSelector(IERC20.balanceOf.selector, owner), abi.encode(100e18));
        vm.mockCall(address(share), abi.encodeWithSelector(IERC20.totalSupply.selector), abi.encode(100e18));
    }

    function test_shouldRevert_whenCallerNotRegisteredVault() public {
        vm.expectRevert(Controller.Controller_CallerNotVault.selector);
        vm.prank(makeAddr("notVault"));
        controller.withdraw(100e18, spender, owner);
    }

    function test_shouldRevert_whenControllerPaused() public {
        _mockVault(vault, asset, 100e18, feed, 1e8, 8, 0, 0, MAX_BPS);
        controller.workaround_setPaused(true);

        vm.expectRevert(EmergencyManager.EmergencyManager_ControllerPaused.selector);
        vm.prank(vault);
        controller.withdraw(100e18, spender, owner);
    }

    function test_shouldRevert_whenAboveMaxWithdraw() public {
        _mockVault(vault, asset, 50e18, feed, 1e8, 8, 0, 0, MAX_BPS);

        vm.expectRevert(Controller.Controller_WithdrawExceedsMax.selector);
        vm.prank(vault);
        controller.withdraw(100e18, spender, owner);
    }

    function test_shouldRevert_whenOtherVaultAboveMaxProportionality() public {
        _mockVault(vault, asset, 100e18, feed, 1e8, 8, 0, 0, MAX_BPS);
        _mockVault(makeAddr("vault2"), asset, 100e18, makeAddr("feed2"), 1e8, 8, 0, 0, 4000);

        vm.mockCall(address(share), abi.encodeWithSelector(IERC20.totalSupply.selector), abi.encode(200e18));

        vm.expectRevert(Controller.Controller_WithdrawExceedsMax.selector);
        vm.prank(vault);
        controller.withdraw(100e18, spender, owner);
    }

    function test_shouldRevert_whenInsufficientBalance() public {
        _mockVault(vault, asset, 100e18, feed, 1e8, 8, 0, 0, MAX_BPS);

        vm.mockCall(address(share), abi.encodeWithSelector(IERC20.balanceOf.selector, owner), abi.encode(90e18));

        vm.expectRevert(Controller.Controller_WithdrawExceedsMax.selector);
        vm.prank(vault);
        controller.withdraw(100e18, spender, owner);
    }

    function testFuzz_shouldReturnShares_whenAssetPriceBelowMin_whenSharePriceOne(
        uint256 price,
        uint256 normalizedAssets
    )
        public
    {
        normalizedAssets = bound(normalizedAssets, 0, 100e18);
        price = bound(price, 0.01e8, 1e8 - 1);
        _mockVault(vault, asset, 100e18, feed, price, 8);
        vm.mockCall(address(share), abi.encodeWithSelector(IERC20.totalSupply.selector), abi.encode(1e18));

        vm.prank(vault);
        assertEq(controller.withdraw(normalizedAssets, spender, owner), normalizedAssets);
    }

    function testFuzz_shouldReturnShares_whenAssetPriceBelowMin_whenSharePriceLessThanOne(
        uint256 price,
        uint256 normalizedAssets
    )
        public
    {
        normalizedAssets = bound(normalizedAssets, 0, 10e18);
        price = bound(price, 0.1e8, 1e8 - 1);
        _mockVault(vault, asset, 100e18, feed, price, 8);

        uint256 shareRedemptionPrice = controller.shareRedemptionPrice();
        assertLt(shareRedemptionPrice, 1e18);

        uint256 expectedShares = normalizedAssets * 1e18 / shareRedemptionPrice;
        vm.prank(vault);
        assertApproxEqAbs(controller.withdraw(normalizedAssets, spender, owner), expectedShares, 1);
        // allow 1 wei difference due to rounding
    }

    function testFuzz_shouldReturnShares_whenAssetPriceAboveMin_whenSharePriceOne(
        uint256 price,
        uint256 normalizedAssets
    )
        public
    {
        normalizedAssets = bound(normalizedAssets, 0, 10e18);
        price = bound(price, 1e8 + 1, 10e8);
        _mockVault(vault, asset, 100e18, feed, price, 8);

        uint256 expectedShares = normalizedAssets * price / 1e8;
        vm.prank(vault);
        assertApproxEqAbs(controller.withdraw(normalizedAssets, spender, owner), expectedShares, 1);
        // allow 1 wei difference due to rounding
    }

    function testFuzz_shouldReturnShares_whenAssetPriceAboveMin_whenSharePriceLessThanOne(
        uint256 price,
        uint256 normalizedAssets
    )
        public
    {
        normalizedAssets = bound(normalizedAssets, 0, 1e18);
        price = bound(price, 1e8 + 1, 10e8);
        _mockVault(vault, asset, 1e18, feed, price, 8);

        uint256 shareRedemptionPrice = controller.shareRedemptionPrice();
        assertLt(shareRedemptionPrice, 1e18);

        uint256 expectedShares = normalizedAssets * price * 1e10 / shareRedemptionPrice; // * 1e18 / 1e8 = 1e10
        vm.prank(vault);
        assertApproxEqAbs(controller.withdraw(normalizedAssets, spender, owner), expectedShares, 1);
        // allow 1 wei difference due to rounding
    }

    function test_shouldRoundUp_whenSharesNotWholeNumber() public {
        _mockVault(vault, asset, 100e18, feed, 1.1e8, 8);

        vm.prank(vault);
        assertEq(controller.withdraw(2, spender, owner), 3); // 2 * 1.1 = 2.2
    }

    function test_shouldBurnSharesFromOwner() public {
        _mockVault(vault, asset, 100e18, feed, 1e8, 8);

        vm.expectCall(address(share), abi.encodeWithSelector(IERC20Mintable.burn.selector, owner, spender, 100e18));

        vm.prank(vault);
        controller.withdraw(100e18, spender, owner);
    }
}

contract Controller_Redeem_Test is ControllerTest {
    address vault = makeAddr("vault");
    address asset = makeAddr("asset");
    address feed = makeAddr("feed");
    address spender = makeAddr("spender");
    address owner = makeAddr("owner");

    function setUp() public override {
        super.setUp();
        vm.mockCall(address(share), abi.encodeWithSelector(IERC20Mintable.burn.selector), "");
        vm.mockCall(address(share), abi.encodeWithSelector(IERC20.balanceOf.selector, owner), abi.encode(100e18));
        vm.mockCall(address(share), abi.encodeWithSelector(IERC20.totalSupply.selector), abi.encode(100e18));
    }

    function test_shouldRevert_whenCallerNotRegisteredVault() public {
        vm.expectRevert(Controller.Controller_CallerNotVault.selector);
        vm.prank(makeAddr("notVault"));
        controller.redeem(100e18, spender, owner);
    }

    function test_shouldRevert_whenControllerPaused() public {
        _mockVault(vault, asset, 100e18, feed, 1e8, 8, 0, 0, MAX_BPS);
        controller.workaround_setPaused(true);

        vm.expectRevert(EmergencyManager.EmergencyManager_ControllerPaused.selector);
        vm.prank(vault);
        controller.redeem(100e18, spender, owner);
    }

    function test_shouldRevert_whenAboveMaxRedeem() public {
        _mockVault(vault, asset, 10e18, feed, 1e8, 8, 0, 0, MAX_BPS);
        _mockVault(makeAddr("vault2"), makeAddr("asset2"), 100e18, makeAddr("feed2"), 1e8, 8, 0, 0, MAX_BPS);

        vm.mockCall(address(share), abi.encodeWithSelector(IERC20.totalSupply.selector), abi.encode(110e18));

        vm.expectRevert(Controller.Controller_RedeemExceedsMax.selector);
        vm.prank(vault);
        controller.redeem(100e18, spender, owner);
    }

    function test_shouldRevert_whenOtherVaultAboveMaxProportionality() public {
        _mockVault(vault, asset, 100e18, feed, 1e8, 8, 0, 0, MAX_BPS);
        _mockVault(makeAddr("vault2"), makeAddr("asset2"), 100e18, makeAddr("feed2"), 1e8, 8, 0, 0, 4000);

        vm.mockCall(address(share), abi.encodeWithSelector(IERC20.totalSupply.selector), abi.encode(200e18));

        vm.expectRevert(Controller.Controller_RedeemExceedsMax.selector);
        vm.prank(vault);
        controller.redeem(100e18, spender, owner);
    }

    function test_shouldRevert_whenInsufficientBalance() public {
        _mockVault(vault, asset, 100e18, feed, 1e8, 8, 0, 0, MAX_BPS);

        vm.mockCall(address(share), abi.encodeWithSelector(IERC20.balanceOf.selector, owner), abi.encode(90e18));

        vm.expectRevert(Controller.Controller_RedeemExceedsMax.selector);
        vm.prank(vault);
        controller.redeem(100e18, spender, owner);
    }

    function testFuzz_shouldReturnAssets_whenAssetPriceBelowMin_whenSharePriceOne(
        uint256 price,
        uint256 shares
    )
        public
    {
        shares = bound(shares, 0, 100e18);
        price = bound(price, 0.01e8, 1e8 - 1);
        _mockVault(vault, asset, 100e18, feed, price, 8);
        vm.mockCall(address(share), abi.encodeWithSelector(IERC20.totalSupply.selector), abi.encode(1e18));

        vm.prank(vault);
        assertEq(controller.redeem(shares, spender, owner), shares);
    }

    function testFuzz_shouldReturnAssets_whenAssetPriceBelowMin_whenSharePriceLessThanOne(
        uint256 price,
        uint256 shares
    )
        public
    {
        shares = bound(shares, 0, 100e18);
        price = bound(price, 0.01e8, 1e8 - 1);
        _mockVault(vault, asset, 100e18, feed, price, 8);
        vm.mockCall(address(share), abi.encodeWithSelector(IERC20.totalSupply.selector), abi.encode(100e18));

        uint256 shareRedemptionPrice = controller.shareRedemptionPrice();
        assertLt(shareRedemptionPrice, 1e18);

        uint256 expectedAssets = shares * shareRedemptionPrice / 1e18;
        vm.prank(vault);
        assertApproxEqAbs(controller.redeem(shares, spender, owner), expectedAssets, 1);
        // allow 1 wei difference due to rounding
    }

    function testFuzz_shouldReturnAssets_whenAssetPriceAboveMin_whenSharePriceOne(
        uint256 price,
        uint256 shares
    )
        public
    {
        shares = bound(shares, 0, 100e18);
        price = bound(price, 1e8 + 1, 10e8);
        _mockVault(vault, asset, 100e18, feed, price, 8);
        vm.mockCall(address(share), abi.encodeWithSelector(IERC20.totalSupply.selector), abi.encode(100e18));

        uint256 expectedAssets = shares * 1e8 / price;
        vm.prank(vault);
        assertApproxEqAbs(controller.redeem(shares, spender, owner), expectedAssets, 1);
        // allow 1 wei difference due to rounding
    }

    function testFuzz_shouldReturnAssets_whenAssetPriceAboveMin_whenSharePriceLessThanOne(
        uint256 price,
        uint256 shares
    )
        public
    {
        shares = bound(shares, 0, 100e18);
        price = bound(price, 1e8 + 1, 10e8);
        _mockVault(vault, asset, 1e18, feed, price, 8);
        vm.mockCall(address(share), abi.encodeWithSelector(IERC20.totalSupply.selector), abi.encode(100e18));

        uint256 shareRedemptionPrice = controller.shareRedemptionPrice();
        assertLt(shareRedemptionPrice, 1e18);

        uint256 expectedAssets = shares * shareRedemptionPrice / 1e10 / price; // / 1e18 * 1e8 = 1e10
        vm.prank(vault);
        assertApproxEqAbs(controller.redeem(shares, spender, owner), expectedAssets, 1);
        // allow 1 wei difference due to rounding
    }

    function test_shouldRoundDown_whenAssetsNotWholeNumber() public {
        _mockVault(vault, asset, 100e18, feed, 1.1e8, 8);
        vm.mockCall(address(share), abi.encodeWithSelector(IERC20.totalSupply.selector), abi.encode(100e18));

        vm.prank(vault);
        assertEq(controller.redeem(2, spender, owner), 1); // 2 / 1.1 = 1.818...
    }

    function test_shouldBurnSharesFromOwner() public {
        _mockVault(vault, asset, 100e18, feed, 1e8, 8);

        vm.expectCall(address(share), abi.encodeWithSelector(IERC20Mintable.burn.selector, owner, spender, 100e18));

        vm.prank(vault);
        controller.redeem(100e18, spender, owner);
    }
}
