// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2025.
pragma solidity ^0.8.23;

import {IVersion} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IVersion.sol";
import {TokenData} from "../types/TokenData.sol";

interface ITokenCompressor is IVersion {
    function getTokens(address[] memory tokens) external view returns (TokenData[] memory);

    function getTokenInfo(address token) external view returns (TokenData memory);
}
