// SPDX-License-Identifier: MIT
// Likwid Contracts
pragma solidity ^0.8.0;

import {Math} from "./Math.sol";

import {PerLibrary} from "./PerLibrary.sol";

library FeeLibrary {
    function deductFrom(uint24 fee, uint256 amount) internal pure returns (uint256 amountWithoutFee) {
        uint256 ratio = PerLibrary.ONE_MILLION - fee;
        amountWithoutFee = Math.mulDiv(amount, ratio, PerLibrary.ONE_MILLION);
    }

    function deduct(uint24 fee, uint256 amount) internal pure returns (uint256 amountWithoutFee, uint256 feeAmount) {
        amountWithoutFee = deductFrom(fee, amount);
        feeAmount = amount - amountWithoutFee;
    }

    function attachFrom(uint24 fee, uint256 amount) internal pure returns (uint256 amountWithFee) {
        uint256 ratio = PerLibrary.ONE_MILLION - fee;
        amountWithFee = Math.mulDiv(amount, PerLibrary.ONE_MILLION, ratio);
    }

    function attach(uint24 fee, uint256 amount) internal pure returns (uint256 amountWithFee, uint256 feeAmount) {
        amountWithFee = attachFrom(fee, amount);
        feeAmount = amountWithFee - amount;
    }

    function part(uint24 fee, uint256 amount) internal pure returns (uint256 feeAmount) {
        feeAmount = Math.mulDiv(amount, uint256(fee), PerLibrary.ONE_MILLION);
    }

    function bound(uint24 fee, uint256 amount) internal pure returns (uint256 lower, uint256 upper) {
        lower = deductFrom(fee, amount);
        upper = attachFrom(fee, amount);
    }
}
