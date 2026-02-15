// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Vault} from "./Vault.sol";

library ShareMath {
    uint256 internal constant PLACEHOLDER_UINT = 1;

    function assetToShares(uint256 assetAmount, uint256 assetPerShare, uint256 decimals)
        internal
        pure
        returns (uint256)
    {
        // If this throws, it means that vault's roundPricePerShare[currentRound] has not been set yet
        // which should never happen.
        // Has to be larger than 1 because `1` is used in `initRoundPricePerShares` to prevent cold writes.
        require(assetPerShare > PLACEHOLDER_UINT, "Invalid assetPerShare");

        return (assetAmount * (10 ** decimals)) / assetPerShare;
    }

    function sharesToAsset(uint256 shares, uint256 assetPerShare, uint256 decimals) internal pure returns (uint256) {
        // If this throws, it means that vault's roundPricePerShare[currentRound] has not been set yet
        // which should never happen.
        // Has to be larger than 1 because `1` is used in `initRoundPricePerShares` to prevent cold writes.
        require(assetPerShare > PLACEHOLDER_UINT, "Invalid assetPerShare");

        return (shares * assetPerShare) / (10 ** decimals);
    }

    /**
     * @notice Returns the shares unredeemed by the user given their StakeReceipt
     * @param stakeReceipt is the user's deposit receipt
     * @param currentRound is the `round` stored on the vault
     * @param assetPerShare is the price in asset per share
     * @param decimals is the number of decimals the asset/shares use
     * @return unredeemedShares is the user's virtual balance of shares that are owed
     */
    function getSharesFromReceipt(
        Vault.StakeReceipt memory stakeReceipt,
        uint256 currentRound,
        uint256 assetPerShare,
        uint256 decimals
    ) internal pure returns (uint256 unredeemedShares) {
        if (stakeReceipt.round > 0 && stakeReceipt.round < currentRound) {
            uint256 sharesFromRound = assetToShares(stakeReceipt.amount, assetPerShare, decimals);

            return uint256(stakeReceipt.unredeemedShares) + sharesFromRound;
        }
        return stakeReceipt.unredeemedShares;
    }

    function pricePerShare(uint256 totalSupply, uint256 totalBalance, uint256 pendingAmount, uint256 decimals)
        internal
        pure
        returns (uint256)
    {
        uint256 singleShare = 10 ** decimals;
        return totalSupply > 0 ? (singleShare * (totalBalance - pendingAmount)) / totalSupply : singleShare;
    }

    // #############################################
    // HELPERS
    // #############################################

    function assertUint104(uint256 num) internal pure {
        require(num <= type(uint104).max, "Overflow uint104");
    }

    function assertUint128(uint256 num) internal pure {
        require(num <= type(uint128).max, "Overflow uint128");
    }
}
