// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Vm } from "@forge-std/Test.sol";

struct Users {
    // Admin
    Vm.Wallet admin;
    // DAO treasury.
    Vm.Wallet daoTreasury;
    // Insurance fund multisig.
    Vm.Wallet insuranceFundMultisig;
    // Impartial user.
    Vm.Wallet alice;
    // Impartial user.
    Vm.Wallet bob;
    // Malicious user.
    Vm.Wallet hacker;
}
