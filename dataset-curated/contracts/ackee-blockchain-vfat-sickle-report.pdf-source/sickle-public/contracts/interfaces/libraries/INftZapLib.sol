// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { NftZapIn, NftZapOut } from "contracts/structs/NftZapStructs.sol";

interface INftZapLib {
    function zapIn(
        NftZapIn memory zap
    ) external payable;

    function zapOut(
        NftZapOut memory zap
    ) external;
}
