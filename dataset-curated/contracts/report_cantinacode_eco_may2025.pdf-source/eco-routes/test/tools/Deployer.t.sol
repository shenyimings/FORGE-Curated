// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {BaseTest} from "../BaseTest.sol";
import {Deployer, IDeployer} from "../../contracts/tools/Deployer.sol";
import {TestERC20} from "../../contracts/test/TestERC20.sol";

contract MockDeployer is IDeployer {
    mapping(bytes32 => address) public deployedContracts;

    function deploy(
        bytes memory _initCode,
        bytes32 _salt
    ) external override returns (address payable createdContract) {
        bytes32 key = keccak256(abi.encodePacked(_initCode, _salt));

        if (deployedContracts[key] == address(0)) {
            TestERC20 testContract = new TestERC20("TestToken", "TEST");
            createdContract = payable(address(testContract));
            deployedContracts[key] = createdContract;
        } else {
            createdContract = payable(deployedContracts[key]);
        }

        return createdContract;
    }
}

contract DeployerTest is BaseTest {
    Deployer internal deployerContract;
    MockDeployer internal mockDeployer;

    function setUp() public override {
        super.setUp();

        vm.startPrank(deployer);
        mockDeployer = new MockDeployer();
        deployerContract = new Deployer(IDeployer(address(mockDeployer)));
        vm.stopPrank();
    }

    function testDeployerBasicFunctionality() public {
        bytes memory initCode = abi.encodePacked(
            type(TestERC20).creationCode,
            abi.encode("TestToken", "TEST")
        );
        bytes32 salt = keccak256("test-salt");

        vm.prank(creator);
        address payable deployed = deployerContract.deploy(initCode, salt);

        assertNotEq(deployed, address(0));

        // Verify it's a working contract
        TestERC20 token = TestERC20(deployed);
        assertEq(token.name(), "TestToken");
        assertEq(token.symbol(), "TEST");
    }

    function testDeployerDeterministicDeployment() public {
        bytes memory initCode = abi.encodePacked(
            type(TestERC20).creationCode,
            abi.encode("TestToken", "TEST")
        );
        bytes32 salt = keccak256("test-salt");

        vm.prank(creator);
        address payable deployed1 = deployerContract.deploy(initCode, salt);

        vm.prank(claimant);
        address payable deployed2 = deployerContract.deploy(initCode, salt);

        // Should be the same address
        assertEq(deployed1, deployed2);
    }

    function testDeployerDifferentSalts() public {
        bytes memory initCode = abi.encodePacked(
            type(TestERC20).creationCode,
            abi.encode("TestToken", "TEST")
        );
        bytes32 salt1 = keccak256("salt1");
        bytes32 salt2 = keccak256("salt2");

        vm.prank(creator);
        address payable deployed1 = deployerContract.deploy(initCode, salt1);

        vm.prank(creator);
        address payable deployed2 = deployerContract.deploy(initCode, salt2);

        // Should be different addresses
        assertNotEq(deployed1, deployed2);
    }

    function testDeployerEmitsEvent() public {
        bytes memory initCode = abi.encodePacked(
            type(TestERC20).creationCode,
            abi.encode("TestToken", "TEST")
        );
        bytes32 salt = keccak256("test-salt");

        vm.expectEmit(true, false, false, false);
        emit Deployer.Deployed(creator, address(0)); // We don't know the exact address

        vm.prank(creator);
        deployerContract.deploy(initCode, salt);
    }

    function testDeployerImmutableDeployer() public {
        address initialDeployer = address(deployerContract.deployer());

        // Time travel shouldn't affect the deployer
        vm.warp(block.timestamp + 1000);
        vm.roll(block.number + 1000);

        assertEq(address(deployerContract.deployer()), initialDeployer);
    }

    function testDeployerWithZeroDeployer() public {
        Deployer defaultDeployer = new Deployer(IDeployer(address(0)));

        // Should use EIP-2470 SingletonFactory address
        assertEq(
            address(defaultDeployer.deployer()),
            0xce0042B868300000d44A59004Da54A005ffdcf9f
        );
    }
}
