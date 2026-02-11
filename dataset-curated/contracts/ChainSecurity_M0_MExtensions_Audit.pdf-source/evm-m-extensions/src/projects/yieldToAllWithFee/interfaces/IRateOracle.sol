// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.26;

/**
 * @title  Rate Oracle interface.
 * @author M0 Labs
 */
interface IRateOracle {
    /* ============ View/Pure Functions ============ */

    /**
     * @notice Returns the current value of the earner rate in basis points.
     */
    function earnerRate() external view returns (uint32);
}
