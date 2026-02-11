// SPDX-License-Identifier: LZBL-1.2

pragma solidity ^0.8.20;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";

import { MultiCall } from "./MultiCall.sol";

/// @title EssenceDVNWrapper is a contract, used to execute multiple worker calls in a single transaction
/// The calls should be as follows:
/// 1. N calls to dvn.execute() to verify the payload on ULN
/// 2. 1 call to uln.commitVerification() to commit the verification into the endpoint
/// 3. 1 call to executor.execute() to execute lzReceive() on the endpoint
///
/// Node: The DVN should assign EssenceDVNWrapper as an admin to the DVN contract.
///
contract EssenceDVNWrapper is AccessControl, MultiCall {
    bytes32 internal constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    error DVNWrapper_InvalidRole(bytes32 role);
    error DVNWrapper_InvalidAdminCount();
    error DVNWrapper_RoleRenouncingDisabled();

    uint256 public adminCount;

    modifier onlyAdmin(bytes32 _role) {
        if (_role == ADMIN_ROLE) {
            _checkRole(_role); // admin required
        } else {
            revert DVNWrapper_InvalidRole(_role);
        }
        _;
    }

    constructor(address[] memory admins) {
        if (admins.length == 0) {
            revert DVNWrapper_InvalidAdminCount();
        }
        for (uint i = 0; i < admins.length; i++) {
            _setupRole(ADMIN_ROLE, admins[i]);
        }
        adminCount = admins.length;
    }

    function multiCall(
        Call[] calldata _calls
    ) public payable override onlyAdmin(ADMIN_ROLE) returns (bool[] memory successes, bytes[] memory results) {
        (successes, results) = super.multiCall(_calls);
    }

    // ========================= Override Functions =========================

    function grantRole(bytes32 _role, address _account) public override onlyAdmin(_role) {
        _grantRole(_role, _account);
    }

    function revokeRole(bytes32 _role, address _account) public override onlyAdmin(_role) {
        _revokeRole(_role, _account);
    }

    function renounceRole(bytes32 /*role*/, address /*account*/) public pure override {
        revert DVNWrapper_RoleRenouncingDisabled();
    }

    function _grantRole(bytes32 _role, address _account) internal override {
        if (_role == ADMIN_ROLE) ++adminCount;
        super._grantRole(_role, _account);
    }

    function _revokeRole(bytes32 _role, address _account) internal override {
        if (_role == ADMIN_ROLE) --adminCount;
        if (adminCount == 0) {
            revert DVNWrapper_InvalidAdminCount(); // not allowed to remove all admins
        }
        super._revokeRole(_role, _account);
    }
}
