// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface IClammFeeStrategy {
    /// @notice Computes the fee for an option purchase on CLAMM
    /// @param _optionMarket Address of the option market
    /// @param _amount Notional Amount
    /// @param _iv Implied Volatility
    /// @param _premium Total premium being charged for the option purchase
    /// @return fee the computed fee
    function onFeeReqReceive(address _optionMarket, uint256 _amount, uint256 _iv, uint256 _premium)
        external
        view
        returns (uint256 fee);
}
