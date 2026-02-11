// SPDX-License-Identifier: GNU General Public License Version 3
// See license at: https://github.com/forta-network/forta-firewall-contracts/blob/master/LICENSE-GPLv3.md

pragma solidity ^0.8.25;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @notice Until the attestation can arrive on chain and the user transaction can be executed,
 * the asset amounts that will be processed can fluctuate slightly and cause different hashes
 * to be produced during the real execution and a mismatch with the values in the attestation.
 * This library solves this problem by quantizing the reference value used in checkpoint hash
 * computation.
 */
library Quantization {
    /**
     * @notice Quantizes the given value by zeroing the smaller digits.
     * @param n Input value.
     */
    function quantize(uint256 n) public pure returns (uint256) {
        uint256 offset = 8 * Math.log256(n);
        return ((n >> offset) << offset) + (2 ** offset) - 1;
    }
}
