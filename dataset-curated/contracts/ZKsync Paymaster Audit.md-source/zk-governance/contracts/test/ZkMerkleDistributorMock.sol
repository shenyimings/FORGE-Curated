// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {IZkMerkleDistributor} from "../interfaces/IZkMerkleDistributor.sol";

contract ZkMerkleDistributorMock is IZkMerkleDistributor {
    function MERKLE_ROOT() external view returns (bytes32) {}

    function claim(uint256 _index, uint256 _amount, bytes32[] calldata _merkleProof) external {}
}
