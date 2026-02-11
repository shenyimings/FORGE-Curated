// SPDX-License-Identifier: BUSL-1.1
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2024.
pragma solidity ^0.8.23;

import {IAddressProvider} from "../interfaces/IAddressProvider.sol";
import {AP_INSTANCE_MANAGER} from "./ContractLiterals.sol";
import {LibString} from "@solady/utils/LibString.sol";

library Domain {
    using LibString for string;
    using LibString for bytes32;

    function extractDomain(string memory str) internal pure returns (string memory) {
        uint256 separatorIndex = str.indexOf("::");

        // If no separator found, treat the whole name as domain
        if (separatorIndex == LibString.NOT_FOUND) {
            return str;
        }

        return str.slice(0, separatorIndex);
    }

    function extractDomain(bytes32 contractType) internal pure returns (bytes32) {
        return extractDomain(contractType.fromSmallString()).toSmallString();
    }
}
