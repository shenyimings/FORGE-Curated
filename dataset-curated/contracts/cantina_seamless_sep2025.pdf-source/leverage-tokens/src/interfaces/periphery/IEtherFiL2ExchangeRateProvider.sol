// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IEtherFiL2ExchangeRateProvider {
    /// @notice Get conversion amount for a token, given an amount in of token it should return the amount out. It also
    /// applies the deposit fee. Will revert if: - No rate oracle is set for the token - The rate is outdated (fresh
    /// period has passed)
    /// @param token The address of the token to convert
    /// @param amount The amount of `token` to convert
    /// @return amountOut The amount of weETH received
    function getConversionAmount(address token, uint256 amount) external view returns (uint256 amountOut);
}
