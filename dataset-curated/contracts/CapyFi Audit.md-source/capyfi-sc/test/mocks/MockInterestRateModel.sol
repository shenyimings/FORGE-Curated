// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {InterestRateModel} from "../../src/contracts/InterestRateModel.sol";

// ---------------------------------------------------------------------
// Minimal mock for the InterestRateModel
// ---------------------------------------------------------------------

contract MockInterestRateModel is InterestRateModel {
    function getBorrowRate(uint, uint, uint) external pure override returns (uint) {
        return 2e16; // 2% (scaled by 1e18 => 0.02)
    }

    function getSupplyRate(uint, uint, uint, uint) external pure override returns (uint) {
        return 1e16; // 1%
    }
}