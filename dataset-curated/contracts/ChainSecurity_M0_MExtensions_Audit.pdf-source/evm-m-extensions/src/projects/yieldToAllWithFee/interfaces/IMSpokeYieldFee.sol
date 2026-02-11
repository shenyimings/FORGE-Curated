// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.26;

/**
 * @title  M Spoke Yield Fee interface.
 * @author M0 Labs
 */
interface IMSpokeYieldFee {
    /* ============ Custom Errors ============ */

    /// @notice Emitted in constructor if Rate Oracle is 0x0.
    error ZeroRateOracle();

    /* ============ View/Pure Functions ============ */

    /// @notice Returns the address of the Rate Oracle.
    function rateOracle() external view returns (address);
}
