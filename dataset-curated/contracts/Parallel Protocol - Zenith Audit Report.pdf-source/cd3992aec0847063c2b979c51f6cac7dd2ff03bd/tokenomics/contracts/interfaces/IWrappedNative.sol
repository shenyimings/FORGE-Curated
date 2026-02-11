// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @notice Interface for WETH9.
 * See https://github.com/gnosis/canonical-weth/blob/0dd1ea3e295eef916d0c6223ec63141137d22d67/contracts/WETH9.sol
 */
interface IWrappedNative is IERC20 {
    /// @dev "wrap" native.
    function deposit() external payable;

    /// @dev "unwrap" to native.
    function withdraw(uint256 amount) external;
}
