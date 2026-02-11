// Copyright (c) 2025 Merge Layers Inc.
//
// This source code is licensed under the Business Source License 1.1
// (the "License"); you may not use this file except in compliance with the
// License. You may obtain a copy of the License at
//
//     https://github.com/malda-protocol/malda-lending/blob/main/LICENSE-BSL
//
// See the License for the specific language governing permissions and
// limitations under the License.

// SPDX-License-Identifier: BSL-1.1
pragma solidity =0.8.28;

/*
 _____ _____ __    ____  _____ 
|     |  _  |  |  |    \|  _  |
| | | |     |  |__|  |  |     |
|_|_|_|__|__|_____|____/|__|__|   
*/

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {ERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

contract MaldaNft is ERC721Enumerable, Ownable {
    bytes32 public merkleRoot;
    mapping(address => mapping(uint256 => bool)) public hasClaimed;
    mapping(uint256 => bool) public minted;

    uint256 private _nextTokenId;
    string private _baseTokenURI;

    event MerkleRootSet(bytes32 merkleRoot);
    event TokensClaimed(address indexed claimer, uint256 indexed tokenIdClaimed);

    error MaldaNft_MerkleRootNotSet();
    error MaldaNft_InvalidMerkleProof();
    error MaldaNft_TokenAlreadyMinted();
    error MaldaNft_TokenAlreadyClaimed();
    error MaldaNft_TokenNotTransferable();


    constructor(string memory name, string memory symbol, string memory baseURI, address owner) ERC721(name, symbol) Ownable(owner) {
        _baseTokenURI = baseURI;
    }

    // ----------- OWNER ------------
    function mint(address to, uint256 tokenId) external onlyOwner {
        require(!minted[tokenId], MaldaNft_TokenAlreadyMinted());
        _safeMint(to, tokenId);
        hasClaimed[to][tokenId] = true;
    }

    function setBaseURI(string memory baseURI) external onlyOwner {
        _baseTokenURI = baseURI;
    }

    function setMerkleRoot(bytes32 _merkleRoot) external onlyOwner {
        merkleRoot = _merkleRoot;
        emit MerkleRootSet(_merkleRoot);
    }


    // ----------- PUBLIC ------------
    function canClaim(
        address claimer,
        uint256 tokenId,
        bytes32[] calldata merkleProof
    )
        external
        view
        returns (bool)
    {
        require(merkleRoot != bytes32(0), MaldaNft_MerkleRootNotSet());
        if (hasClaimed[claimer][tokenId]) return false;
        if (minted[tokenId]) return false;

        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(claimer, tokenId))));

        return MerkleProof.verify(merkleProof, merkleRoot, leaf);
    }

    function claim(uint256 tokenId, bytes32[] calldata merkleProof) external {
        require(merkleRoot != bytes32(0), MaldaNft_MerkleRootNotSet());
        require(!hasClaimed[msg.sender][tokenId], MaldaNft_TokenAlreadyClaimed());
        require(!minted[tokenId], MaldaNft_TokenAlreadyMinted());

        bytes32 leaf = keccak256(bytes.concat(keccak256(abi.encode(msg.sender, tokenId))));
        require(MerkleProof.verify(merkleProof, merkleRoot, leaf), MaldaNft_InvalidMerkleProof());
        hasClaimed[msg.sender][tokenId] = true;
        minted[tokenId] = true;
        _safeMint(msg.sender, tokenId);
        emit TokensClaimed(msg.sender, tokenId);
    }

     /// @dev non-transferable
    function transferFrom(address, address, uint256) public override(ERC721,IERC721) {
        revert MaldaNft_TokenNotTransferable();
    }

    /// @dev non-transferable
    function safeTransferFrom(address, address, uint256, bytes memory)
        public
        override(ERC721,IERC721)
    {
        revert MaldaNft_TokenNotTransferable();
    }

    // ----------- PRIVATE ------------
    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }
}