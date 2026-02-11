// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {BlueprintV2} from "../src/BlueprintV2.sol";
import {Blueprint} from "../src/history/BlueprintV2.sol";
import {stdError} from "forge-std/StdError.sol";

contract BlueprintTest is Test {
    BlueprintV2 public blueprint;
    bytes32 public projectId;
    address public solverAddress;
    address public workerAddress;
    address public dummyAddress;

    function setUp() public {
        blueprint = new BlueprintV2();
        blueprint.initialize(); // mimic upgradeable contract deploy behavior
        projectId = bytes32(0x2723a34e38d0f0aa09ce626f00aa23c0464b52c75516cf3203cc4c9afeaf2980);
        solverAddress = address(0x275960ad41DbE218bBf72cDF612F88b5C6f40648);
        workerAddress = address(0x4d6585D89F889F29f77fd7Dd71864269BA1B31df);
        dummyAddress = address(0);
    }

    function test_ProjectID() public {
        bytes32 pid = blueprint.createProjectID();
        bytes32 projId = blueprint.getLatestUserProjectID(address(this));
        assertEq(pid, projId);
    }

    function test_VERSION() public view {
        string memory ver = blueprint.VERSION();
        assertEq(ver, "2.0.0");
    }

    function test_createProposalRequest() public {
        bytes32 projId = blueprint.createProjectID();
        bytes32 proposalId = blueprint.createProposalRequest(projId, "test base64 param", "test server url");
        bytes32 latestProposalId = blueprint.getLatestProposalRequestID(address(this));
        assertEq(proposalId, latestProposalId);
    }

    function test_Revert_invalid_projectId_createProposalRequest() public {
        // Expect the transaction to revert with the correct error message
        vm.expectRevert("projectId does not exist");

        blueprint.createProposalRequest("invalid project id", "test base64 param", "test server url");
    }

    function test_createProjectIDAndProposalRequest() public {
        bytes32 proposalId =
            blueprint.createProjectIDAndProposalRequest(projectId, "test base64 param", "test server url");
        bytes32 latestProposalId = blueprint.getLatestProposalRequestID(address(this));
        bytes32 latestProjId = blueprint.getLatestUserProjectID(address(this));

        assertEq(proposalId, latestProposalId);
        assertEq(projectId, latestProjId);
    }

    function test_Revert_duplicate_projectId_createProjectIDAndProposalRequest() public {
        bytes32 projId = blueprint.createProjectID();
        // use duplicate project id , then cause creation fail error
        vm.expectRevert("projectId already exists");
        blueprint.createProjectIDAndProposalRequest(projId, "test base64 param", "test server url");
    }

    function test_Revert_request_twice_createProjectIDAndProposalRequest() public {
        // first create success, while second fail
        blueprint.createProjectIDAndProposalRequest(projectId, "test base64 param", "test server url");
        vm.expectRevert("projectId already exists");

        blueprint.createProjectIDAndProposalRequest(projectId, "test base64 param", "test server url");
    }

    function test_createDeploymentRequest() public {
        bytes32 projId = blueprint.createProjectID();

        bytes32 deploymentRequestId =
            blueprint.createDeploymentRequest(projId, solverAddress, "test base64 param", "test server url");

        bytes32 requestId = keccak256(
            abi.encodePacked(
                uint256(block.timestamp), address(this), "test base64 param", uint256(block.chainid), uint256(0)
            )
        );

        bytes32 latestDeploymentRequestId = blueprint.getLatestDeploymentRequestID(address(this));
        assertEq(deploymentRequestId, latestDeploymentRequestId);

        assertEq(requestId, latestDeploymentRequestId);

        (address deployedSolverAddr,, bytes32[] memory deploymentIdList) = blueprint.getProjectInfo(projId);

        assertEq(solverAddress, deployedSolverAddr);

        assertEq(deploymentRequestId, deploymentIdList[0]);
    }

    function test_createProjectIDAndDeploymentRequest() public {
        bytes32 deploymentRequestId =
            blueprint.createProjectIDAndDeploymentRequest(projectId, "test base64 param", "test server url");
        bytes32 latestDeploymentRequestId = blueprint.getLatestDeploymentRequestID(address(this));
        bytes32 latestProjId = blueprint.getLatestUserProjectID(address(this));

        assertEq(deploymentRequestId, latestDeploymentRequestId);

        assertEq(projectId, latestProjId);

        (address deployedSolverAddr,, bytes32[] memory deploymentIdList) = blueprint.getProjectInfo(projectId);
        // skip solver
        assertEq(dummyAddress, deployedSolverAddr);

        assertEq(deploymentRequestId, deploymentIdList[0]);
    }

    function test_createPrivateDeploymentRequest() public {
        bytes32 projId = blueprint.createProjectID();
        bytes32 deploymentRequestId = blueprint.createPrivateDeploymentRequest(
            projId, solverAddress, workerAddress, "test base64 param", "test server url"
        );
        bytes32 latestDeploymentRequestId = blueprint.getLatestDeploymentRequestID(address(this));

        assertEq(deploymentRequestId, latestDeploymentRequestId);

        (Blueprint.Status status, address pickUpWorkerAddr) = blueprint.getDeploymentStatus(latestDeploymentRequestId);

        assertEq(workerAddress, pickUpWorkerAddr);

        assertTrue(status == Blueprint.Status.Pickup);

        (address deployedSolverAddr,, bytes32[] memory deploymentIdList) = blueprint.getProjectInfo(projId);

        assertEq(solverAddress, deployedSolverAddr);

        assertEq(deploymentRequestId, deploymentIdList[0]);
    }

    function test_createProjectIDAndPrivateDeploymentRequest() public {
        bytes32 deploymentRequestId = blueprint.createProjectIDAndPrivateDeploymentRequest(
            projectId, "test base64 param", workerAddress, "test server url"
        );
        bytes32 latestDeploymentRequestId = blueprint.getLatestDeploymentRequestID(address(this));
        bytes32 latestProjId = blueprint.getLatestUserProjectID(address(this));

        assertEq(projectId, latestProjId);
        assertEq(deploymentRequestId, latestDeploymentRequestId);

        (Blueprint.Status status, address pickUpWorkerAddr) = blueprint.getDeploymentStatus(latestDeploymentRequestId);

        assertEq(workerAddress, pickUpWorkerAddr);

        assertTrue(status == Blueprint.Status.Pickup);

        (,, bytes32[] memory deploymentIdList) = blueprint.getProjectInfo(projectId);

        assertEq(deploymentRequestId, deploymentIdList[0]);
    }

    function test_submitDeploymentRequest() public {
        bytes32 deploymentRequestId =
            blueprint.createProjectIDAndDeploymentRequest(projectId, "test base64 param", "test server url");

        // worker submit request
        bool isAccept = blueprint.submitDeploymentRequest(projectId, deploymentRequestId);

        assertEq(isAccept, true);

        (Blueprint.Status status, address pickUpWorkerAddr) = blueprint.getDeploymentStatus(deploymentRequestId);

        assertEq(address(this), pickUpWorkerAddr);

        assertTrue(status == Blueprint.Status.Pickup);
    }

    function test_submitProofOfDeployment() public {
        bytes32 deploymentRequestId =
            blueprint.createProjectIDAndDeploymentRequest(projectId, "test base64 param", "test server url");

        // worker submit request
        bool isAccept = blueprint.submitDeploymentRequest(projectId, deploymentRequestId);

        assertEq(isAccept, true);

        // submit proof
        string memory proof = "deployment proof";
        blueprint.submitProofOfDeployment(projectId, deploymentRequestId, proof);

        (Blueprint.Status status, address pickUpWorkerAddr) = blueprint.getDeploymentStatus(deploymentRequestId);

        assertEq(address(this), pickUpWorkerAddr);

        assertTrue(status == Blueprint.Status.GeneratedProof);

        // check proof
        string memory deploymentProof = blueprint.getDeploymentProof(deploymentRequestId);

        assertEq(proof, deploymentProof);
    }
}
