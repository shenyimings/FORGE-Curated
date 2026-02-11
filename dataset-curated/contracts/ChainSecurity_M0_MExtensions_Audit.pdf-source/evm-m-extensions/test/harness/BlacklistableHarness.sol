// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.26;

import { Blacklistable } from "../../src/components/Blacklistable.sol";

contract BlacklistableHarness is Blacklistable {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address blacklistManager) public initializer {
        __Blacklistable_init(blacklistManager);
    }
}
