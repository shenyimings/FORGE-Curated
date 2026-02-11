// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.20;

import { IInbox } from "@arbitrum/nitro-contracts/src/bridge/IInbox.sol";

import { ArbitrumDVNAdapterL2 } from "./ArbitrumDVNAdapterL2.sol";
import { DVNAdapterBase } from "../DVNAdapterBase.sol";
import { DVNAdapterMessageCodec } from "../libs/DVNAdapterMessageCodec.sol";

contract ArbitrumDVNAdapterL1 is DVNAdapterBase {
    // --- Config Struct ---
    struct DstConfig {
        uint16 multiplierBps;
        uint256 maxSubmissionCost;
        uint256 gasLimit;
        uint256 maxFeePerGas;
    }

    // --- Events ---
    event RetryableTicketCreated(uint256 indexed ticketId);
    error OnlyArbitrum();

    uint32 public immutable arbitrumEid; // eid % 30000 (v1 eid)
    IInbox public immutable inbox;

    address public peer; // L2 adapter
    DstConfig public dstConfig;

    constructor(
        address[] memory _admins,
        uint32 _arbitrumEid,
        address _inbox
    ) DVNAdapterBase(msg.sender, _admins, 12000) {
        arbitrumEid = _arbitrumEid; // eid % 30000 (v1 eid)
        inbox = IInbox(_inbox);
    }

    // --- Admin ---
    function setPeer(address _peer) external onlyRole(ADMIN_ROLE) {
        peer = _peer;
    }

    function setDstConfig(
        uint16 _multiplierBps,
        uint256 _maxSubmissionCost,
        uint256 _gasLimit,
        uint256 _maxFeePerGas
    ) external onlyRole(ADMIN_ROLE) {
        dstConfig = DstConfig({
            multiplierBps: _multiplierBps,
            maxSubmissionCost: _maxSubmissionCost,
            gasLimit: _gasLimit,
            maxFeePerGas: _maxFeePerGas
        });
    }

    // --- Send ---
    function assignJob(
        AssignJobParam calldata _param,
        bytes calldata /*_options*/
    ) external payable override onlyRole(MESSAGE_LIB_ROLE) onlyAcl(_param.sender) returns (uint256 fee) {
        DstConfig storage config = dstConfig;
        fee = _getArbitrumFee(_param.dstEid, config);

        bytes memory payload = abi.encodeWithSelector(
            ArbitrumDVNAdapterL2.verify.selector,
            DVNAdapterMessageCodec.encode(
                receiveLibs[msg.sender][_param.dstEid],
                _param.packetHeader,
                _param.payloadHash
            )
        );

        // fee estimation: https://github.com/OffchainLabs/arbitrum-sdk/blob/main/src/lib/message/L1ToL2MessageCreator.ts#L52
        uint256 ticketID = inbox.createRetryableTicket{ value: fee }(
            peer,
            0,
            config.maxSubmissionCost,
            peer,
            peer,
            config.gasLimit,
            config.maxFeePerGas,
            payload
        );
        emit RetryableTicketCreated(ticketID);

        // adjust fee based on multiplier
        //        if (workerFeeLib != address(0)) {
        //            fee = IDVNAdapterFeeLib(workerFeeLib).getFee(
        //                _param.dstEid,
        //                _param.sender,
        //                defaultMultiplierBps,
        //                config.multiplierBps,
        //                fee
        //            );
        //        }
    }

    // --- View ---
    function getFee(
        uint32 _dstEid,
        uint64 /*_confirmations*/,
        address _sender,
        bytes calldata /*_options*/
    ) public view override onlyAcl(_sender) returns (uint256 fee) {
        DstConfig storage config = dstConfig;
        fee = _getArbitrumFee(_dstEid, config);

        // adjust fee based on multiplier
        //        if (workerFeeLib != address(0)) {
        //            fee = IDVNAdapterFeeLib(workerFeeLib).getFee(
        //                _dstEid,
        //                _sender,
        //                defaultMultiplierBps,
        //                config.multiplierBps,
        //                fee
        //            );
        //        }
    }

    function _getArbitrumFee(uint32 _dstEid, DstConfig storage _dstConfig) internal view returns (uint256 fee) {
        if (_dstEid % 30000 != arbitrumEid) revert OnlyArbitrum();
        fee = _dstConfig.maxSubmissionCost + _dstConfig.gasLimit * _dstConfig.maxFeePerGas;
    }
}
