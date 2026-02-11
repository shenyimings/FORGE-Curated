// SPDX-FileCopyrightText: 2024 Lido <info@lido.fi>
// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {Stonks} from "../Stonks.sol";

/**
 * @title Test contract for Stonks functionality.
 */
contract StonksTest is Stonks {
    // ==================== Constructor ====================

    /**
     * @notice Initializes the test contract with Stonks parameters.
     * @param initParams_ Initialization parameters for the Stonks contract.
     */
    constructor(InitParams memory initParams_) Stonks(initParams_) {}

    // ==================== External View Functions ====================

    /**
     * @notice Gets the margin value for testing.
     * @return Margin in basis points.
     */
    function getMargin() external view returns (uint256) {
        return MARGIN_IN_BASIS_POINTS;
    }
}
