// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.20;

import { ICrossDomainMessenger } from "@eth-optimism/contracts/libraries/bridge/ICrossDomainMessenger.sol";

import { OptimismDVNAdapterL2 } from "./OptimismDVNAdapterL2.sol";
import { DVNAdapterMessageCodec } from "../libs/DVNAdapterMessageCodec.sol";
import { DVNAdapterBase } from "../DVNAdapterBase.sol";

/// @title OptimismDVNAdapterL1
/// @dev How Optimism DVN adapter works:
///  1. call `sendMessage` on the L1CrossDomainMessenger contract.
///     refer to https://docs.optimism.io/builders/dapp-developers/bridging/messaging#basics-of-communication-between-layers
/// @dev Recovery:
///  1. If the message is not executed or failed to execute on the destination chain, you can manually retry by calling `relayMessage` on the `CrossDomainMessenger` contract.
///     refer to https://github.com/ethereum-optimism/optimism/blob/develop/packages/contracts-bedrock/src/universal/CrossDomainMessenger.sol#L211C14-L211C26
contract OptimismDVNAdapterL1 is DVNAdapterBase {
    // --- Errors ---
    error OnlyOptimism();
    error NoPeer();

    // --- Events ---
    event PeerSet(address indexed peer);
    event GasLimitSet(uint32 gasLimit);

    uint32 public immutable optimismEid; // eid % 30000 (v1 eid)
    address public immutable l1Messenger; // L1CrossDomainMessenger

    uint32 public gasLimit;
    address public peer;

    constructor(
        address[] memory _admins,
        uint32 _optimismEid,
        address _l1Messenger
    ) DVNAdapterBase(msg.sender, _admins, 12000) {
        optimismEid = _optimismEid; // eid % 30000 (v1 eid)
        l1Messenger = _l1Messenger;
    }

    // --- Admin ---
    function setGasLimit(uint32 _gasLimit) external onlyRole(ADMIN_ROLE) {
        gasLimit = _gasLimit;
        emit GasLimitSet(_gasLimit);
    }

    function setPeer(address _peer) external onlyRole(ADMIN_ROLE) {
        peer = _peer;
        emit PeerSet(_peer);
    }

    // --- Send ---
    function assignJob(
        AssignJobParam calldata _param,
        bytes calldata /*_options*/
    ) external payable override onlyAcl(_param.sender) returns (uint256) {
        _getAndAssertReceiveLib(msg.sender, _param.dstEid);

        if (_param.dstEid % 30000 != optimismEid) revert OnlyOptimism();
        if (peer == address(0)) revert NoPeer();

        bytes memory payload = abi.encodeWithSelector(
            OptimismDVNAdapterL2.verify.selector,
            DVNAdapterMessageCodec.encode(
                receiveLibs[msg.sender][_param.dstEid],
                _param.packetHeader,
                _param.payloadHash
            )
        );
        ICrossDomainMessenger(l1Messenger).sendMessage(peer, payload, gasLimit);

        return 0;
    }

    // --- View ---
    function getFee(
        uint32 /*_dstEid*/,
        uint64 /*_confirmations*/,
        address _sender,
        bytes calldata /*_options*/
    ) public view override onlyAcl(_sender) returns (uint256) {
        // no fee, charged as gas when sending message from L1 to L2
        return 0;
    }
}
