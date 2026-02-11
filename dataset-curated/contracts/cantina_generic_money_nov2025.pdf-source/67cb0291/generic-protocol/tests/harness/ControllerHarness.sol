// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { Controller, Math } from "../../src/controller/Controller.sol";
import { IChainlinkAggregatorLike } from "../../src/interfaces/IChainlinkAggregatorLike.sol";

contract ControllerHarness is Controller {
    // ========================================
    // EXPOSED FUNCTIONS
    // ========================================

    function exposed_initializableStorageSlot() external pure returns (bytes32) {
        return _initializableStorageSlot();
    }

    function exposed_getInitializedVersion() external view returns (uint64) {
        return _getInitializedVersion();
    }

    function exposed_vaultsLinkedList(address vault) external view returns (address) {
        return _vaults[vault];
    }

    function exposed_convertToShares(
        uint256 normalizedAssets,
        uint256 assetPrice,
        uint256 sharePrice,
        Math.Rounding rounding
    )
        external
        pure
        returns (uint256)
    {
        return _convertToShares(normalizedAssets, assetPrice, sharePrice, rounding);
    }

    function exposed_convertToAssets(
        uint256 shares,
        uint256 assetPrice,
        uint256 sharePrice,
        Math.Rounding rounding
    )
        external
        pure
        returns (uint256)
    {
        return _convertToAssets(shares, assetPrice, sharePrice, rounding);
    }

    function exposed_vaultsOverview(bool calculateTotalValue) external view returns (VaultsOverview memory) {
        return _vaultsOverview(calculateTotalValue);
    }

    function exposed_maxDepositLimit(address vault) external view returns (uint256 max) {
        return _maxDepositLimit(_vaultsOverview(false), vault);
    }

    function exposed_maxWithdrawLimit(address vault) external view returns (uint256 max) {
        return _maxWithdrawLimit(_vaultsOverview(false), vault);
    }

    function exposed_maxDepositByThisVaultMaxCapacity(
        uint256 maxCapacity,
        uint256 vaultAssets
    )
        external
        pure
        returns (uint256)
    {
        VaultsOverview memory overview =
            VaultsOverview(new address[](1), new uint256[](1), new VaultSettings[](1), 0, 0);
        overview.settings[0].maxCapacity = uint224(maxCapacity);
        overview.assets[0] = vaultAssets;
        return _maxDepositByThisVaultMaxCapacity(overview, 0);
    }

    function exposed_maxDepositByThisVaultMaxProportionality(
        uint16 maxProportionality,
        uint256 vaultAssets,
        uint256 totalAssets
    )
        external
        pure
        returns (uint256)
    {
        VaultsOverview memory overview =
            VaultsOverview(new address[](1), new uint256[](1), new VaultSettings[](1), 0, 0);
        overview.settings[0].maxProportionality = maxProportionality;
        overview.assets[0] = vaultAssets;
        overview.totalAssets = totalAssets;
        return _maxDepositByThisVaultMaxProportionality(overview, 0);
    }

    function exposed_maxDepositByOtherVaultMinProportionality(
        uint16 minProportionality,
        uint256 vaultAssets,
        uint256 totalAssets
    )
        external
        pure
        returns (uint256)
    {
        VaultsOverview memory overview =
            VaultsOverview(new address[](1), new uint256[](1), new VaultSettings[](1), 0, 0);
        overview.settings[0].minProportionality = minProportionality;
        overview.assets[0] = vaultAssets;
        overview.totalAssets = totalAssets;
        return _maxDepositByOtherVaultMinProportionality(overview, 0);
    }

    function exposed_maxWithdrawByThisVaultMinProportionality(
        uint16 minProportionality,
        uint256 vaultAssets,
        uint256 totalAssets
    )
        external
        pure
        returns (uint256)
    {
        VaultsOverview memory overview =
            VaultsOverview(new address[](1), new uint256[](1), new VaultSettings[](1), 0, 0);
        overview.settings[0].minProportionality = minProportionality;
        overview.assets[0] = vaultAssets;
        overview.totalAssets = totalAssets;
        return _maxWithdrawByThisVaultMinProportionality(overview, 0);
    }

    function exposed_maxWithdrawByOtherVaultMaxProportionality(
        uint16 maxProportionality,
        uint256 vaultAssets,
        uint256 totalAssets
    )
        external
        pure
        returns (uint256)
    {
        VaultsOverview memory overview =
            VaultsOverview(new address[](1), new uint256[](1), new VaultSettings[](1), 0, 0);
        overview.settings[0].maxProportionality = maxProportionality;
        overview.assets[0] = vaultAssets;
        overview.totalAssets = totalAssets;
        return _maxWithdrawByOtherVaultMaxProportionality(overview, 0);
    }

    function exposed_vaultAssetsDeltaToHitProportionality(
        uint16 proportionalityLimit,
        uint256 vaultAssets,
        uint256 totalAssets
    )
        external
        pure
        returns (int256)
    {
        return _vaultAssetsDeltaToHitProportionality(proportionalityLimit, vaultAssets, totalAssets);
    }

    function exposed_totalAssetsDeltaToHitProportionality(
        uint16 proportionalityLimit,
        uint256 vaultAssets,
        uint256 totalAssets
    )
        external
        pure
        returns (int256)
    {
        return _totalAssetsDeltaToHitProportionality(proportionalityLimit, vaultAssets, totalAssets);
    }

    // ========================================
    // WORKAROUND FUNCTIONS
    // ========================================

    function workaround_setPriceFeedExists(address asset, bool exists) external {
        if (exists) {
            priceFeeds[asset] = PriceFeed(IChainlinkAggregatorLike(address(1)), 1);
        } else {
            delete priceFeeds[asset];
        }
    }

    function workaround_setPriceFeed(address asset, address feed, uint24 heartbeat) external {
        priceFeeds[asset] = PriceFeed(IChainlinkAggregatorLike(feed), heartbeat);
    }

    function workaround_addVault(address vault) external {
        assert(vault != SENTINEL_VAULTS && vault != address(0) && !isVault(vault));
        _vaults[vault] = _vaults[SENTINEL_VAULTS];
        _vaults[SENTINEL_VAULTS] = vault;
        _vaultsCount++;
    }

    function workaround_setMainVaultFor(address asset, address vault) external {
        _vaultFor[asset] = vault;
    }

    function workaround_setVaultSettings(
        address vault,
        uint224 maxCapacity,
        uint16 minProportionality,
        uint16 maxProportionality
    )
        external
    {
        assert(minProportionality <= maxProportionality && maxProportionality <= MAX_BPS);
        vaultSettings[vault] = VaultSettings({
            maxCapacity: maxCapacity, minProportionality: minProportionality, maxProportionality: maxProportionality
        });
    }

    function workaround_setRewardsCollector(address collector) external {
        rewardsCollector = collector;
    }

    function workaround_setRewardAsset(address asset, bool isReward) external {
        isRewardAsset[asset] = isReward;
    }

    function workaround_setPaused(bool _paused) public {
        paused = _paused;
    }

    function workaround_setSkipNextRebalanceSafetyBufferCheck(bool skip) public {
        skipNextRebalanceSafetyBufferCheck = skip;
    }

    function workaround_setSafetyBufferYieldDeduction(uint256 buffer) public {
        safetyBufferYieldDeduction = buffer;
    }

    function workaround_setMaxProtocolRebalanceSlippage(uint256 maxSlippage) public {
        assert(maxSlippage <= MAX_BPS);
        maxProtocolRebalanceSlippage = uint16(maxSlippage);
    }
}
