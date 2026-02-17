// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Access } from "../access/Access.sol";

import { IFractionalReserve } from "../interfaces/IFractionalReserve.sol";
import { FractionalReserveStorageUtils } from "../storage/FractionalReserveStorageUtils.sol";
import { FractionalReserveLogic } from "./libraries/FractionalReserveLogic.sol";

/// @title Fractional Reserve
/// @author kexley, @capLabs
/// @notice Idle capital is put to work in fractional reserve vaults and can be recalled when
/// withdrawing, redeeming or borrowing.
contract FractionalReserve is IFractionalReserve, Access, FractionalReserveStorageUtils {
    /// @dev Initialize the fractional reserve
    /// @param _accessControl Access control address
    /// @param _feeAuction Fee auction address
    function __FractionalReserve_init(address _accessControl, address _feeAuction) internal onlyInitializing {
        __Access_init(_accessControl);
        __FractionalReserve_init_unchained(_feeAuction);
    }

    /// @dev Initialize unchained
    /// @param _feeAuction Fee auction address
    function __FractionalReserve_init_unchained(address _feeAuction) internal onlyInitializing {
        getFractionalReserveStorage().feeAuction = _feeAuction;
    }

    /// @notice Invest unborrowed capital in a fractional reserve vault (up to the reserve)
    /// @param _asset Asset address
    function investAll(address _asset) external checkAccess(this.investAll.selector) {
        FractionalReserveLogic.invest(getFractionalReserveStorage(), _asset);
    }

    /// @notice Divest all of an asset from a fractional reserve vault and send any profit to fee auction
    /// @param _asset Asset address
    function divestAll(address _asset) external checkAccess(this.divestAll.selector) {
        FractionalReserveLogic.divest(getFractionalReserveStorage(), _asset);
    }

    /// @notice Divest some of an asset from a fractional reserve vault and send any profit to fee auction
    /// @param _asset Asset address
    /// @param _amountOut Amount of asset to divest
    function divest(address _asset, uint256 _amountOut) internal {
        FractionalReserveLogic.divest(getFractionalReserveStorage(), _asset, _amountOut);
    }

    /// @notice Divest some of many assets from a fractional reserve vault and send any profit to fee auction
    /// @param _assets Asset addresses
    /// @param _amountsOut Amounts of assets to divest
    function divestMany(address[] memory _assets, uint256[] memory _amountsOut) internal {
        FractionalReserveStorage storage $ = getFractionalReserveStorage();
        for (uint256 i; i < _assets.length; ++i) {
            FractionalReserveLogic.divest($, _assets[i], _amountsOut[i]);
        }
    }

    /// @notice Set the fractional reserve vault for an asset, divesting the old vault entirely
    /// @param _asset Asset address
    /// @param _vault Fractional reserve vault
    function setFractionalReserveVault(address _asset, address _vault)
        external
        checkAccess(this.setFractionalReserveVault.selector)
    {
        FractionalReserveStorage storage $ = getFractionalReserveStorage();
        FractionalReserveLogic.divest($, _asset);
        FractionalReserveLogic.setFractionalReserveVault($, _asset, _vault);
    }

    /// @notice Set the reserve level for an asset
    /// @param _asset Asset address
    /// @param _reserve Reserve level in asset decimals
    function setReserve(address _asset, uint256 _reserve) external checkAccess(this.setReserve.selector) {
        FractionalReserveLogic.setReserve(getFractionalReserveStorage(), _asset, _reserve);
    }

    /// @notice Realize interest from a fractional reserve vault and send to the fee auction
    /// @dev Left permissionless so arbitrageurs can move fees to auction
    /// @param _asset Asset address
    function realizeInterest(address _asset) external {
        FractionalReserveLogic.realizeInterest(getFractionalReserveStorage(), _asset);
    }

    /// @notice Interest from a fractional reserve vault
    /// @param _asset Asset address
    /// @return interest Claimable amount of asset
    function claimableInterest(address _asset) external view returns (uint256 interest) {
        interest = FractionalReserveLogic.claimableInterest(getFractionalReserveStorage(), _asset);
    }

    /// @notice Fractional reserve vault address for an asset
    /// @param _asset Asset address
    /// @return vaultAddress Vault address
    function fractionalReserveVault(address _asset) external view returns (address vaultAddress) {
        vaultAddress = getFractionalReserveStorage().vault[_asset];
    }

    /// @notice Reserve amount for an asset
    /// @param _asset Asset address
    /// @return reserveAmount Reserve amount
    function reserve(address _asset) external view returns (uint256 reserveAmount) {
        reserveAmount = getFractionalReserveStorage().reserve[_asset];
    }
}
