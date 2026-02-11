// SPDX-FileCopyrightText: 2024 Lido <info@lido.fi>
// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

import {GPv2Order} from "../lib/GPv2Order.sol";

/**
 * @title Helper contract for computing order hashes.
 */
contract HashHelper {
    using GPv2Order for GPv2Order.Data;
    using GPv2Order for bytes;

    // ==================== External Pure Functions ====================

    /**
     * @notice Computes the order hash for a given order and domain separator.
     * @param order Order data structure.
     * @param domainSeparator EIP-712 domain separator.
     * @return orderDigest The computed order hash.
     */
    function hash(
        GPv2Order.Data memory order,
        bytes32 domainSeparator
    ) external pure returns (bytes32 orderDigest) {
        return order.hash(domainSeparator);
    }
}
