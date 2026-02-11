// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Test } from "forge-std/Test.sol";

import { Permit3 } from "../src/Permit3.sol";
import { IPermit3 } from "../src/interfaces/IPermit3.sol";
import { MockToken, Permit3TestUtils } from "./utils/TestUtils.sol";

/**
 * @title TestUtilsTest
 * @notice Tests to achieve full coverage of the TestUtils helper library
 */
contract TestUtilsTest is Test {
    Permit3 permit3;
    MockToken token;
    address owner;
    address spender;
    address recipient;
    uint256 ownerPrivateKey;

    function setUp() public {
        permit3 = new Permit3();
        token = new MockToken();

        // Set up test accounts
        ownerPrivateKey = 0x1234;
        owner = vm.addr(ownerPrivateKey);
        spender = address(0x2);
        recipient = address(0x3);

        // Fund the owner
        deal(address(token), owner, 10_000);
        vm.prank(owner);
        token.approve(address(permit3), type(uint256).max);
    }

    function test_mockToken() public view {
        // Test the MockToken implementation
        assertEq(token.name(), "Mock");
        assertEq(token.symbol(), "MOCK");
        assertEq(token.balanceOf(address(this)), 1_000_000 * 10 ** 18);
    }

    function test_domainSeparator() public view {
        // Test the domainSeparator function
        bytes32 separator = Permit3TestUtils.domainSeparator(permit3);
        assertEq(separator, permit3.DOMAIN_SEPARATOR());
    }

    function test_hashTypedDataV4() public view {
        // Test the hashTypedDataV4 function
        bytes32 structHash = keccak256("test data");
        bytes32 domainSeparator = permit3.DOMAIN_SEPARATOR();

        bytes32 manualHash = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        bytes32 utilHash = Permit3TestUtils.hashTypedDataV4(permit3, structHash);

        assertEq(utilHash, manualHash);
    }

    function test_signDigest() public view {
        // Test the signDigest function
        bytes32 digest = keccak256("test digest");

        // Sign manually
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);
        bytes memory manualSignature = abi.encodePacked(r, s, v);

        // Sign with utility
        bytes memory utilSignature = Permit3TestUtils.signDigest(vm, digest, ownerPrivateKey);

        // Compare signatures
        assertEq(utilSignature.length, manualSignature.length);

        for (uint256 i = 0; i < utilSignature.length; i++) {
            assertEq(utilSignature[i], manualSignature[i]);
        }
    }

    function test_hashChainPermits() public view {
        // Create test permits
        IPermit3.AllowanceOrTransfer[] memory permits = new IPermit3.AllowanceOrTransfer[](2);
        permits[0] = IPermit3.AllowanceOrTransfer({
            modeOrExpiration: 0, // Transfer
            token: address(token),
            account: recipient,
            amountDelta: 1000
        });

        permits[1] = IPermit3.AllowanceOrTransfer({
            modeOrExpiration: 1, // Decrease
            token: address(0xABC),
            account: spender,
            amountDelta: 500
        });

        IPermit3.ChainPermits memory chainPermits =
            IPermit3.ChainPermits({ chainId: uint64(block.chainid), permits: permits });

        // Hash using utility
        bytes32 hash = Permit3TestUtils.hashChainPermits(permit3, chainPermits);

        // Verify the hash
        bytes32[] memory permitHashes = new bytes32[](permits.length);

        for (uint256 i = 0; i < permits.length; i++) {
            permitHashes[i] = keccak256(
                abi.encode(permits[i].modeOrExpiration, permits[i].token, permits[i].account, permits[i].amountDelta)
            );
        }

        bytes32 expectedHash = keccak256(
            abi.encode(
                permit3.CHAIN_PERMITS_TYPEHASH(), chainPermits.chainId, keccak256(abi.encodePacked(permitHashes))
            )
        );

        assertEq(hash, expectedHash);
    }

    function test_hashEmptyChainPermits() public view {
        // Test hashEmptyChainPermits function
        uint64 chainId = uint64(block.chainid);
        bytes32 emptyHash = Permit3TestUtils.hashEmptyChainPermits(permit3, chainId);

        // Create empty permits manually
        IPermit3.AllowanceOrTransfer[] memory emptyPermits = new IPermit3.AllowanceOrTransfer[](0);
        IPermit3.ChainPermits memory chainPermits = IPermit3.ChainPermits({ chainId: chainId, permits: emptyPermits });

        bytes32 manualHash = Permit3TestUtils.hashChainPermits(permit3, chainPermits);

        assertEq(emptyHash, manualHash);
    }

    function test_createTransferPermit() public view {
        // Test createTransferPermit function
        address testToken = address(0xABC);
        address testRecipient = address(0xDEF);
        uint160 testAmount = 1234;

        IPermit3.ChainPermits memory transferPermit =
            Permit3TestUtils.createTransferPermit(testToken, testRecipient, testAmount);

        // Verify the permit structure
        assertEq(transferPermit.chainId, uint64(block.chainid));
        assertEq(transferPermit.permits.length, 1);
        assertEq(transferPermit.permits[0].modeOrExpiration, 0); // Transfer mode
        assertEq(transferPermit.permits[0].token, testToken);
        assertEq(transferPermit.permits[0].account, testRecipient);
        assertEq(transferPermit.permits[0].amountDelta, testAmount);
    }

    function test_verifyBalancedSubtree() public pure {
        // Test verifyBalancedSubtree function
        bytes32 leaf = bytes32(uint256(100));
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = bytes32(uint256(200));

        // Calculate result using the utility
        bytes32 result = Permit3TestUtils.verifyBalancedSubtree(leaf, proof);

        // Calculate expected result manually
        bytes32 expected = keccak256(abi.encodePacked(leaf, proof[0]));

        assertEq(result, expected);

        // Test with leaf > proof element
        bytes32 largerLeaf = bytes32(uint256(300));
        bytes32 resultReverse = Permit3TestUtils.verifyBalancedSubtree(largerLeaf, proof);
        bytes32 expectedReverse = keccak256(abi.encodePacked(proof[0], largerLeaf));

        assertEq(resultReverse, expectedReverse);
    }
}
