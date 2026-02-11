// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {IDegenDistributorV3} from "../interfaces/IDegenDistributorV3.sol";

interface IDegenNFT {
    function mint(address to, uint256 amount) external;
    function burn(address from, uint256 amount) external;
}

contract DegenDistributorV3 is IDegenDistributorV3 {
    uint256 public constant version = 3_00;

    /// @dev Emits each time when call not by treasury
    error TreasuryOnlyException();

    /// @dev Returns the token distributed by the contract
    address public immutable override degenNFT;

    /// @dev DAO Treasury address
    address public immutable treasury;

    /// @dev The current merkle root of total claimable balances
    bytes32 public override merkleRoot;

    /// @dev The mapping that stores amounts already claimed by users
    mapping(address => uint256) public claimed;

    modifier treasuryOnly() {
        if (msg.sender != treasury) revert TreasuryOnlyException();
        _;
    }

    constructor(address degenNFT_, address treasury_) {
        degenNFT = degenNFT_;
        treasury = treasury_;
    }

    function updateMerkleRoot(bytes32 newRoot) external treasuryOnly {
        bytes32 oldRoot = merkleRoot;
        merkleRoot = newRoot;
        emit RootUpdated(oldRoot, newRoot);
    }

    function claim(uint256 index, address account, uint256 totalAmount, bytes32[] calldata merkleProof)
        external
        override
    {
        require(claimed[account] < totalAmount, "MerkleDistributor: Nothing to claim");

        bytes32 node = keccak256(abi.encodePacked(index, account, totalAmount));
        require(MerkleProof.verify(merkleProof, merkleRoot, node), "MerkleDistributor: Invalid proof.");

        uint256 claimedAmount = totalAmount - claimed[account];
        claimed[account] += claimedAmount;
        IDegenNFT(degenNFT).mint(account, claimedAmount);

        emit Claimed(account, claimedAmount);
    }
}
