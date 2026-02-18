pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {BlueprintV5} from "../src/BlueprintV5.sol";
import {BlueprintCore} from "../src/BlueprintCore.sol";
import {Blueprint} from "../src/Blueprint.sol";
import {stdError} from "forge-std/StdError.sol";
import {MockERC20} from "./MockERC20.sol";

contract BlueprintTest is Test {
    BlueprintV5 public blueprint;
    MockERC20 public mockToken;
    bytes32 public projectId;
    address public workerAddress;
    address public dummyAddress;

    function setUp() public {
        blueprint = new BlueprintV5();
        blueprint.initialize(); // mimic upgradeable contract deploy behavior

        mockToken = new MockERC20();

        // set crestal wallet address
        blueprint.setFeeCollectionWalletAddress(address(0x7D8be0Dd8915E3511fFDDABDD631812be824f578));

        projectId = bytes32(0x2723a34e38d0f0aa09ce626f00aa23c0464b52c75516cf3203cc4c9afeaf2980);
        workerAddress = address(0x4d6585D89F889F29f77fd7Dd71864269BA1B31df);
        dummyAddress = address(0);
    }

    function test_createAgentWithToken() public {
        string memory base64Proposal = "test base64 proposal";
        string memory serverURL = "http://example.com";

        // Generate the signature
        (bytes memory signature, address signerAddress) = generateSignature(projectId, base64Proposal, serverURL);

        // Add the payment address
        blueprint.addPaymentAddress(address(mockToken));

        // set zero cost for create agents, use any number less than 0
        blueprint.setCreateAgentTokenCost(address(mockToken), 0);

        // Expect the createAgent event
        vm.expectEmit(true, false, true, true);
        emit BlueprintCore.CreateAgent(projectId, "fake", signerAddress, 0, 0);

        // Create agent with token
        blueprint.createAgentWithTokenWithSig(
            projectId, base64Proposal, workerAddress, serverURL, address(mockToken), signature
        );

        bytes32 latestProjId = blueprint.getLatestUserProjectID(signerAddress);
        assertEq(projectId, latestProjId);

        // Mint tokens to the test account
        uint256 validTokenAmount = 100 * 10 ** 18;

        // set none zero cost for create agents, use any number greater than 0
        blueprint.setCreateAgentTokenCost(address(mockToken), validTokenAmount);

        mockToken.mint(address(this), validTokenAmount);

        // Verify the mint
        uint256 balance = mockToken.balanceOf(address(this));
        assertEq(balance, validTokenAmount, "sender does not have the correct token balance");

        // check LogApproveEvent
        vm.expectEmit(true, true, false, true);
        emit MockERC20.LogApproval(address(this), address(blueprint), validTokenAmount);

        // Approve the blueprint contract to spend tokens directly from the test contract
        mockToken.approve(address(blueprint), validTokenAmount);

        // check allowance after approve
        uint256 allowance = mockToken.allowance(address(this), address(blueprint));
        assertEq(allowance, validTokenAmount, "sender does not have the correct token allowance");

        // try with different project id
        projectId = bytes32(0x2723a34e38d0f0aa09ce626f00aa23c0464b52c75516cf3203cc4c9afeaf2981);
        // create agent with token and non zero cost
        blueprint.createAgentWithToken(projectId, base64Proposal, workerAddress, serverURL, address(mockToken));

        // check balance after creation, it should be balance - cost
        balance = mockToken.balanceOf(address(this));
        assertEq(balance, 0, "signer does not have the correct token balance after creation");
    }

    function test_Revert_createAgentWithToken() public {
        // not set agent creation operation
        vm.expectRevert("Token address is invalid");
        blueprint.createAgentWithToken(
            projectId, "test base64 proposal", workerAddress, "http://example.com", address(mockToken)
        );

        // Mint tokens to the test account
        uint256 validTokenAmount = 100 * 10 ** 18;

        // Add the payment address
        blueprint.addPaymentAddress(address(mockToken));

        // set none zero cost for create agents, use any number greater than 0
        blueprint.setCreateAgentTokenCost(address(mockToken), validTokenAmount);

        // not enough balance to create agent
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        blueprint.createAgentWithToken(
            projectId, "test base64 proposal", workerAddress, "http://example.com", address(mockToken)
        );

        // Mint tokens to the test account
        mockToken.mint(address(this), validTokenAmount);

        // not approve blueprint to spend token
        vm.expectRevert("ERC20: transfer amount exceeds allowance");
        blueprint.createAgentWithToken(
            projectId, "test base64 proposal", workerAddress, "http://example.com", address(mockToken)
        );

        // Approve the blueprint contract to spend tokens directly from the test contract
        mockToken.approve(address(blueprint), validTokenAmount - 1);

        // not enough allowance to create agent
        vm.expectRevert("ERC20: transfer amount exceeds allowance");
        blueprint.createAgentWithToken(
            projectId, "test base64 proposal", workerAddress, "http://example.com", address(mockToken)
        );
    }

    function test_updateWorkerDeploymentConfig() public {
        string memory base64Proposal = "test base64 proposal";
        string memory serverURL = "app.crestal.network";

        // Add the payment address
        blueprint.addPaymentAddress(address(mockToken));

        // set zero cost for create agents, use any number less than 0
        blueprint.setCreateAgentTokenCost(address(mockToken), 0);

        // Create agent with token
        bytes32 requestId =
            blueprint.createAgentWithToken(projectId, base64Proposal, workerAddress, serverURL, address(mockToken));

        // set zero cost for create agents, use any number less than 0
        blueprint.setUpdateCreateAgentTokenCost(address(mockToken), 0);

        // Expect the UpdateDeploymentConfig event
        vm.expectEmit(true, true, true, true);
        emit BlueprintCore.UpdateDeploymentConfig(projectId, requestId, workerAddress, base64Proposal);

        // update agent deployment config
        blueprint.updateWorkerDeploymentConfig(address(mockToken), projectId, requestId, base64Proposal);

        uint256 validTokenAmount = 100 * 10 ** 18;

        // Set the cost for updating the deployment config
        blueprint.setUpdateCreateAgentTokenCost(address(mockToken), validTokenAmount);

        // Mint tokens to the test account
        mockToken.mint(address(this), validTokenAmount);

        // Approve the blueprint contract to spend tokens
        mockToken.approve(address(blueprint), validTokenAmount);

        // Expect the UpdateDeploymentConfig event
        vm.expectEmit(true, true, true, true);
        emit BlueprintCore.UpdateDeploymentConfig(projectId, requestId, workerAddress, base64Proposal);

        //  update agent deployment config
        blueprint.updateWorkerDeploymentConfig(address(mockToken), projectId, requestId, base64Proposal);
    }

    function test_Revert_updateWorkerDeploymentConfig() public {
        string memory base64Proposal = "test base64 proposal";
        string memory serverURL = "app.crestal.network";

        // Add the payment address
        blueprint.addPaymentAddress(address(mockToken));

        // set zero cost for create agents, use any number less than 0
        blueprint.setCreateAgentTokenCost(address(mockToken), 0);

        // Create agent with token
        bytes32 requestId =
            blueprint.createAgentWithToken(projectId, base64Proposal, workerAddress, serverURL, address(mockToken));

        // Mint tokens to the test account
        uint256 validTokenAmount = 100 * 10 ** 18;

        // set none zero cost for create agents, use any number greater than 0
        blueprint.setUpdateCreateAgentTokenCost(address(mockToken), validTokenAmount);

        // not enough balance to create agent
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        //  update agent deployment config
        blueprint.updateWorkerDeploymentConfig(address(mockToken), projectId, requestId, base64Proposal);

        // Mint tokens to the test account
        mockToken.mint(address(this), validTokenAmount);

        // not approve blueprint to spend token
        vm.expectRevert("ERC20: transfer amount exceeds allowance");
        //  update agent deployment config
        blueprint.updateWorkerDeploymentConfig(address(mockToken), projectId, requestId, base64Proposal);

        // Approve the blueprint contract to spend tokens directly from the test contract
        mockToken.approve(address(blueprint), validTokenAmount - 1);

        // not enough allowance to create agent
        vm.expectRevert("ERC20: transfer amount exceeds allowance");
        //  update agent deployment config
        blueprint.updateWorkerDeploymentConfig(address(mockToken), projectId, requestId, base64Proposal);
    }

    function test_userTopUp() public {
        uint256 topUpAmount = 100 * 10 ** 18;

        // Add the payment address
        blueprint.addPaymentAddress(address(mockToken));

        // Mint tokens to the test account
        mockToken.mint(address(this), topUpAmount);

        // Approve the blueprint contract to spend tokens
        mockToken.approve(address(blueprint), topUpAmount);

        // Expect the UserTopUp event
        vm.expectEmit(true, true, true, true);
        emit BlueprintCore.UserTopUp(
            address(this), blueprint.feeCollectionWalletAddress(), address(mockToken), topUpAmount
        );

        // Call the userTopUp function
        blueprint.userTopUp(address(mockToken), topUpAmount);

        // Verify the top-up amount
        uint256 userBalance = blueprint.userTopUpMp(address(this), address(mockToken));
        assertEq(userBalance, topUpAmount, "User top-up amount is incorrect");

        // Verify the token transfer
        uint256 blueprintBalance = mockToken.balanceOf(address(blueprint.feeCollectionWalletAddress()));
        assertEq(blueprintBalance, topUpAmount, "Blueprint fee collection wallet balance is incorrect");

        // verify user balance after top up
        uint256 balance = mockToken.balanceOf(address(this));
        assertEq(balance, 0, "sender does not have the correct token balance after top up");
    }

    function test_Revert_userTopUp() public {
        uint256 topUpAmount = 100 * 10 ** 18;

        // Add the payment address
        blueprint.addPaymentAddress(address(mockToken));

        // Mint tokens to the test account
        mockToken.mint(address(this), topUpAmount);

        // not approve blueprint to spend token
        vm.expectRevert("ERC20: transfer amount exceeds allowance");
        // Call the userTopUp function
        blueprint.userTopUp(address(mockToken), topUpAmount);
    }

    function test_removePaymentAddress() public {
        address paymentAddress = address(mockToken);

        // Add the payment address
        blueprint.addPaymentAddress(paymentAddress);

        // Verify the payment address is added
        bool isPaymentAddressEnabled = blueprint.paymentAddressEnableMp(paymentAddress);
        assertTrue(isPaymentAddressEnabled, "Payment address should be enabled");

        // Expect the RemovePaymentAddress event
        vm.expectEmit(true, true, true, true);
        emit Blueprint.RemovePaymentAddress(paymentAddress);

        // Call the removePaymentAddress function
        blueprint.removePaymentAddress(paymentAddress);

        // Verify the payment address is removed (soft remove)
        isPaymentAddressEnabled = blueprint.paymentAddressEnableMp(paymentAddress);
        assertFalse(isPaymentAddressEnabled, "Payment address should be disabled");
    }

    function test_setCreateAgentTokenCost() public {
        address paymentAddress = address(mockToken);
        uint256 cost = 100 * 10 ** 18;

        // Add the payment address
        blueprint.addPaymentAddress(paymentAddress);

        // Expect the CreateAgentTokenCost event
        vm.expectEmit(true, true, true, true);
        emit Blueprint.CreateAgentTokenCost(paymentAddress, cost);

        // Call the setCreateAgentTokenCost function
        blueprint.setCreateAgentTokenCost(paymentAddress, cost);

        // Verify the token cost is set correctly
        uint256 setCost = blueprint.paymentOpCostMp(paymentAddress, blueprint.CREATE_AGENT_OP());
        assertEq(setCost, cost, "Create agent token cost is incorrect");
    }

    function test_setUpdateCreateAgentTokenCost() public {
        address paymentAddress = address(mockToken);
        uint256 cost = 50 * 10 ** 18;

        // Add the payment address
        blueprint.addPaymentAddress(paymentAddress);

        // Expect the UpdateAgentTokenCost event
        vm.expectEmit(true, true, true, true);
        emit Blueprint.UpdateAgentTokenCost(paymentAddress, cost);

        // Call the setUpdateCreateAgentTokenCost function
        blueprint.setUpdateCreateAgentTokenCost(paymentAddress, cost);

        // Verify the token cost is set correctly
        uint256 setCost = blueprint.paymentOpCostMp(paymentAddress, blueprint.UPDATE_AGENT_OP());
        assertEq(setCost, cost, "Update agent token cost is incorrect");
    }

    function test_addPaymentAddress() public {
        address paymentAddress = address(mockToken);

        // Expect the PaymentAddressAdded event
        vm.expectEmit(true, true, true, true);
        emit Blueprint.PaymentAddressAdded(paymentAddress);

        // Call the addPaymentAddress function
        blueprint.addPaymentAddress(paymentAddress);

        // Verify the payment address is added
        bool isPaymentAddressEnabled = blueprint.paymentAddressEnableMp(paymentAddress);
        assertTrue(isPaymentAddressEnabled, "Payment address should be enabled");

        // Verify the payment address is in the list
        address[] memory paymentAddresses = blueprint.getPaymentAddresses();
        bool found = false;
        for (uint256 i = 0; i < paymentAddresses.length; i++) {
            if (paymentAddresses[i] == paymentAddress) {
                found = true;
                break;
            }
        }

        assertTrue(found, "Payment address should be in the list");
    }

    function generateSignature(bytes32 _projectId, string memory _base64Proposal, string memory _serverURL)
        internal
        view
        returns (bytes memory, address)
    {
        bytes32 digest = blueprint.getRequestDeploymentDigest(_projectId, _base64Proposal, _serverURL);
        uint256 signerPrivateKey = 0xA11CE;
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, digest);
        return (abi.encodePacked(r, s, v), vm.addr(0xA11CE));
    }
}
