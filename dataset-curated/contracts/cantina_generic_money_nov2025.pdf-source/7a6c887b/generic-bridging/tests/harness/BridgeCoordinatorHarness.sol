// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { BaseBridgeCoordinatorHarness } from "./BaseBridgeCoordinatorHarness.sol";

contract BridgeCoordinatorHarness is BaseBridgeCoordinatorHarness {
    struct LastRestrictCall {
        address whitelabel;
        address owner;
        uint256 amount;
    }
    LastRestrictCall public lastRestrictCall;

    function _restrictUnits(address whitelabel, address owner, uint256 amount) internal virtual override {
        lastRestrictCall = LastRestrictCall({ whitelabel: whitelabel, owner: owner, amount: amount });
    }

    struct LastReleaseCall {
        address whitelabel;
        address receiver;
        uint256 amount;
    }
    LastReleaseCall public lastReleaseCall;

    function _releaseUnits(address whitelabel, address receiver, uint256 amount) internal virtual override {
        lastReleaseCall = LastReleaseCall({ whitelabel: whitelabel, receiver: receiver, amount: amount });
    }
}
