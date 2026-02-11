// SPDX-License-Identifier: UNLICENSED
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2024.
pragma solidity ^0.8.17;

import {IACL} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IACL.sol";

interface IACLExt is IACL {
    function addPausableAdmin(address addr) external;
    function removePausableAdmin(address addr) external;
    function addUnpausableAdmin(address addr) external;
    function removeUnpausableAdmin(address addr) external;
}
