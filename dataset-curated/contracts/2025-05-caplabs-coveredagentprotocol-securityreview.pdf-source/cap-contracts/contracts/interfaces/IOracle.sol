// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IPriceOracle } from "./IPriceOracle.sol";
import { IRateOracle } from "./IRateOracle.sol";

/// @title Oracle
/// @author kexley, @capLabs
/// @notice Price and rate oracles are unified
interface IOracle is IPriceOracle, IRateOracle {
    /// @notice Oracle data
    struct OracleData {
        address adapter;
        bytes payload;
    }
}
