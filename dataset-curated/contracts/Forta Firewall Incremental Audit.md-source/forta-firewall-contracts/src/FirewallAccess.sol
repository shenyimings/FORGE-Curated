// SPDX-License-Identifier: GNU General Public License Version 3
// See license at: https://github.com/forta-network/forta-firewall-contracts/blob/master/LICENSE-GPLv3.md

pragma solidity ^0.8.25;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import "./interfaces/IFirewallAccess.sol";

/// @dev All role ids are keccak256() of their names.
bytes32 constant FIREWALL_ADMIN_ROLE = 0x98e851166691f2754ebd45a95aded8e2022948d80311058644ab62dcc95eddca;
bytes32 constant PROTOCOL_ADMIN_ROLE = 0xd0c934f24ef5a377dc3832429ce607cbe940a3ca3c6cd7e532bd35b4b212d196;
bytes32 constant CHECKPOINT_MANAGER_ROLE = 0x2744166e218551d4b70cd805a1125548316250adef86b0e4941caa239677a49c;
bytes32 constant LOGIC_UPGRADER_ROLE = 0x8cd1a30abbcda9a4b45f36d916f90dd3359477439ecac772ba02d299a01d78cb;
bytes32 constant CHECKPOINT_EXECUTOR_ROLE = 0xae57c28fd3eb1dad9c6bc61e0a47e0f57230389fedc20e0381b101467bc4b075;
bytes32 constant ATTESTER_MANAGER_ROLE = 0xa6104eeb16757cf1b916694e5bc99107eaf38064b4948290b9f96447e33d6396;
bytes32 constant TRUSTED_ATTESTER_ROLE = 0x725a15d5fb1f1294f13d7272d4441134b951367ff5aebd74853471ce1cfb9cc4;

/**
 * @notice Keeps the set of accounts which can manage a firewall.
 */
contract FirewallAccess is AccessControl, IFirewallAccess {
    constructor(address _defaultAdmin) {
        _grantRole(DEFAULT_ADMIN_ROLE, _defaultAdmin);
        _setRoleAdmin(PROTOCOL_ADMIN_ROLE, FIREWALL_ADMIN_ROLE);
        _setRoleAdmin(CHECKPOINT_MANAGER_ROLE, PROTOCOL_ADMIN_ROLE);
        _setRoleAdmin(LOGIC_UPGRADER_ROLE, PROTOCOL_ADMIN_ROLE);
        _setRoleAdmin(CHECKPOINT_EXECUTOR_ROLE, PROTOCOL_ADMIN_ROLE);
        _setRoleAdmin(ATTESTER_MANAGER_ROLE, PROTOCOL_ADMIN_ROLE);
        _setRoleAdmin(TRUSTED_ATTESTER_ROLE, ATTESTER_MANAGER_ROLE);
    }

    /**
     * @notice Checks if the given address is a firewall admin.
     * @param caller Caller address.
     */
    function isFirewallAdmin(address caller) public view returns (bool) {
        return hasRole(FIREWALL_ADMIN_ROLE, caller);
    }

    /**
     * @notice Checks if the given address is a protocol admin.
     * @param caller Caller address.
     */
    function isProtocolAdmin(address caller) public view returns (bool) {
        return hasRole(PROTOCOL_ADMIN_ROLE, caller);
    }

    /**
     * @notice Checks if the given address is a checkpoint manager.
     * @param caller Caller address.
     */
    function isCheckpointManager(address caller) public view returns (bool) {
        return hasRole(PROTOCOL_ADMIN_ROLE, caller) || hasRole(CHECKPOINT_MANAGER_ROLE, caller);
    }

    /**
     * @notice Checks if the given address is a logic upgrader.
     * @param caller Caller address.
     */
    function isLogicUpgrader(address caller) public view returns (bool) {
        return hasRole(PROTOCOL_ADMIN_ROLE, caller) || hasRole(LOGIC_UPGRADER_ROLE, caller);
    }

    /**
     * @notice Checks if the given address is a checkpoint executor.
     * @param caller Caller address.
     */
    function isCheckpointExecutor(address caller) public view returns (bool) {
        return hasRole(PROTOCOL_ADMIN_ROLE, caller) || hasRole(CHECKPOINT_EXECUTOR_ROLE, caller);
    }

    /**
     * @notice Checks if the given address is an attester manager.
     * @param caller Caller address.
     */
    function isAttesterManager(address caller) public view returns (bool) {
        return hasRole(PROTOCOL_ADMIN_ROLE, caller) || hasRole(ATTESTER_MANAGER_ROLE, caller);
    }

    /**
     * @notice Checks if the given address is a trusted attester.
     * @param caller Caller address.
     */
    function isTrustedAttester(address caller) public view returns (bool) {
        return hasRole(TRUSTED_ATTESTER_ROLE, caller);
    }
}
