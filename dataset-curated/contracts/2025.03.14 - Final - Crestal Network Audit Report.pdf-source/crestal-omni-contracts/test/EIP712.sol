// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {BlueprintV3} from "../src/BlueprintV3.sol";
import {stdError} from "forge-std/StdError.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";

contract EIP712Test is Test, EIP712Upgradeable {
    BlueprintV3 public eip712;
    bytes32 public domainSeparator;
    uint256 public signerPrivateKey;
    address public signerAddress;
    bytes32 public projectId;

    function setUp() public {
        eip712 = new BlueprintV3();
        eip712.initialize(); // mimic upgradeable contract deploy behavior
        projectId = bytes32(0x2723a34e38d0f0aa09ce626f00aa23c0464b52c75516cf3203cc4c9afeaf2980);
        signerPrivateKey = 0xA11CE;
        signerAddress = vm.addr(signerPrivateKey);

        domainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes(eip712.SIGNING_DOMAIN())),
                keccak256(bytes(eip712.VERSION())),
                block.chainid,
                address(eip712)
            )
        );
    }

    function testGetRequestProposalHashDigest(bytes32 projId, string memory base64RecParam, string memory serverURL)
        public
        view
        returns (bytes32)
    {
        bytes32 structHash = keccak256(
            abi.encode(
                eip712.PROPOSAL_REQUEST_TYPEHASH(),
                projId,
                keccak256(bytes(base64RecParam)),
                keccak256(bytes(serverURL))
            )
        );

        // Hash the data with the domain separator
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        return digest;
    }

    function test_getRequestProposalDigest() public view {
        // check address
        assertEq(eip712.getAddress(), address(eip712));

        string memory base64RecParam = "data:image/png;base64,sdfasdfsdf";
        string memory serverURL = "https://example.com";

        // Generate the hash of the request proposal
        bytes32 digest1 = eip712.getRequestProposalDigest(projectId, base64RecParam, serverURL);
        // generate hash using test function
        bytes32 digest2 = testGetRequestProposalHashDigest(projectId, base64RecParam, serverURL);
        assertEq(digest1, digest2);
    }

    function test_getSignerAddress() public {
        // Generate the hash of the request proposal
        bytes32 digest = eip712.getRequestProposalDigest(projectId, "", "");

        // Generate the signature using the private key of the signer
        signerPrivateKey = 0xA11CE;
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Recover the signer's address from the hash and signature
        address recoveredSigner = eip712.getSignerAddress(digest, signature);

        // Verify that the recovered address matches the expected signer's address
        assertEq(recoveredSigner, vm.addr(signerPrivateKey));
    }

    function test_invalidSignature() public {
        bytes32 digest = eip712.getRequestProposalDigest(projectId, "", "");

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Modify the signature to make it invalid
        signature[0] = bytes1(uint8(signature[0]) + 1);

        // Expect the next call to revert with ECDSAInvalidSignature
        vm.expectRevert();
        address recoveredSigner = eip712.getSignerAddress(digest, signature);
        assertEq(recoveredSigner, address(0));
    }
}
