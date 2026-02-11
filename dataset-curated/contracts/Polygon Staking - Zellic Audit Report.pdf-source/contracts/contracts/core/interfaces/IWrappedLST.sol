// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import "./IERC677.sol";

interface IWrappedLST is IERC677 {
    /**
     * @notice wraps tokens
     * @param _amount amount of unwrapped tokens to wrap
     */
    function wrap(uint256 _amount) external;

    /**
     * @notice unwraps tokens
     * @param _amount amount of wrapped tokens to unwrap
     */
    function unwrap(uint256 _amount) external;

    /**
     * @notice Returns amount of unwrapped tokens for an amount of wrapped tokens
     * @param _amount amount of wrapped tokens
     * @return amount of unwrapped tokens
     */
    function getUnderlyingByWrapped(uint256 _amount) external view returns (uint256);

    function sdToken() external view returns (address);
}
