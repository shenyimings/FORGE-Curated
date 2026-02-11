// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IRateOracle } from "../interfaces/IRateOracle.sol";

/// @title RateOracleStorageUtils
/// @author kexley, @capLabs
/// @notice Storage utilities for RateOracle contract
abstract contract RateOracleStorageUtils {
    /// @dev keccak256(abi.encode(uint256(keccak256("cap.storage.RateOracle")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 constant RateOracleStorageLocation = 0xc2fe5bdef19b00667b17c16a6e885c9ed219a037de5cdf872528698fdc749f00;

    /// @notice Get rate oracle storage
    /// @return $ Storage pointer
    function getRateOracleStorage() internal pure returns (IRateOracle.RateOracleStorage storage $) {
        assembly {
            $.slot := RateOracleStorageLocation
        }
    }
}
