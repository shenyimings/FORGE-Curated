// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IPriceOracle } from "../interfaces/IPriceOracle.sol";

/// @title PriceOracleStorageUtils
/// @author kexley, @capLabs
/// @notice Storage utilities for PriceOracle contract
contract PriceOracleStorageUtils {
    /// @dev keccak256(abi.encode(uint256(keccak256("cap.storage.PriceOracle")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 constant PriceOracleStorageLocation = 0x02a142d837c166bd77dc34adb0a38ff11e81f2f3e8008e975ef32f5fb877ac00;

    /// @notice Get price oracle storage
    /// @return $ Storage pointer
    function getPriceOracleStorage() internal pure returns (IPriceOracle.PriceOracleStorage storage $) {
        assembly {
            $.slot := PriceOracleStorageLocation
        }
    }
}
