// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.29;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {LibString} from "solady/utils/LibString.sol";

import {BuilderCodes} from "../src/BuilderCodes.sol";

contract LookupAllowedCharacters is Script {
    function run() external {
        BuilderCodes codes = new BuilderCodes();
        console.log("Allowed characters:", LibString.to7BitASCIIAllowedLookup(codes.ALLOWED_CHARACTERS()));
    }
}
