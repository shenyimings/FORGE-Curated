// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { Test } from "forge-std/Test.sol";

import { ISwapper } from "../../src/interfaces/ISwapper.sol";
import { IYieldDistributor } from "../../src/interfaces/IYieldDistributor.sol";
import { IControlledVault } from "../../src/interfaces/IControlledVault.sol";
import { IChainlinkAggregatorLike } from "../../src/interfaces/IChainlinkAggregatorLike.sol";
import { GenericUnit } from "../../src/unit/GenericUnit.sol";
import { Controller } from "../../src/controller/Controller.sol";

import { ControllerHarness } from "../harness/ControllerHarness.sol";

contract ControllerHandler is Test {
    ControllerHarness public controller;

    GenericUnit public share;
    address public rewardsCollector = makeAddr("rewardsCollector");
    address public swapper = makeAddr("swapper");
    address public yieldDistributor = makeAddr("yieldDistributor");

    address[3] public vaults;
    address[3] public assets;
    address[3] public feeds;
    uint256[3] public vaultBalances;

    address owner = makeAddr("owner");

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
        controller.workaround_setMainVaultFor(asset, vault);
    }

    function _mockVaultAssets(address vault, uint256 _assets) internal {
        vm.mockCall(vault, abi.encodeWithSelector(IControlledVault.totalNormalizedAssets.selector), abi.encode(_assets));
    }

    constructor() {
        controller = new ControllerHarness();

        share = new GenericUnit(address(controller), "Generic Unit", "GU");

        // reset the Initializable storage slot to allow usage of deployed instance in tests
        vm.store(address(controller), controller.exposed_initializableStorageSlot(), bytes32(0));
        controller.initialize(
            address(this), share, rewardsCollector, ISwapper(swapper), IYieldDistributor(yieldDistributor)
        );

        vaults = [makeAddr("vault1"), makeAddr("vault2"), makeAddr("vault3")];
        assets = [makeAddr("asset1"), makeAddr("asset2"), makeAddr("asset3")];
        feeds = [makeAddr("feed1"), makeAddr("feed2"), makeAddr("feed3")];
        vaultBalances = [3000e18, 3000e18, 3000e18];

        for (uint256 i; i < vaults.length; ++i) {
            _mockVault(vaults[i], assets[i], vaultBalances[i], feeds[i], 1e8, 8, 10_000e18, 2000, 5000);
        }
    }

    function deposit(uint256 vaultIndex, uint256 _assets) external {
        vaultIndex = bound(vaultIndex, 0, vaults.length - 1);
        _assets = bound(_assets, 1, 10_000e18);

        vm.prank(vaults[vaultIndex]);
        controller.deposit(_assets, owner);

        vaultBalances[vaultIndex] += _assets;
        _mockVaultAssets(vaults[vaultIndex], vaultBalances[vaultIndex]);
    }

    function mint(uint256 vaultIndex, uint256 shares) external {
        vaultIndex = bound(vaultIndex, 0, vaults.length - 1);
        shares = bound(shares, 1, 10_000e18);

        vm.prank(vaults[vaultIndex]);
        uint256 _assets = controller.mint(shares, owner);

        vaultBalances[vaultIndex] += _assets;
        _mockVaultAssets(vaults[vaultIndex], vaultBalances[vaultIndex]);
    }

    function withdraw(uint256 vaultIndex, uint256 _assets) external {
        vaultIndex = bound(vaultIndex, 0, vaults.length - 1);
        _assets = bound(_assets, 1, vaultBalances[vaultIndex]);

        vm.prank(vaults[vaultIndex]);
        controller.withdraw(_assets, owner, owner);

        vaultBalances[vaultIndex] -= _assets;
        _mockVaultAssets(vaults[vaultIndex], vaultBalances[vaultIndex]);
    }

    function redeem(uint256 vaultIndex, uint256 shares) external {
        vaultIndex = bound(vaultIndex, 0, vaults.length - 1);
        shares = bound(shares, 1, vaultBalances[vaultIndex]);

        vm.prank(vaults[vaultIndex]);
        uint256 _assets = controller.redeem(shares, owner, owner);

        vaultBalances[vaultIndex] -= _assets;
        _mockVaultAssets(vaults[vaultIndex], vaultBalances[vaultIndex]);
    }
}

contract ControllerInvariantTest is Test {
    ControllerHandler handler;

    function setUp() public virtual {
        handler = new ControllerHandler();

        excludeContract(address(handler.share()));
        excludeContract(address(handler.controller()));
    }

    function invariant_vaultsMustNotGetOutOfLimits() public view {
        Controller.VaultsOverview memory overview = handler.controller().exposed_vaultsOverview(false);
        for (uint256 i; i < overview.vaults.length; ++i) {
            assertLe(overview.assets[i], overview.settings[i].maxCapacity);
            assertGe(overview.assets[i], overview.totalAssets * overview.settings[i].minProportionality / 1e4);
            assertLe(overview.assets[i], overview.totalAssets * overview.settings[i].maxProportionality / 1e4);
        }
    }

    function invariant_sumOfAllVaultAssetsMustEqualTotalAssets() public view {
        Controller.VaultsOverview memory overview = handler.controller().exposed_vaultsOverview(false);
        uint256 sum;
        for (uint256 i; i < overview.vaults.length; ++i) {
            sum += overview.assets[i];
        }
        assertEq(sum, overview.totalAssets);
    }
}
