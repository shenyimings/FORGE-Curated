// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { IEIP712 } from "../../contracts/fillers/cowswap/Constants.sol";

contract MockEIP712 is IEIP712 {
    bytes32 public immutable domainSeparator;

    constructor(bytes32 _domainSeparator) {
        domainSeparator = _domainSeparator;
    }
}
