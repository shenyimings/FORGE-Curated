// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.22;

import { GovernanceMessageEVMCodec } from "../../../contracts/GovernanceMessageEVMCodec.sol";

contract GovernanceEVMCodecLibraryHelper {
    function decode(bytes calldata message) external pure returns (GovernanceMessageEVMCodec.GovernanceMessage memory) {
        return GovernanceMessageEVMCodec.decode(message);
    }
}