/* -*- c-basic-offset: 4 -*- */
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {TokenAmount, Route, Call} from "./Intent.sol";
/**
 * @title EcoERC7683
 * @dev ERC7683 orderData subtypes designed for Eco Protocol
 */

/**
 * @notice contains everything which, when combined with other aspects of GaslessCrossChainOrder
 * is sufficient to publish an intent via Eco Protocol
 * @dev the orderData field of GaslessCrossChainOrder should be decoded as GaslessCrosschainOrderData\
 * @param route the route data
 * @param creator the address of the intent creator
 * @param prover the address of the prover contract this intent will be proven against
 * @param nativeValue the amount of native token offered as a reward
 * @param tokens the addresses and amounts of reward tokens
 */
struct OnchainCrosschainOrderData {
    Route route;
    address creator;
    address prover;
    uint256 nativeValue;
    TokenAmount[] rewardTokens;
}
/**
 * @notice contains everything which, when combined with other aspects of GaslessCrossChainOrder
 * is sufficient to publish an intent via Eco Protocol
 * @dev the orderData field of GaslessCrossChainOrder should be decoded as GaslessCrosschainOrderData
 * @param destination the ID of the chain where the intent was created
 * @param inbox the inbox contract on the destination chain that will fulfill the intent
 * @param calls the call instructions to be called during intent fulfillment
 * @param prover the address of the prover contract this intent will be proven against
 * @param nativeValue the amount of native token offered as a reward
 * @param tokens the addresses and amounts of reward tokens
 */
struct GaslessCrosschainOrderData {
    uint256 destination;
    address inbox;
    TokenAmount[] routeTokens;
    Call[] calls;
    address prover;
    uint256 nativeValue;
    TokenAmount[] rewardTokens;
}

//EIP712 typehashes
bytes32 constant ONCHAIN_CROSSCHAIN_ORDER_DATA_TYPEHASH = keccak256(
    "OnchainCrosschainOrderData(Route route,address creator,address prover,uint256 nativeValue,TokenAmount[] rewardTokens)Route(bytes32 salt,uint256 source,uint256 destination,address inbox,TokenAmount[] tokens,Call[] calls)TokenAmount(address token,uint256 amount)Call(address target,bytes data,uint256 value)"
);
bytes32 constant GASLESS_CROSSCHAIN_ORDER_DATA_TYPEHASH = keccak256(
    "GaslessCrosschainOrderData(uint256 destination,address inbox,TokenAmount[] routeTokens,Call[] calls,address prover,uint256 nativeValue,TokenAmount[] rewardTokens)TokenAmount(address token,uint256 amount)Call(address target,bytes data,uint256 value)"
);
