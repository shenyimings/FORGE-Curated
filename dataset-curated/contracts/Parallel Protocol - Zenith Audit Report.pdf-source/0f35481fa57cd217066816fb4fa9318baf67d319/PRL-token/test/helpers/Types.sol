// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Vm } from "@forge-std/Test.sol";

struct Users {
    // Default owner for all contracts.
    Vm.Wallet owner;
    // Impartial user.
    Vm.Wallet alice;
    // Impartial user.
    Vm.Wallet bob;
    // Malicious user.
    Vm.Wallet hacker;
}
