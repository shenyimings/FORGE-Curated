// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import {InvalidInitialization} from "../interfaces/Errors.sol";

contract Initializable {
    bool private initialized;

    constructor() {
        initialized = true;
    }

    function initialize(bytes calldata data) external {
        if (initialized) revert InvalidInitialization();
        initialized = true;
        _initialize(data);
    }

    function _initialize(bytes calldata data) internal virtual { }
}