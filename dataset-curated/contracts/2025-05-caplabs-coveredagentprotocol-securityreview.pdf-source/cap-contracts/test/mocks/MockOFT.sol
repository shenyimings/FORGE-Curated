// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.22;

import { MockERC20 } from "./MockERC20.sol";

// Mock OFT token for testing
contract MockOFT is MockERC20 {
    constructor() MockERC20("MockOFT", "MOFT", 18) { }

    function token() external view returns (address) {
        return address(this);
    }
}
