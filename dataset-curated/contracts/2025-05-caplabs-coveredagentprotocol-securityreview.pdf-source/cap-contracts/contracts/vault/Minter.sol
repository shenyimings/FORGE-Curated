// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { Access } from "../access/Access.sol";

import { IMinter } from "../interfaces/IMinter.sol";
import { MinterStorageUtils } from "../storage/MinterStorageUtils.sol";
import { MinterLogic } from "./libraries/MinterLogic.sol";

/// @title Minter/burner for cap tokens
/// @author kexley, @capLabs
/// @notice Cap tokens are minted or burned in exchange for collateral ratio of the backing tokens
/// @dev Dynamic fees are applied according to the allocation of assets in the basket. Increasing
/// the supply of a excessive asset or burning for an scarce asset will charge fees on a kinked
/// slope. Redeem can be used to avoid these fees by burning for the current ratio of assets.
contract Minter is IMinter, Access, MinterStorageUtils {
    /// @dev Initialize the minter
    /// @param _accessControl Access control address
    /// @param _oracle Oracle address
    function __Minter_init(address _accessControl, address _oracle) internal onlyInitializing {
        __Access_init(_accessControl);
        __Minter_init_unchained(_oracle);
    }

    /// @dev Initialize unchained
    /// @param _oracle Oracle address
    function __Minter_init_unchained(address _oracle) internal onlyInitializing {
        getMinterStorage().oracle = _oracle;
    }

    /// @notice Get the mint amount for a given asset
    /// @param _asset Asset address
    /// @param _amountIn Amount of asset to use
    /// @return amountOut Amount minted
    function getMintAmount(address _asset, uint256 _amountIn) public view returns (uint256 amountOut) {
        amountOut =
            MinterLogic.amountOut(getMinterStorage(), AmountOutParams({ mint: true, asset: _asset, amount: _amountIn }));
    }

    /// @notice Get the burn amount for a given asset
    /// @param _asset Asset address to withdraw
    /// @param _amountIn Amount of cap token to burn
    /// @return amountOut Amount of the asset withdrawn
    function getBurnAmount(address _asset, uint256 _amountIn) public view returns (uint256 amountOut) {
        amountOut = MinterLogic.amountOut(
            getMinterStorage(), AmountOutParams({ mint: false, asset: _asset, amount: _amountIn })
        );
    }

    /// @notice Get the redeem amount
    /// @param _amountIn Amount of cap token to burn
    /// @return amountsOut Amounts of assets to be withdrawn
    function getRedeemAmount(uint256 _amountIn) public view returns (uint256[] memory amountsOut) {
        amountsOut = MinterLogic.redeemAmountOut(getMinterStorage(), RedeemAmountOutParams({ amount: _amountIn }));
    }

    /// @notice Set the allocation slopes and ratios for an asset
    /// @param _asset Asset address
    /// @param _feeData Fee slopes and ratios for the asset in the vault
    function setFeeData(address _asset, FeeData calldata _feeData) external checkAccess(this.setFeeData.selector) {
        getMinterStorage().fees[_asset] = _feeData;
        emit SetFeeData(_asset, _feeData);
    }

    /// @notice Set the redeem fee
    /// @param _redeemFee Redeem fee amount
    function setRedeemFee(uint256 _redeemFee) external checkAccess(this.setRedeemFee.selector) {
        getMinterStorage().redeemFee = _redeemFee;
        emit SetRedeemFee(_redeemFee);
    }
}
