/* -*- c-basic-offset: 4 -*- */
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IOriginSettler} from "../interfaces/ERC7683/IOriginSettler.sol";

import {Reward} from "../types/Intent.sol";
import {OnchainCrossChainOrder, ResolvedCrossChainOrder, GaslessCrossChainOrder, Output, FillInstruction, OrderData, ORDER_DATA_TYPEHASH} from "../types/ERC7683.sol";
import {AddressConverter} from "../libs/AddressConverter.sol";

/**
 * @title Eco7683OriginSettler
 * @notice Entry point to Eco Protocol via EIP-7683 with enhanced security and compliance
 * @dev Provides ERC-7683 compliant interface with replay protection and proper validation
 * @dev Features comprehensive validation, unified funding logic, and ERC-7683 compliance
 * @dev Includes protection against replay attacks through vault state checking
 */
abstract contract OriginSettler is IOriginSettler, EIP712 {
    using ECDSA for bytes32;
    using SafeERC20 for IERC20;
    using AddressConverter for bytes32;

    /// @notice typehash for gasless crosschain order
    bytes32 public GASLESS_CROSSCHAIN_ORDER_TYPEHASH =
        keccak256(
            "GaslessCrossChainOrder(address originSettler,address user,uint256 nonce,uint256 originChainId,uint32 openDeadline,uint32 fillDeadline,bytes32 orderDataType,bytes32 orderDataHash)"
        );

    /**
     * @notice Initializes the Eco7683OriginSettler with EIP-712 domain
     * @dev Sets up EIP-712 domain for signature verification with "EcoPortal" name and version "1"
     */
    constructor() EIP712("EcoPortal", "1") {}

    /**
     * @notice Opens an Eco intent directly on chain via ERC-7683 interface
     * @dev Called by the user to create and fund an intent atomically
     * @dev Validates ORDER_DATA_TYPEHASH and decodes OrderData for intent creation
     * @dev Uses unified _publishAndFund method for consistent behavior
     * @dev Emits Open event with ERC-7683 compliant ResolvedCrossChainOrder
     * @param order the OnchainCrossChainOrder containing embedded OrderData
     */
    function open(OnchainCrossChainOrder calldata order) external payable {
        if (order.orderDataType != ORDER_DATA_TYPEHASH) {
            revert TypeSignatureMismatch();
        }

        // Decode components individually to avoid Solidity's nested struct decoding issues
        OrderData memory orderData = abi.decode(order.orderData, (OrderData));

        (bytes32 orderId, ) = _publishAndFund(
            orderData.destination,
            orderData.route,
            orderData.reward,
            false,
            msg.sender
        );

        // block.timestamp is not going to overflow uint32 until 2106
        emit Open(orderId, _resolve(uint32(block.timestamp), orderData));
    }

    /**
     * @notice Opens an Eco intent on behalf of a user via ERC-7683 gasless interface
     * @dev Called by a solver to create an intent for a user using their signature
     * @dev Performs comprehensive validation: deadlines, signature, chain IDs, origin settler
     * @dev Includes replay protection through vault state checking in _publishAndFund
     * @dev Uses unified _publishAndFund method for consistent behavior and security
     * @dev Emits Open event with ERC-7683 compliant ResolvedCrossChainOrder
     * @param order the GaslessCrossChainOrder containing user signature and OrderData
     * @param signature the user's EIP-712 signature authorizing the intent creation
     */
    function openFor(
        GaslessCrossChainOrder calldata order,
        bytes calldata signature,
        bytes calldata /* originFillerData */
    ) external payable {
        if (block.timestamp > order.openDeadline) {
            revert OpenDeadlinePassed();
        }

        if (order.originSettler != address(this)) {
            revert InvalidOriginSettler(order.originSettler, address(this));
        }

        if (order.originChainId != block.chainid) {
            revert InvalidOriginChainId(order.originChainId, block.chainid);
        }

        if (order.orderDataType != ORDER_DATA_TYPEHASH) {
            revert TypeSignatureMismatch();
        }

        if (!_validateOrderSig(order, signature)) {
            revert InvalidSignature();
        }

        OrderData memory orderData = abi.decode(order.orderData, (OrderData));

        // No need for replay protection here
        // 1) If intent is Withdrawn or Refunded, it fails
        // 2) If intent is Initial, it publishes and funds
        // 3) If intent is Funded, it publishes and does nothing
        (bytes32 orderId, ) = _publishAndFund(
            orderData.destination,
            orderData.route,
            orderData.reward,
            false,
            order.user
        );

        emit Open(orderId, _resolve(order.openDeadline, orderData));
    }

    /**
     * @notice resolves an OnchainCrossChainOrder to a ResolvedCrossChainOrder
     * @param order the OnchainCrossChainOrder to be resolved
     */
    function resolve(
        OnchainCrossChainOrder calldata order
    ) public view returns (ResolvedCrossChainOrder memory) {
        OrderData memory orderData = abi.decode(order.orderData, (OrderData));

        // block.timestamp is not going to overflow uint32 until 2106
        return _resolve(uint32(block.timestamp), orderData);
    }

    /**
     * @notice resolves GaslessCrossChainOrder to a ResolvedCrossChainOrder
     * @param order the GaslessCrossChainOrder to be resolved
     * param originFillerData filler data for the origin chain (not used)
     */
    function resolveFor(
        GaslessCrossChainOrder calldata order,
        bytes calldata // originFillerData keeping it for purpose of interface
    ) public view returns (ResolvedCrossChainOrder memory) {
        OrderData memory orderData = abi.decode(order.orderData, (OrderData));

        return _resolve(order.openDeadline, orderData);
    }

    /**
     * @notice Helper method for signature verification
     * @dev Verifies that the gasless order was properly signed by the user
     * @param order The gasless cross-chain order to verify
     * @param signature The user's signature
     * @return True if the signature is valid, false otherwise
     */
    function _validateOrderSig(
        GaslessCrossChainOrder calldata order,
        bytes calldata signature
    ) internal view returns (bool) {
        bytes32 structHash = keccak256(
            abi.encode(
                GASLESS_CROSSCHAIN_ORDER_TYPEHASH,
                order.originSettler,
                order.user,
                order.nonce,
                order.originChainId,
                order.openDeadline,
                order.fillDeadline,
                order.orderDataType,
                keccak256(order.orderData)
            )
        );
        bytes32 hash = _hashTypedDataV4(structHash);
        address signer = hash.recover(signature);

        return signer == order.user;
    }

    /**
     * @notice Resolves order data into ERC-7683 compliant ResolvedCrossChainOrder format
     * @dev Converts Eco-specific OrderData into standardized format for off-chain solvers
     * @dev Uses orderData.maxSpent directly instead of reconstructing from route
     * @dev Correctly assigns chainIds: minReceived uses origin chain, native rewards use destination
     * @dev FillInstruction.originData contains (route, rewardHash) instead of full intent
     * @dev Addresses all ERC-7683 compliance issues identified in security review
     * @param openDeadline The deadline for opening the order
     * @param orderData The updated OrderData with maxSpent, routePortal, and routeDeadline
     * @return ResolvedCrossChainOrder ERC-7683 compliant format with proper field mappings
     */
    function _resolve(
        uint32 openDeadline,
        OrderData memory orderData
    ) public view returns (ResolvedCrossChainOrder memory) {
        uint256 rewardTokenCount = orderData.reward.tokens.length;
        Output[] memory minReceived = new Output[](
            rewardTokenCount + (orderData.reward.nativeAmount > 0 ? 1 : 0)
        );

        for (uint256 i = 0; i < rewardTokenCount; ++i) {
            minReceived[i] = Output(
                bytes32(uint256(uint160(orderData.reward.tokens[i].token))), // token
                orderData.reward.tokens[i].amount, // amount
                bytes32(uint256(uint160(address(0)))), // recipient is zero address
                block.chainid // chainId
            );
        }

        if (orderData.reward.nativeAmount > 0) {
            minReceived[rewardTokenCount] = Output(
                bytes32(0), // token
                orderData.reward.nativeAmount, // amount
                bytes32(uint256(uint160(address(0)))), // recipient is zero address
                block.chainid // chainId
            );
        }

        bytes32 routeHash = keccak256(orderData.route);
        bytes32 rewardHash = keccak256(abi.encode(orderData.reward));
        bytes32 intentHash = keccak256(
            abi.encodePacked(orderData.destination, routeHash, rewardHash)
        );

        FillInstruction[] memory fillInstructions = new FillInstruction[](1);
        bytes memory originData = abi.encode(orderData.route, rewardHash);
        fillInstructions[0] = FillInstruction(
            orderData.destination,
            orderData.routePortal,
            originData
        );

        return
            ResolvedCrossChainOrder(
                orderData.reward.creator,
                block.chainid,
                openDeadline,
                uint32(orderData.routeDeadline),
                intentHash,
                orderData.maxSpent,
                minReceived,
                fillInstructions
            );
    }

    /// @notice EIP712 domain separator
    function domainSeparatorV4() public view returns (bytes32) {
        return EIP712._domainSeparatorV4();
    }

    /**
     * @notice Core method for atomic intent creation and funding
     * @dev Abstract method to be implemented by derived contracts for unified intent handling
     * @dev Must handle both publishing new intents and funding existing ones atomically
     * @dev Provides replay protection through vault state checking in funding logic
     * @dev Should handle excess ETH return for optimal user experience
     * @dev Called by both open() and openFor() methods to ensure consistent behavior
     * @param destination Destination chain ID where the intent should be executed
     * @param route Encoded route data containing execution instructions for destination chain
     * @param reward The reward structure containing token amounts, creator, prover, and deadline
     * @param allowPartial Whether to accept partial funding if full funding is not possible
     * @param funder The address providing the funding (msg.sender for open(), order.user for openFor())
     * @return intentHash Unique identifier of the created or existing intent
     * @return vault Address of the intent's vault contract for reward escrow
     */
    function _publishAndFund(
        uint64 destination,
        bytes memory route,
        Reward memory reward,
        bool allowPartial,
        address funder
    ) internal virtual returns (bytes32 intentHash, address vault);
}
