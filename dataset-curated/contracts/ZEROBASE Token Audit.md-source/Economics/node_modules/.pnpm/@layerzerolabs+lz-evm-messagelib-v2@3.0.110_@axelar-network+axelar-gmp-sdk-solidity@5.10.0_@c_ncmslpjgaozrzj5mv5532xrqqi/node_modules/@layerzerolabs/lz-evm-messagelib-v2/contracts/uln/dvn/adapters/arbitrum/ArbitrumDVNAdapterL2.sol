// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.20;

import { AddressAliasHelper } from "@arbitrum/nitro-contracts/src/libraries/AddressAliasHelper.sol";

import { DVNAdapterBase } from "../DVNAdapterBase.sol";

contract ArbitrumDVNAdapterL2 is DVNAdapterBase {
    // --- Errors ---
    error UntrustedPeer(address peer);

    // --- Events ---
    event PeerSet(address peer);

    // --- Variables ---
    address public peer; // L1 adapter

    constructor(address[] memory _admins) DVNAdapterBase(msg.sender, _admins, 12000) {}

    // --- Admin ---
    function setPeer(address _peer) external onlyRole(ADMIN_ROLE) {
        peer = _peer;
        emit PeerSet(_peer);
    }

    // --- Send ---
    function assignJob(
        AssignJobParam calldata /*_param*/,
        bytes calldata /*_options*/
    ) external payable override returns (uint256) {
        revert DVNAdapter_NotImplemented();
    }

    function getFee(
        uint32 /*_dstEid*/,
        uint64 /*_confirmations*/,
        address /*_sender*/,
        bytes calldata /*_options*/
    ) external pure override returns (uint256) {
        revert DVNAdapter_NotImplemented();
    }

    // --- Receive ---
    function verify(bytes calldata _payload) external {
        // To check that message came from L1, we check that the sender is the L1 contract's L2 alias.
        if (msg.sender != AddressAliasHelper.applyL1ToL2Alias(peer)) revert UntrustedPeer(msg.sender);
        _decodeAndVerify(0, _payload); //todo: fix
    }
}
