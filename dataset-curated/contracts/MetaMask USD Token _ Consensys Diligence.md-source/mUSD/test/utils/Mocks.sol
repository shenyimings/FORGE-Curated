// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.26;

import { Initializable } from "../../lib/evm-m-extensions/lib/common/lib/openzeppelin-contracts-upgradeable/lib/openzeppelin-contracts/contracts/proxy/utils/Initializable.sol";

contract MUSDUpgrade is Initializable {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function bar() external pure returns (uint256) {
        return 1;
    }
}
