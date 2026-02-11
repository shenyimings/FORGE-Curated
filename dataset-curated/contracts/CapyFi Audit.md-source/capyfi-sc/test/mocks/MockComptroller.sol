// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {ComptrollerInterface} from "../../src/contracts/ComptrollerInterface.sol";

// ---------------------------------------------------------------------
// Minimal mock for the Comptroller
// Implements all abstract functions from the interface
// ---------------------------------------------------------------------
contract MockComptroller is ComptrollerInterface {
    // ---------- Policy Hooks (Allowed) ----------
    function mintAllowed(address, address, uint) external pure override returns (uint) {
        return 0; // always allow
    }
    function redeemAllowed(address, address, uint) external pure override returns (uint) {
        return 0; // always allow
    }
    function borrowAllowed(address, address, uint) external pure override returns (uint) {
        return 0; // always allow
    }
    function repayBorrowAllowed(address, address, address, uint) external pure override returns (uint) {
        return 0; // always allow
    }
    function liquidateBorrowAllowed(address, address, address, address, uint) external pure override returns (uint) {
        return 0; // always allow
    }
    function seizeAllowed(address, address, address, address, uint) external pure override returns (uint) {
        return 0; // always allow
    }
    function transferAllowed(address, address, address, uint) external pure override returns (uint) {
        return 0; // always allow
    }

    // ---------- Policy Hooks (Verify stubs) ----------
    function mintVerify(address, address, uint, uint) external pure override {}
    function redeemVerify(address, address, uint, uint) external pure override {}
    function borrowVerify(address, address, uint) external pure override {}
    function repayBorrowVerify(address, address, address, uint, uint) external pure override {}
    function liquidateBorrowVerify(address, address, address, address, uint, uint) external pure override {}
    function seizeVerify(address, address, address, address, uint) external pure override {}
    function transferVerify(address, address, address, uint) external pure override {}

    // ---------- Additional / Not used in tests ----------
    function liquidateCalculateSeizeTokens(address, address, uint) external pure override returns (uint, uint) {
        // For test simplicity, we won't revert, but we won't do anything
        return (0, 0);
    }
    function enterMarkets(address[] calldata) external pure override returns (uint[] memory) {
        revert("not implemented");
    }
    function exitMarket(address) external pure override returns (uint) {
        revert("not implemented");
    }
}