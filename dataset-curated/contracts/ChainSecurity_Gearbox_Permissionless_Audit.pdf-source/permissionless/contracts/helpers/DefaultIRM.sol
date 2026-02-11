// SPDX-License-Identifier: BUSL-1.1
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2024.
pragma solidity ^0.8.23;

import {IInterestRateModel} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IInterestRateModel.sol";
import {AP_INTEREST_RATE_MODEL_DEFAULT} from "../libraries/ContractLiterals.sol";

contract DefaultIRM is IInterestRateModel {
    uint256 public constant override version = 3_10;
    bytes32 public constant override contractType = AP_INTEREST_RATE_MODEL_DEFAULT;

    function calcBorrowRate(uint256, uint256, bool) external pure override returns (uint256) {
        return 0;
    }

    function availableToBorrow(uint256, uint256) external pure override returns (uint256) {
        return 0;
    }
}
