// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.20;

import { ICrossDomainMessenger } from "@eth-optimism/contracts/libraries/bridge/ICrossDomainMessenger.sol";

import { DVNAdapterBase } from "../DVNAdapterBase.sol";

contract OptimismDVNAdapterL2 is DVNAdapterBase {
    // --- Errors ---
    error UntrustedPeer(address peer);
    error Unauthorized();

    // --- Events ---
    event PeerSet(address indexed peer);

    address public immutable l2Messenger; // L2CrossDomainMessenger

    address public peer;

    constructor(address[] memory _admins, address _l2Messenger) DVNAdapterBase(msg.sender, _admins, 12000) {
        l2Messenger = _l2Messenger;
    }

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
        // assert messenger
        if (msg.sender != l2Messenger) revert Unauthorized();
        // assert peer
        address xSender = ICrossDomainMessenger(l2Messenger).xDomainMessageSender();
        if (xSender != peer) revert UntrustedPeer(xSender);

        _decodeAndVerify(0, _payload); //todo: fix
    }
}
