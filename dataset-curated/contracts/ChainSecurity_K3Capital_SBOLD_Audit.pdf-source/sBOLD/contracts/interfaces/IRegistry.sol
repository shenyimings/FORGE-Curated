// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

/// @title IPriceOracle
/// @notice PriceOracle interface.
interface IRegistry {
    /// @notice Configuration struct for price oracles.
    struct Oracle {
        address base;
        address addr;
    }

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @dev Emitted on setting price oracles.
    event OraclesSet(Oracle[] oracles);

    /*//////////////////////////////////////////////////////////////
                                 FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Sets the different price oracles.
    /// @dev The priority of the price oracles should be as ordered.
    /// @param oracles The address of the base asset.
    function setOracles(Oracle[] memory oracles) external;
}
