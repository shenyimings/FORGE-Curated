// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../lib/create3-factory/src/ICREATE3Factory.sol";
import { FluidkeyEarnModule } from "../src/FluidkeyEarnModule.sol";
import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";

contract Create3Deployment is Script {
    ICREATE3Factory factory = ICREATE3Factory(0x9fBB3DF7C40Da2e5A0dE984fFE2CCB7C47cd0ABf);

    function run(
        address authorizedRelayer,
        address wrappedNative,
        bytes calldata salt
    )
        public
        view
    {
        // Encode the contract creation code and constructor arguments
        bytes memory creationCode = abi.encodePacked(
            type(FluidkeyEarnModule).creationCode, abi.encode(authorizedRelayer, wrappedNative)
        );

        // Encode the call to the deploy function of the Create3 factory
        bytes memory deployCalldata =
            abi.encodeWithSelector(factory.deploy.selector, bytes32(salt), creationCode);

        // Log the encoded calldata
        console.log("Encoded calldata for Create3 deploy:");
        console.logBytes(deployCalldata);
    }
}
