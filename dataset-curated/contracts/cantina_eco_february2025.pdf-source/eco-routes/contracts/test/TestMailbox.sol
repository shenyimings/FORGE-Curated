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
        bytes calldata _messageBody
    ) public payable returns (uint256) {
        destinationDomain = _destinationDomain;
        recipientAddress = _recipientAddress;
        messageBody = _messageBody;
        dispatched = true;

        if (processor != address(0)) {
            process(_messageBody);
        }

        if (msg.value < FEE) {
            revert("no");
        }

        return (msg.value);
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

        if (processor != address(0)) {
            process(_messageBody);
        }

        if (msg.value < FEE) {
            revert("no");
        }

        return (msg.value);
    }

    function process(bytes calldata _msg) public {
        IMessageRecipient(recipientAddress.bytes32ToAddress()).handle(
            uint32(block.chainid),
            msg.sender.addressToBytes32(),
            _msg
        );
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
        address
    ) public pure returns (bytes32) {
        return bytes32(FEE);
    }
}
