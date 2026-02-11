// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

/// @title Fractional Reserve Interface
/// @author kexley, @capLabs
/// @notice Interface for the Fractional Reserve contract
interface IFractionalReserve {
    /// @custom:storage-location erc7201:cap.storage.FractionalReserve
    struct FractionalReserveStorage {
        address feeAuction;
        mapping(address => uint256) loaned;
        mapping(address => uint256) reserve;
        mapping(address => address) vault;
    }

    /// @notice Invest unborrowed capital in a fractional reserve vault (up to the reserve)
    /// @param _asset Asset address
    function investAll(address _asset) external;

    /// @notice Divest all of an asset from a fractional reserve vault and send any profit to fee auction
    /// @param _asset Asset address
    function divestAll(address _asset) external;

    /// @notice Set the fractional reserve vault for an asset, divesting the old vault entirely
    /// @param _asset Asset address
    /// @param _vault Fractional reserve vault
    function setFractionalReserveVault(address _asset, address _vault) external;

    /// @notice Set the reserve level for an asset
    /// @param _asset Asset address
    /// @param _reserve Reserve level in asset decimals
    function setReserve(address _asset, uint256 _reserve) external;

    /// @notice Realize interest from a fractional reserve vault and send to the fee auction
    /// @dev Left permissionless so arbitrageurs can move fees to auction
    /// @param _asset Asset address
    function realizeInterest(address _asset) external;

    /// @notice Interest from a fractional reserve vault
    /// @param _asset Asset address
    /// @return interest Claimable amount of asset
    function claimableInterest(address _asset) external view returns (uint256 interest);

    /// @notice Fractional reserve vault address for an asset
    /// @param _asset Asset address
    /// @return vaultAddress Vault address
    function fractionalReserveVault(address _asset) external view returns (address vaultAddress);

    /// @notice Reserve amount for an asset
    /// @param _asset Asset address
    /// @return reserveAmount Reserve amount
    function reserve(address _asset) external view returns (uint256 reserveAmount);
}
