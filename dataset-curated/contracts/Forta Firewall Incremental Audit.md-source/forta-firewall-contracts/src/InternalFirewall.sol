// SPDX-License-Identifier: GNU General Public License Version 3
// See license at: https://github.com/forta-network/forta-firewall-contracts/blob/master/LICENSE-GPLv3.md

pragma solidity ^0.8.25;

import {Firewall} from "./Firewall.sol";
import "./interfaces/FirewallDependencies.sol";

/**
 * @notice This contract provides firewall functionality through inheritance. The child
 * contract must use the _secureExecution() function to check checkpoint
 * activation conditions and execute checkpoints. The storage used by the Firewall contract
 * is namespaced and causes no collision. The checkpoints must be adjusted by calling the
 * setCheckpoint() function.
 */
abstract contract InternalFirewall is Firewall {
    constructor(
        ISecurityValidator _validator,
        ICheckpointHook _checkpointHook,
        bytes32 _attesterControllerId,
        IFirewallAccess _firewallAccess
    ) {
        _updateFirewallConfig(_validator, _checkpointHook, _attesterControllerId, _firewallAccess);
    }

    modifier safeExecution() {
        _secureExecution();
        _;
    }
}
