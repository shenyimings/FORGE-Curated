// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {BlueprintV1} from "../src/BlueprintV1.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {BlueprintV2} from "../src/BlueprintV2.sol";
import {BlueprintV3} from "../src/BlueprintV3.sol";
import {BlueprintV4} from "../src/BlueprintV4.sol";
import {BlueprintV5} from "../src/BlueprintV5.sol";

contract BlueprintTestUpgrade is Test {
    BlueprintV1 public proxy;
    address public solverAddress;
    bytes32 public projIdV4;
    bytes32 public projIdV5;
    address public constant NFT_CONTRACT_ADDRESS = address(0x7D8be0Dd8915E3511fFDDABDD631812be824f578);

    function setUp() public {
        BlueprintV1 blueprint = new BlueprintV1();

        // Create a proxy pointing to the implementation
        ERC1967Proxy e1967 = new ERC1967Proxy(address(blueprint), abi.encodeWithSignature("initialize()"));

        // Interact with the proxy as if it were the implementation
        proxy = BlueprintV1(address(e1967));

        // init solver address
        solverAddress = address(0x275960ad41DbE218bBf72cDF612F88b5C6f40648);
    }

    function test_UpgradeV2() public {
        string memory ver = proxy.VERSION();
        assertEq(ver, "1.0.0");

        bytes32 pid = proxy.createProjectID();
        bytes32 projId = proxy.getLatestUserProjectID(address(this));
        assertEq(pid, projId);

        bytes32 deploymentRequestId =
            proxy.createDeploymentRequest(projId, solverAddress, "test base64 param", "test server url");
        bytes32 latestDeploymentRequestId = proxy.getLatestDeploymentRequestID(address(this));
        assertEq(deploymentRequestId, latestDeploymentRequestId);

        BlueprintV2 blueprintV2 = new BlueprintV2();
        proxy.upgradeToAndCall(address(blueprintV2), abi.encodeWithSignature("initialize()"));
        ver = proxy.VERSION();
        assertEq(ver, "2.0.0");

        // create proposal request with old project id from v1
        bytes32 proposalId = proxy.createProposalRequest(projId, "test base64 param", "test server url");
        bytes32 latestProposalId = proxy.getLatestProposalRequestID(address(this));
        assertEq(proposalId, latestProposalId);

        // get old project id
        projId = proxy.getLatestUserProjectID(address(this));
        assertEq(pid, projId);

        // get old deployment request id
        latestDeploymentRequestId = proxy.getLatestDeploymentRequestID(address(this));
        assertEq(deploymentRequestId, latestDeploymentRequestId);
    }

    function test_UpgradeV3() public {
        string memory ver = proxy.VERSION();
        assertEq(ver, "1.0.0");

        bytes32 pid = proxy.createProjectID();
        bytes32 projId = proxy.getLatestUserProjectID(address(this));
        assertEq(pid, projId);

        bytes32 deploymentRequestId =
            proxy.createDeploymentRequest(projId, solverAddress, "test base64 param", "test server url");
        bytes32 latestDeploymentRequestId = proxy.getLatestDeploymentRequestID(address(this));
        assertEq(deploymentRequestId, latestDeploymentRequestId);

        BlueprintV2 blueprintV2 = new BlueprintV2();
        proxy.upgradeToAndCall(address(blueprintV2), abi.encodeWithSignature("initialize()"));
        ver = proxy.VERSION();
        assertEq(ver, "2.0.0");

        // create proposal request with old project id from v1
        bytes32 proposalId = proxy.createProposalRequest(projId, "test base64 param", "test server url");
        bytes32 latestProposalId = proxy.getLatestProposalRequestID(address(this));
        assertEq(proposalId, latestProposalId);

        // get old project id
        projId = proxy.getLatestUserProjectID(address(this));
        assertEq(pid, projId);

        // get old deployment request id
        latestDeploymentRequestId = proxy.getLatestDeploymentRequestID(address(this));
        assertEq(deploymentRequestId, latestDeploymentRequestId);

        // Sleep for one second to ensure createProjectID() will return a different value
        vm.warp(block.timestamp + 1);
        // create new project
        bytes32 pidV2 = proxy.createProjectID();
        bytes32 projIdV2 = proxy.getLatestUserProjectID(address(this));
        assertEq(pidV2, projIdV2);

        // create new deployment
        bytes32 deploymentRequestIdV2 =
            proxy.createDeploymentRequest(projIdV2, solverAddress, "test base64 param", "test server url");
        bytes32 latestDeploymentRequestIdV2 = proxy.getLatestDeploymentRequestID(address(this));
        assertEq(deploymentRequestIdV2, latestDeploymentRequestIdV2);

        BlueprintV3 blueprintV3 = new BlueprintV3();
        proxy.upgradeToAndCall(address(blueprintV3), abi.encodeWithSignature("initialize()"));
        ver = proxy.VERSION();
        assertEq(ver, "3.0.0");

        // create proposal request with old project id from v2
        proposalId = proxy.createProposalRequest(projIdV2, "test base64 param", "test server url");
        latestProposalId = proxy.getLatestProposalRequestID(address(this));
        assertEq(proposalId, latestProposalId);

        // get old project id from v2
        projId = proxy.getLatestUserProjectID(address(this));
        assertEq(projIdV2, projId);

        // get old deployment request id from V2
        latestDeploymentRequestId = proxy.getLatestDeploymentRequestID(address(this));
        assertEq(deploymentRequestIdV2, latestDeploymentRequestId);
    }

    function test_UpgradeV4() public {
        string memory ver = proxy.VERSION();
        assertEq(ver, "1.0.0");

        bytes32 pid = proxy.createProjectID();
        bytes32 projId = proxy.getLatestUserProjectID(address(this));
        assertEq(pid, projId);

        bytes32 deploymentRequestId =
            proxy.createDeploymentRequest(projId, solverAddress, "test base64 param", "test server url");
        bytes32 latestDeploymentRequestId = proxy.getLatestDeploymentRequestID(address(this));
        assertEq(deploymentRequestId, latestDeploymentRequestId);

        BlueprintV2 blueprintV2 = new BlueprintV2();
        proxy.upgradeToAndCall(address(blueprintV2), abi.encodeWithSignature("initialize()"));
        ver = proxy.VERSION();
        assertEq(ver, "2.0.0");

        // create proposal request with old project id from v1
        bytes32 proposalId = proxy.createProposalRequest(projId, "test base64 param", "test server url");
        bytes32 latestProposalId = proxy.getLatestProposalRequestID(address(this));
        assertEq(proposalId, latestProposalId);

        // get old project id
        projId = proxy.getLatestUserProjectID(address(this));
        assertEq(pid, projId);

        // get old deployment request id
        latestDeploymentRequestId = proxy.getLatestDeploymentRequestID(address(this));
        assertEq(deploymentRequestId, latestDeploymentRequestId);

        // Sleep for one second to ensure createProjectID() will return a different value
        vm.warp(block.timestamp + 1);
        // create new project
        bytes32 pidV2 = proxy.createProjectID();
        bytes32 projIdV2 = proxy.getLatestUserProjectID(address(this));
        assertEq(pidV2, projIdV2);

        // create new deployment
        bytes32 deploymentRequestIdV2 =
            proxy.createDeploymentRequest(projIdV2, solverAddress, "test base64 param", "test server url");
        bytes32 latestDeploymentRequestIdV2 = proxy.getLatestDeploymentRequestID(address(this));
        assertEq(deploymentRequestIdV2, latestDeploymentRequestIdV2);

        BlueprintV3 blueprintV3 = new BlueprintV3();
        proxy.upgradeToAndCall(address(blueprintV3), abi.encodeWithSignature("initialize()"));
        ver = proxy.VERSION();
        assertEq(ver, "3.0.0");

        // create proposal request with old project id from v2
        proposalId = proxy.createProposalRequest(projIdV2, "test base64 param", "test server url");
        latestProposalId = proxy.getLatestProposalRequestID(address(this));
        assertEq(proposalId, latestProposalId);

        // get old project id from v2
        projId = proxy.getLatestUserProjectID(address(this));
        assertEq(projIdV2, projId);

        // get old deployment request id from V2
        latestDeploymentRequestId = proxy.getLatestDeploymentRequestID(address(this));
        assertEq(deploymentRequestIdV2, latestDeploymentRequestId);

        // set worker public key
        bytes memory publicKey1 = hex"123456";
        // cast proxy to BlueprintV3 to call setWorkerPublicKey
        BlueprintV3(address(proxy)).setWorkerPublicKey(publicKey1);

        // upgrade into V4
        BlueprintV4 blueprintV4 = new BlueprintV4();
        proxy.upgradeToAndCall(address(blueprintV4), abi.encodeWithSignature("initialize()"));
        ver = proxy.VERSION();
        assertEq(ver, "4.0.0");

        // get project id from V3
        bytes32 projIdV3 = proxy.getLatestUserProjectID(address(this));
        assertEq(projIdV3, projId);

        // create new deployment
        projIdV4 = bytes32(0x2723a34e38d0f0aa09ce626f00aa23c0464b52c75516cf3203cc4c9afeaf2980);

        BlueprintV4(address(proxy)).createProjectIDAndDeploymentRequest(projIdV4, "base64", "test server url");

        // get latest project id
        bytes32 latestProjId = proxy.getLatestUserProjectID(address(this));
        assertEq(projIdV4, latestProjId);
    }

    function test_UpdradeV5() public {
        test_UpgradeV4();

        // upgrade into V5
        BlueprintV5 blueprintV5 = new BlueprintV5();
        proxy.upgradeToAndCall(address(blueprintV5), abi.encodeWithSignature("initialize()"));
        string memory ver = proxy.VERSION();
        assertEq(ver, "5.0.0");

        // get v4 project id
        bytes32 latestProjId = proxy.getLatestUserProjectID(address(this));
        assertEq(projIdV4, latestProjId);

        // create new deployment
        projIdV5 = bytes32(0x2723a34e38d0f0aa09ce626f00aa23c0464b52c75516cf3203cc4c9afeaf2985);

        BlueprintV5(address(proxy)).createProjectIDAndDeploymentRequest(projIdV5, "base64", "test server url");

        // get latest project id
        latestProjId = proxy.getLatestUserProjectID(address(this));
        assertEq(projIdV5, latestProjId);

        assertEq(BlueprintV5(address(proxy)).NFT_CONTRACT_ADDRESS(), NFT_CONTRACT_ADDRESS);
    }
}
