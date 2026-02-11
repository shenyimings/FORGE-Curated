// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2025.
pragma solidity ^0.8.23;

import {ILinearInterestRateModelV3} from "@gearbox-protocol/core-v3/contracts/interfaces/ILinearInterestRateModelV3.sol";
import {IStateSerializerLegacy} from "../../interfaces/IStateSerializerLegacy.sol";

contract LinearInterestRateModelSerializer is IStateSerializerLegacy {
    function serialize(address irm) external view override returns (bytes memory) {
        (uint16 U_1, uint16 U_2, uint16 R_base, uint16 R_slope1, uint16 R_slope2, uint16 R_slope3) =
            ILinearInterestRateModelV3(irm).getModelParameters();
        bool isBorrowingMoreU2Forbidden = ILinearInterestRateModelV3(irm).isBorrowingMoreU2Forbidden();
        return abi.encode(U_1, U_2, R_base, R_slope1, R_slope2, R_slope3, isBorrowingMoreU2Forbidden);
    }
}
