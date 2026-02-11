/* -*- c-basic-offset: 4 -*- */
/* solhint-disable gas-custom-errors */
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IMessageRecipient} from "@hyperlane-xyz/core/contracts/interfaces/IMessageRecipient.sol";
import {TypeCasts} from "@hyperlane-xyz/core/contracts/libs/TypeCasts.sol";
import {IPostDispatchHook} from "@hyperlane-xyz/core/contracts/interfaces/hooks/IPostDispatchHook.sol";

contract TestMailbox {
    using TypeCasts for bytes32;
    using TypeCasts for address;

    address public processor;

    uint32 public destinationDomain;

    bytes32 public recipientAddress;

    bytes public messageBody;

    bytes public metadata;

    address public relayer;

    bool public dispatched;

    bool public dispatchedWithRelayer;

    uint256 public constant FEE = 100000;

    constructor(address _processor) {
        processor = _processor;
    }

    function dispatch(
        uint32 _destinationDomain,
        bytes32 _recipientAddress,
        bytes calldata _messageBody,
        bytes calldata _metadata,
        IPostDispatchHook _relayer
    ) public payable returns (uint256) {
        destinationDomain = _destinationDomain;
        recipientAddress = _recipientAddress;
        messageBody = _messageBody;
        metadata = _metadata;
        relayer = address(_relayer);

        dispatchedWithRelayer = true;

        if (msg.value < FEE) {
            revert("no");
        }

        // Process the message if we have a processor
        // This simulates the cross-chain message being delivered
        if (processor != address(0)) {
            // In Hyperlane, the sender would be the prover contract on the source chain
            // which is passed as recipientAddress in the dispatch call
            IMessageRecipient(processor).handle(
                _destinationDomain, // The origin domain (source chain)
                _recipientAddress, // The sender (prover on source chain)
                _messageBody
            );
        }

        return (msg.value);
    }

    function process(bytes calldata) public pure {
        // solhint-disable-previous-line no-unused-vars
        // This function is kept for compatibility but not used in the new flow
        // The dispatch function handles the message processing directly
        return;
    }

    function quoteDispatch(
        uint32,
        bytes32,
        bytes calldata
    ) public pure returns (bytes32) {
        return bytes32(FEE);
    }

    function quoteDispatch(
        uint32,
        bytes32,
        bytes calldata,
        bytes calldata,
        IPostDispatchHook
    ) public pure returns (uint256) {
        return FEE;
    }

    function defaultHook() public pure returns (IPostDispatchHook) {
        return IPostDispatchHook(address(0));
    }

    function setProcessor(address _processor) public {
        processor = _processor;
    }
}
