// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

import { BaseController } from "./BaseController.sol";
import { VaultManager } from "./VaultManager.sol";
import { IControlledVault } from "../interfaces/IControlledVault.sol";

/**
 * @title AccountingLogic
 * @notice Abstract contract providing accounting logic for share and asset pricing calculations
 * @dev Inherits from BaseController and VaultManager to access vault operations and price feeds
 */
abstract contract AccountingLogic is BaseController, VaultManager {
    using Math for uint256;

    /**
     * @notice The fixed price used for minting new shares (1.0 in normalized decimals)
     */
    uint256 public constant SHARE_MINT_PRICE = 1 * 10 ** NORMALIZED_PRICE_DECIMALS;
    /**
     * @notice Maximum price cap for asset deposits to prevent overvaluation
     */
    uint256 public constant ASSET_DEPOSIT_MAX_PRICE = 1 * 10 ** NORMALIZED_PRICE_DECIMALS;
    /**
     * @notice Minimum price floor for asset redemptions to prevent undervaluation
     */
    uint256 public constant ASSET_REDEMPTION_MIN_PRICE = 1 * 10 ** NORMALIZED_PRICE_DECIMALS;

    /**
     * @notice Gets the price for depositing a specific asset, capped at maximum deposit price
     * @dev Uses the minimum between market price and maximum allowed deposit price
     * @param asset The address of the asset to get deposit price for
     * @return The asset deposit price, limited to ASSET_DEPOSIT_MAX_PRICE
     */
    function assetDepositPrice(address asset) public view returns (uint256) {
        return getAssetPrice(asset).min(ASSET_DEPOSIT_MAX_PRICE);
    }

    /**
     * @notice Gets the price for redeeming a specific asset, floored at minimum redemption price
     * @dev Uses the maximum between market price and minimum allowed redemption price
     * @param asset The address of the asset to get redemption price for
     * @return The asset redemption price, at least ASSET_REDEMPTION_MIN_PRICE
     */
    function assetRedemptionPrice(address asset) public view returns (uint256) {
        return getAssetPrice(asset).max(ASSET_REDEMPTION_MIN_PRICE);
    }

    /**
     * @notice Gets the fixed price for depositing/minting shares
     * @dev Returns a constant value as share minting always uses a fixed price
     * @return The share deposit price (always SHARE_MINT_PRICE)
     */
    function shareDepositPrice() public pure returns (uint256) {
        return SHARE_MINT_PRICE;
    }

    /**
     * @notice Calculates the current redemption price for shares based on backing value
     * @dev Price is calculated as backing value per share, with a max of SHARE_MINT_PRICE
     * @return The share redemption price based on total backing assets and share supply
     */
    function shareRedemptionPrice() public view returns (uint256) {
        return _shareRedemptionPrice(backingAssetsValue());
    }

    /**
     * @notice Calculates the total value of all backing assets across all vaults
     * @dev Iterates through all vaults, gets asset prices and vault balances, then sums the total value
     * @return totalValue The combined value of all vault assets in normalized decimals
     */
    function backingAssetsValue() public view returns (uint256 totalValue) {
        address[] memory _vaults = vaults();
        for (uint256 i; i < _vaults.length; ++i) {
            totalValue += _vaultValue(_vaults[i], IControlledVault(_vaults[i]).totalNormalizedAssets());
        }
    }

    /**
     * @notice Safety buffer amount maintained to stabilize share redemption prices
     * @dev Buffer is used to maintain stable share redemption prices during periods of expected
     * asset volatility, ensuring consistent pricing for share holders during market fluctuations.
     * @return The current safety buffer amount in normalized decimals
     */
    function safetyBuffer() public view returns (uint256) {
        return _safetyBuffer(backingAssetsValue());
    }

    /**
     * @notice Converts normalized asset amounts to share amounts using given prices
     * @param normalizedAssets The amount of normalized assets to convert
     * @param assetPrice The price of the asset in normalized decimals
     * @param sharePrice The price of shares in normalized decimals
     * @param rounding The rounding mode to use for division
     * @return The equivalent amount of shares
     */
    function _convertToShares(
        uint256 normalizedAssets,
        uint256 assetPrice,
        uint256 sharePrice,
        Math.Rounding rounding
    )
        internal
        pure
        returns (uint256)
    {
        return normalizedAssets.mulDiv(assetPrice, sharePrice, rounding);
    }

    /**
     * @notice Converts share amounts to normalized asset amounts using given prices
     * @param shares The amount of shares to convert
     * @param assetPrice The price of the asset in normalized decimals
     * @param sharePrice The price of shares in normalized decimals
     * @param rounding The rounding mode to use for division
     * @return The equivalent amount of normalized assets
     */
    function _convertToAssets(
        uint256 shares,
        uint256 assetPrice,
        uint256 sharePrice,
        Math.Rounding rounding
    )
        internal
        pure
        returns (uint256)
    {
        return shares.mulDiv(sharePrice, assetPrice, rounding);
    }

    /**
     * @notice Internal function to calculate share redemption price based on backing value and supply
     * @param backingValue The total value of backing assets
     * @return The calculated share redemption price
     */
    function _shareRedemptionPrice(uint256 backingValue) internal view returns (uint256) {
        uint256 shareTotalSupply = _share.totalSupply();
        if (backingValue >= shareTotalSupply) return SHARE_MINT_PRICE;
        return backingValue.mulDiv(10 ** NORMALIZED_PRICE_DECIMALS, shareTotalSupply);
    }

    /**
     * @notice Internal function to calculate the safety buffer based on backing value
     * @param backingValue The total value of backing assets
     * @return The calculated safety buffer amount
     */
    function _safetyBuffer(uint256 backingValue) internal view returns (uint256) {
        uint256 totalSupply = _share.totalSupply();
        return backingValue > totalSupply ? backingValue - totalSupply : 0;
    }
}
