// SPDX-License-Identifier: BSL-1.1
pragma solidity =0.8.28;

import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {Strings} from "openzeppelin-contracts/contracts/utils/Strings.sol";
import "forge-std/console.sol";
import "forge-std/Test.sol";
import {MaldaNft} from "src/nft/MaldaNft.sol";

contract MaldaNftTest is Test {
    MaldaNft private maldaNft;
    address private owner;
    address[10] private users;
    uint256[10] private tokenIds = [1, 10, 11, 15, 16, 22, 32, 50, 100, 200];

    bytes32[] public merkleProof1;
    bytes32[] public merkleProof2;
    bytes32 public merkleRoot;

    function setUp() public {
        owner = address(this);
        maldaNft = new MaldaNft("MaldaNFT", "MLDNFT", "https://baseuri.com/", address(this));
        maldaNft.transferOwnership(owner);
        
        users[0] = address(0x1);
        users[1] = address(0x2);
        users[2] = address(0x3);
        users[3] = address(0x4);
        users[4] = address(0x5);
        users[5] = address(0x6);
        users[6] = address(0x7);
        users[7] = address(0x8);
        users[8] = address(0x9);
        users[9] = address(0x10);

        (merkleRoot, merkleProof1) = _generateMerkleTree(users[0]);
        (, merkleProof2) = _generateMerkleTree(users[1]);

        maldaNft.setMerkleRoot(merkleRoot);
    }


    function testMintByOwner() public {
        address to = users[0];
        uint256 tokenId = tokenIds[0];
        maldaNft.mint(to, tokenId);
        assertEq(maldaNft.ownerOf(tokenId), to);
    }

    function test_ClaimToken() public {
        vm.prank(users[0]);
        maldaNft.claim(tokenIds[0], merkleProof1);
        assertEq(maldaNft.ownerOf(tokenIds[0]), users[0]);

        uint256 supply = maldaNft.totalSupply();
        assertEq(supply, 1);

        assertEq(maldaNft.tokenByIndex(0), tokenIds[0]);
    }

    function test_CannotClaim() public {
        vm.startPrank(users[0]);
        vm.expectRevert(MaldaNft.MaldaNft_InvalidMerkleProof.selector);
        maldaNft.claim(tokenIds[1], merkleProof1);
        vm.stopPrank();
    }

    function test_CannotClaimTwice() public {
        vm.prank(users[0]);
        maldaNft.claim(tokenIds[0], merkleProof1);
        assertEq(maldaNft.ownerOf(tokenIds[0]), users[0]);

        uint256 supply = maldaNft.totalSupply();
        assertEq(supply, 1);

        vm.startPrank(users[0]);
        vm.expectRevert(MaldaNft.MaldaNft_TokenAlreadyClaimed.selector);
        maldaNft.claim(tokenIds[0], merkleProof1);
        vm.stopPrank();
    }

    function test_CannotMintClaimedToken() public {
        vm.prank(users[0]);
        maldaNft.claim(tokenIds[0], merkleProof1);
        assertEq(maldaNft.ownerOf(tokenIds[0]), users[0]);

        uint256 supply = maldaNft.totalSupply();
        assertEq(supply, 1);
        
        vm.expectRevert(MaldaNft.MaldaNft_TokenAlreadyMinted.selector);
        maldaNft.mint(address(this), tokenIds[0]);
    }

    function test_CannotTransfer() public {
        vm.prank(users[0]);
        maldaNft.claim(tokenIds[0], merkleProof1);
        assertEq(maldaNft.ownerOf(tokenIds[0]), users[0]);

        uint256 supply = maldaNft.totalSupply();
        assertEq(supply, 1);

        vm.startPrank(users[0]);
        vm.expectRevert(MaldaNft.MaldaNft_TokenNotTransferable.selector);
        maldaNft.transferFrom(users[0], address(this), tokenIds[0]);
        vm.stopPrank();
    }


     /// @dev read the merkle root and proof from js generated tree
    function _generateMerkleTree(address _user)
        internal
        view
        returns (bytes32 root, bytes32[] memory proofsAt)
    {
        root = _parseRoot();

        string memory tree = vm.readFile(string.concat(vm.projectRoot(), "/test/unit/nft/merkle/result/tree.json"));
        for (uint256 i; i < 10; ++i) {
            bytes memory treeUser = vm.parseJson(tree, string.concat(".values[", Strings.toString(i), "].user"));
            address parsedUser = abi.decode(treeUser, (address));
            if (parsedUser == _user) {
                bytes memory encodedProof = vm.parseJson(tree, string.concat(".values[", Strings.toString(i), "].proof"));
                proofsAt = abi.decode(encodedProof, (bytes32[]));

                break;
            }
        }
    }

    function _parseRoot() private view returns (bytes32 root) {
        string memory rootJson = vm.readFile(string.concat(vm.projectRoot(), "/test/unit/nft/merkle/result/root.json"));
        bytes memory encodedRoot = vm.parseJson(rootJson, ".root");
        root = abi.decode(encodedRoot, (bytes32));
    }


}