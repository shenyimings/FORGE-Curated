// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {BARD} from "../BARD/BARD.sol";

contract BARDMock is BARD {
    constructor() BARD(address(1), address(2)) {}
}
