// SPDX-FileCopyrightText: 2024 Lido <info@lido.fi>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.23;

import {ICoWSwapSettlement} from "../interfaces/ICoWSwapSettlement.sol";

/**
 * @title Stub for the CoWSwap's Settlement contract
 * @notice Contract is supposed to be used with the Order contract
 *     to return domain separator value, initiated on the stub deployment.
 */
contract CoWSwapSettlementStub is ICoWSwapSettlement {
    // ==================== Immutables ====================

    /**
     * @dev The domain separator used for signing orders that gets mixed in making signatures for
     * different domains incompatible. This domain separator is computed following the EIP-712
     * standard and has replay protection mixed in so that signed orders are only valid for
     * specific contracts.
     */
    bytes32 public immutable domainSeparator;

    // ==================== Constants ====================

    /**
     * @dev The EIP-712 domain type hash used for computing the domain separator.
     */
    bytes32 private constant DOMAIN_TYPE_HASH =
        keccak256(
            "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
        );

    /**
     * @dev The EIP-712 domain name used for computing the domain separator.
     */
    bytes32 private constant DOMAIN_NAME = keccak256("Settlement Instance Stub");

    /**
     * @dev The EIP-712 domain version used for computing the domain separator.
     */
    bytes32 private constant DOMAIN_VERSION = keccak256("v2");

    // ==================== Constructor ====================

    /**
     * @notice Initializes the contract and computes the domain separator.
     */
    constructor() {
        domainSeparator = keccak256(
            abi.encode(DOMAIN_TYPE_HASH, DOMAIN_NAME, DOMAIN_VERSION, block.chainid, address(this))
        );
    }
}
