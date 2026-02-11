// SPDX-License-Identifier: GPL-3.0

/*
    This file is part of the Enzyme Protocol.
    (c) Enzyme Foundation <security@enzyme.finance>
    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity >=0.6.0 <0.9.0;

/// @title IVotiumMultiMerkleStash Interface
/// @author Enzyme Foundation <security@enzyme.finance>
interface IVotiumMultiMerkleStash {
    struct ClaimParam {
        address token;
        uint256 index;
        uint256 amount;
        bytes32[] merkleProof;
    }

    function updateMerkleRoot(address _token, bytes32 _merkleRoot) external;

    function owner() external view returns (address owner_);
}
