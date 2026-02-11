// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "../interfaces/IERC20Mintable.sol";

contract MerkleAirdrop is Ownable {
    IERC20Mintable immutable token;
    mapping(uint256 => bytes32) public merkleRoots;
    mapping(address => mapping(uint256 => uint256)) public claimedBitMap;

    event Claimed(uint256 index, address account, uint256 amount);

    constructor(address tokenAddress) {
        token = IERC20Mintable(tokenAddress);
    }

    function isClaimed(uint256 index) public view returns (bool) {
        uint256 claimedWordIndex = index / 256;
        uint256 claimedBitIndex = index % 256;
        uint256 claimedWord = claimedBitMap[_msgSender()][claimedWordIndex];
        uint256 mask = (1 << claimedBitIndex);
        return claimedWord & mask == mask;
    }

    function isClaimed(uint256[] calldata indexes) external view returns (bool[] memory) {
        bool[] memory result = new bool[](indexes.length);
        for (uint256 i = 0; i < indexes.length; i++) {
            result[i] = isClaimed(indexes[i]);
        }
        return result;
    }

    function _setClaimed(uint256 index) private {
        uint256 claimedWordIndex = index / 256;
        uint256 claimedBitIndex = index % 256;
        claimedBitMap[_msgSender()][claimedWordIndex] |= (1 << claimedBitIndex);
    }

    function claim(uint256 index, uint256 amount, bytes32[] calldata merkleProof) external {
        require(!isClaimed(index), "MerkleAirdrop: Drop already claimed.");
        require(merkleRoots[index] != 0, "Airdrop: MerkleRoot not set for this day.");

        bytes32 node = keccak256(abi.encodePacked(_msgSender(), amount));
        require(MerkleProof.verify(merkleProof, merkleRoots[index], node), "MerkleAirdrop: Invalid proof.");

        _setClaimed(index);

        token.mint(_msgSender(), amount);

        emit Claimed(index, _msgSender(), amount);
    }

    function claimMultiple(
        uint256[] calldata indexes,
        uint256[] calldata amounts,
        bytes32[][] calldata merkleProofs
    ) external {
        require(indexes.length == amounts.length && indexes.length == merkleProofs.length, "Airdrop: Parameters length mismatch.");

        uint256 totalAmount = 0;

        for (uint256 i = 0; i < indexes.length; i++) {
            uint256 index = indexes[i];
            uint256 amount = amounts[i];
            bytes32[] calldata merkleProof = merkleProofs[i];

            require(!isClaimed(index), "Airdrop: Some drops already claimed for this day.");
            bytes32 merkleRoot = merkleRoots[index];
            require(merkleRoot != 0, "Airdrop: MerkleRoot not set for this day.");

            bytes32 leaf = keccak256(abi.encodePacked(_msgSender(), amount));
            require(
                MerkleProof.verify(merkleProof, merkleRoot, leaf),
                "Airdrop: Invalid proof."
            );

            _setClaimed(index);

            totalAmount += amount;

            emit Claimed(index, _msgSender(), amount);
        }

        token.mint(_msgSender(), totalAmount);
    }

    function setMerkleRoot(uint256 index, bytes32 merkleRoot) external onlyOwner {
        merkleRoots[index] = merkleRoot;
    }
}
