// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { BaseAdapter } from "./BaseAdapter.sol";
import { IBridgeCoordinator } from "../interfaces/IBridgeCoordinator.sol";
import { IBridgeAdapter } from "../interfaces/IBridgeAdapter.sol";
import { IMessageService } from "../interfaces/bridges/linea/IMessageService.sol";
import { ILineaBridgeAdapter } from "../interfaces/bridges/linea/ILineaBridgeAdapter.sol";
import { Bytes32AddressLib } from "../utils/Bytes32AddressLib.sol";
import { BridgeTypes } from "./BridgeTypes.sol";

/**
 * @title LineaBridgeAdapter
 * @notice Bridge adapter using Linea's Message Service for cross-chain messaging
 * @dev Handles message passing only - does NOT hold or manage tokens
 */
contract LineaBridgeAdapter is BaseAdapter, ILineaBridgeAdapter {
    /**
     * @notice Thrown when arbitrary calldata does not match the expected encoding format.
     */
    error InvalidParams();
    /**
     * @notice Thrown when the provided fee is insufficient for the bridge operation
     */
    error InsufficientFee();
    /**
     * @notice Thrown when refunding excess fee fails
     */
    error FeeRefundFailed();

    /**
     * @notice Emitted whenever the message service endpoint configured for a chain changes.
     * @param chainId The L2 chain identifier associated with the message service.
     * @param previousService The previously configured message service address.
     * @param newService The newly configured message service address.
     */
    event MessageServiceConfigured(
        uint256 indexed chainId, address indexed previousService, address indexed newService
    );

    /**
     * @notice Reverse lookup for authorised message services back to their origin chain id.
     */
    mapping(address messageService => uint256 chainId) public messageServiceToChainId;
    /**
     * @notice Mapping from chain id to the trusted message service contract.
     */
    mapping(uint256 chainId => address messageService) public chainIdToMessageService;

    constructor(IBridgeCoordinator _coordinator, address owner) BaseAdapter(_coordinator, owner) { }

    /// @inheritdoc BaseAdapter
    function _dispatchBridge(
        uint256 chainId,
        bytes32 remoteAdapter,
        bytes calldata message,
        address refundAddress,
        bytes calldata bridgeParams,
        bytes32 messageId
    )
        internal
        virtual
        override
    {
        IMessageService messageService = IMessageService(chainIdToMessageService[chainId]);
        require(address(messageService) != address(0), InvalidZeroAddress());

        bytes memory calldata_ = abi.encodeCall(ILineaBridgeAdapter.settleInboundBridge, (message, messageId));
        uint256 fee = estimateBridgeFee(chainId, message, bridgeParams);
        require(msg.value >= fee, InsufficientFee());

        messageService.sendMessage{ value: fee }(Bytes32AddressLib.toAddressFromLowBytes(remoteAdapter), fee, calldata_);

        if (msg.value > fee) {
            // Refund any excess fee to the refund address
            (bool success,) = payable(refundAddress).call{ value: msg.value - fee }("");
            require(success, FeeRefundFailed());
        }
    }

    /// @inheritdoc ILineaBridgeAdapter
    function settleInboundBridge(bytes calldata messageData, bytes32 messageId) external {
        IMessageService messageService = IMessageService(msg.sender);
        uint256 chainId = messageServiceToChainId[address(messageService)];

        // If the chain detected is 0, it means the message service isn't whitelisted
        require(chainId != 0, UnauthorizedCaller());

        bytes32 remoteSender = Bytes32AddressLib.toBytes32WithLowAddress(messageService.sender());
        coordinator.settleInboundMessage(bridgeType(), chainId, remoteSender, messageData, messageId);
    }

    /// @inheritdoc IBridgeAdapter
    function estimateBridgeFee(uint256, bytes calldata, bytes calldata) public pure returns (uint256 nativeFee) {
        // IMPORTANT: This is hardcoded to 0 because both Linea and Status sponsor transaction on their end.
        // The transactions sponsored on Linea can spend up to 250k gas, more than a million on Status end, which is
        // higher than the expected execution from our L2 proxy.
        return 0;
    }

    /// @inheritdoc BaseAdapter
    function bridgeType() public pure override returns (uint16) {
        return BridgeTypes.LINEA;
    }

    /**
     * @notice Updates the message service endpoint used for cross-chain messaging.
     * @dev Callable only by owner.
     * @param _messageService The new message service contract.
     */
    function setMessageService(address _messageService, uint256 _chainId) external onlyOwner {
        require(_messageService != address(0), InvalidZeroAddress());

        // We need to clean up the previous messageService if it exists
        address previousService = chainIdToMessageService[_chainId];

        emit MessageServiceConfigured(_chainId, previousService, _messageService);

        if (previousService != address(0)) {
            messageServiceToChainId[previousService] = 0;
        }
        messageServiceToChainId[_messageService] = _chainId;
        chainIdToMessageService[_chainId] = _messageService;
    }
}
