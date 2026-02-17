// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

/// @title IAccess
/// @author kexley, @capLabs
/// @notice Interface for Access contract
interface IMinter {
    /// @custom:storage-location erc7201:cap.storage.Minter
    struct MinterStorage {
        address oracle;
        uint256 redeemFee;
        mapping(address => FeeData) fees;
    }

    /// @dev Fee data set for an asset in a vault
    struct FeeData {
        uint256 slope0;
        uint256 slope1;
        uint256 mintKinkRatio;
        uint256 burnKinkRatio;
        uint256 optimalRatio;
    }

    /// @dev Parameters for applying fee slopes
    struct FeeSlopeParams {
        bool mint;
        uint256 amount;
        uint256 ratio;
    }

    /// @dev Parameters for minting or burning
    struct AmountOutParams {
        bool mint;
        address asset;
        uint256 amount;
    }

    /// @dev Parameters for redeeming
    struct RedeemAmountOutParams {
        uint256 amount;
    }

    /// @dev Fee data set for an asset in a vault
    event SetFeeData(address asset, FeeData feeData);

    /// @dev Redeem fee set
    event SetRedeemFee(uint256 redeemFee);

    /// @notice Get the mint amount for a given asset
    /// @param _asset Asset address
    /// @param _amountIn Amount of asset to use
    /// @return amountOut Amount minted
    function getMintAmount(address _asset, uint256 _amountIn) external view returns (uint256 amountOut);

    /// @notice Get the burn amount for a given asset
    /// @param _asset Asset address to withdraw
    /// @param _amountIn Amount of cap token to burn
    /// @return amountOut Amount of the asset withdrawn
    function getBurnAmount(address _asset, uint256 _amountIn) external view returns (uint256 amountOut);

    /// @notice Get the redeem amount
    /// @param _amountIn Amount of cap token to burn
    /// @return amountsOut Amounts of assets to be withdrawn
    function getRedeemAmount(uint256 _amountIn) external view returns (uint256[] memory amountsOut);

    /// @notice Set the allocation slopes and ratios for an asset
    /// @param _asset Asset address
    /// @param _feeData Fee slopes and ratios for the asset in the vault
    function setFeeData(address _asset, FeeData calldata _feeData) external;

    /// @notice Set the redeem fee
    /// @param _redeemFee Redeem fee amount
    function setRedeemFee(uint256 _redeemFee) external;
}
