// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {BlueprintV3} from "../src/BlueprintV3.sol";
import {Blueprint} from "../src/history/BlueprintV3.sol";
import {stdError} from "forge-std/StdError.sol";

contract BlueprintTest is Test {
    BlueprintV3 public blueprint;
    bytes32 public projectId;
    address public solverAddress;
    address public workerAddress;
    address public dummyAddress;

    function setUp() public {
        blueprint = new BlueprintV3();
        blueprint.initialize(); // mimic upgradeable contract deploy behavior
        projectId = bytes32(0x2723a34e38d0f0aa09ce626f00aa23c0464b52c75516cf3203cc4c9afeaf2980);
        solverAddress = address(0x275960ad41DbE218bBf72cDF612F88b5C6f40648);
        workerAddress = address(0x4d6585D89F889F29f77fd7Dd71864269BA1B31df);
        dummyAddress = address(0);
    }

    function test_VERSION() public view {
        string memory ver = blueprint.VERSION();
        assertEq(ver, "3.0.0");
    }

    function test_setWorkerPublicKey() public {
        bytes memory publicKey = hex"123456";
        blueprint.setWorkerPublicKey(publicKey);

        bytes memory storedPublicKey = blueprint.getWorkerPublicKey(address(this));
        assertEq(storedPublicKey, publicKey);
    }

    function test_getWorkerAddresses() public {
        // Case 1: One worker
        bytes memory publicKey1 = hex"123456";
        blueprint.setWorkerPublicKey(publicKey1);

        address[] memory workerAddresses = blueprint.getWorkerAddresses();
        assertEq(workerAddresses.length, 1);
        assertEq(workerAddresses[0], address(this));

        // Case 2: Two workers
        bytes memory publicKey2 = hex"abcdef";
        vm.prank(dummyAddress);
        blueprint.setWorkerPublicKey(publicKey2);

        workerAddresses = blueprint.getWorkerAddresses();
        assertEq(workerAddresses.length, 2);
        assertEq(workerAddresses[0], address(this));
        assertEq(workerAddresses[1], dummyAddress);
    }

    function test_createProjectIdAndPrivateDeploymentWithConfig() public {
        // Define the configuration parameters
        string memory base64Proposal = "test base64 proposal";
        address privateWorkerAddress = workerAddress;
        string memory serverURL = "http://example.com";

        // Expect the UpdateDeploymentConfig event to be emitted
        vm.expectEmit(true, true, true, true);
        emit Blueprint.UpdateDeploymentConfig(
            projectId,
            keccak256(
                abi.encodePacked(
                    uint256(block.timestamp),
                    address(this),
                    base64Proposal,
                    uint256(block.chainid),
                    projectId,
                    uint256(0)
                )
            ),
            privateWorkerAddress,
            "Encrypted config for deployment"
        );

        // Call the function with the configuration parameters
        bytes32 requestID = blueprint.createProjectIdAndPrivateDeploymentWithConfig(
            projectId, base64Proposal, privateWorkerAddress, serverURL
        );

        // Verify that the returned request ID is not zero
        assert(requestID != bytes32(0));

        // Verify that the deployment status is updated correctly
        (Blueprint.Status status, address workerAddr) = blueprint.getDeploymentStatus(requestID);
        assertTrue(status == Blueprint.Status.Pickup);
        assertEq(workerAddr, privateWorkerAddress);
    }

    function test_createProjectIDAndProposalRequestWithSig() public {
        // Define the configuration parameters
        string memory base64RecParam = "data";
        string memory serverURL = "https://example.com";

        // Generate the hash of the request proposal
        bytes32 digest = blueprint.getRequestProposalDigest(projectId, base64RecParam, serverURL);

        // Generate the signature using the private key of the sender
        uint256 ownerPrivateKey = 0xA11CE;
        address owner = vm.addr(ownerPrivateKey);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Expect the RequestProposal event to be emitted
        vm.expectEmit(true, true, true, true);
        emit Blueprint.RequestProposal(
            projectId,
            owner,
            keccak256(abi.encodePacked(block.timestamp, owner, base64RecParam, block.chainid)),
            base64RecParam,
            serverURL
        );

        // Call the function with the configuration parameters
        bytes32 requestID =
            blueprint.createProjectIDAndProposalRequestWithSig(projectId, base64RecParam, serverURL, signature);

        // Verify that the returned request ID is not zero
        assert(requestID != bytes32(0));

        // Verify that the proposal request ID is stored correctly
        bytes32 storedRequestID = blueprint.getLatestProposalRequestID(owner);
        assertEq(storedRequestID, requestID);

        // verify project id is stored correctly
        bytes32 storedProjectID = blueprint.getLatestUserProjectID(owner);
        assertEq(storedProjectID, projectId);
    }

    function test_createPrivateDeploymentRequestWithSig() public {
        string memory base64Proposal = "data:image/png;base64,sdfasdfsdf";
        string memory serverURL = "https://example.com";
        bytes32 projId = blueprint.createProjectID();
        bytes32 digest = blueprint.getRequestDeploymentDigest(projId, base64Proposal, serverURL);

        uint256 signerPrivateKey = 0xA11CE;
        address signerAddress = vm.addr(signerPrivateKey);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        bytes32 requestID = blueprint.createPrivateDeploymentRequestWithSig(
            projId, solverAddress, workerAddress, base64Proposal, serverURL, signature
        );

        assert(requestID != bytes32(0));

        bytes32 storedRequestID = blueprint.getLatestDeploymentRequestID(signerAddress);
        assertEq(storedRequestID, requestID);
    }

    function test_createDeploymentRequestWithSig() public {
        string memory base64Proposal = "data:image/png;base64,sdfasdfsdf";
        string memory serverURL = "https://example.com";
        bytes32 projId = blueprint.createProjectID();
        bytes32 digest = blueprint.getRequestDeploymentDigest(projId, base64Proposal, serverURL);

        uint256 signerPrivateKey = 0xA11CE;
        address signerAddress = vm.addr(signerPrivateKey);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        bytes32 requestID =
            blueprint.createDeploymentRequestWithSig(projId, solverAddress, base64Proposal, serverURL, signature);

        assert(requestID != bytes32(0));

        bytes32 storedRequestID = blueprint.getLatestDeploymentRequestID(signerAddress);
        assertEq(storedRequestID, requestID);
    }

    function test_createProposalRequestWithSig() public {
        string memory base64RecParam = "data:image/png;base64,sdfasdfsdf";
        string memory serverURL = "https://example.com";

        bytes32 projId = blueprint.createProjectID();
        bytes32 digest = blueprint.getRequestProposalDigest(projId, base64RecParam, serverURL);

        uint256 signerPrivateKey = 0xA11CE;
        address signerAddress = vm.addr(signerPrivateKey);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        bytes32 requestID = blueprint.createProposalRequestWithSig(projId, base64RecParam, serverURL, signature);

        assert(requestID != bytes32(0));

        bytes32 storedRequestID = blueprint.getLatestProposalRequestID(signerAddress);
        assertEq(storedRequestID, requestID);
    }

    function test_createProjectIDAndDeploymentRequestWithSig() public {
        string memory base64Proposal = "data:image/png;base64,sdfasdfsdf";
        string memory serverURL = "https://example.com";

        // Generate the hash of the deployment request
        bytes32 digest = blueprint.getRequestDeploymentDigest(projectId, base64Proposal, serverURL);

        // Generate the signature using the private key of the signer
        uint256 signerPrivateKey = 0xA11CE;
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);
        address signerAddress = vm.addr(signerPrivateKey);

        // Create the project ID and deployment request with signature
        bytes32 requestID =
            blueprint.createProjectIDAndDeploymentRequestWithSig(projectId, base64Proposal, serverURL, signature);

        // Verify that the request ID is not empty
        assert(requestID != bytes32(0));

        // Verify that the deployment status is updated correctly
        (Blueprint.Status status, address workerAddr) = blueprint.getDeploymentStatus(requestID);
        assertTrue(status == Blueprint.Status.Issued);
        assertEq(workerAddr, address(0));

        // Verify that the request ID is stored correctly
        bytes32 storedRequestID = blueprint.getLatestDeploymentRequestID(signerAddress);
        assertEq(storedRequestID, requestID);

        // verify project id is stored correctly
        bytes32 storedProjectID = blueprint.getLatestUserProjectID(signerAddress);
        assertEq(storedProjectID, projectId);
    }

    function test_createProjectIDAndPrivateDeploymentRequestWithSig() public {
        // Define the configuration parameters
        string memory base64Proposal = "test base64 proposal";
        string memory serverURL = "http://example.com";

        // Generate the hash of the deployment request
        bytes32 digest = blueprint.getRequestDeploymentDigest(projectId, base64Proposal, serverURL);

        // Generate the signature using the private key of the signer
        uint256 signerPrivateKey = 0xA11CE;
        address signerAddress = vm.addr(signerPrivateKey);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Call the function with the configuration parameters
        bytes32 requestID = blueprint.createProjectIDAndPrivateDeploymentRequestWithSig(
            projectId, base64Proposal, workerAddress, serverURL, signature
        );

        // Verify that the returned request ID is not zero
        assert(requestID != bytes32(0));

        // Verify that the deployment status is updated correctly
        (Blueprint.Status status, address workerAddr) = blueprint.getDeploymentStatus(requestID);
        assertTrue(status == Blueprint.Status.Pickup);
        assertEq(workerAddr, workerAddress);

        // Verify that the request ID is stored correctly
        bytes32 storedRequestID = blueprint.getLatestDeploymentRequestID(signerAddress);
        assertEq(storedRequestID, requestID);

        // verify project id is stored correctly
        bytes32 storedProjectID = blueprint.getLatestUserProjectID(signerAddress);
        assertEq(storedProjectID, projectId);
    }

    function test_createDeploymentRequest() public {
        bytes32 projId = blueprint.createProjectID();
        // fix v2 bug that user with different project id trigger blueprint within one block time can get same request id
        bytes32 requestId = keccak256(
            abi.encodePacked(
                uint256(block.timestamp), address(this), "test base64 param", uint256(block.chainid), projId, uint256(0)
            )
        );

        bytes32 deploymentRequestId =
            blueprint.createDeploymentRequest(projId, solverAddress, "test base64 param", "test server url");

        assertEq(deploymentRequestId, requestId);

        bytes32 latestDeploymentRequestId = blueprint.getLatestDeploymentRequestID(address(this));

        assertEq(deploymentRequestId, latestDeploymentRequestId);

        (address deployedSolverAddr,, bytes32[] memory deploymentIdList) = blueprint.getProjectInfo(projId);

        assertEq(solverAddress, deployedSolverAddr);

        assertEq(deploymentRequestId, deploymentIdList[0]);
    }
}
