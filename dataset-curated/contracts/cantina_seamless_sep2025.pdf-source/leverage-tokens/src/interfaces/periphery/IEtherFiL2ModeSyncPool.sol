// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

interface IEtherFiL2ModeSyncPool {
    /// @notice Deposits `tokenIn` into the EtherFi L2 Mode Sync Pool and returns `minAmountOut` of weETH
    /// @param tokenIn The address of the token to deposit. The token must be whitelisted
    /// @param amountIn The amount of `tokenIn` to deposit
    /// @param minAmountOut The minimum amount of weETH to receive
    /// @param referral The address of the referral
    /// @return amountOut The amount of weETH received
    function deposit(address tokenIn, uint256 amountIn, uint256 minAmountOut, address referral)
        external
        payable
        returns (uint256 amountOut);
}
