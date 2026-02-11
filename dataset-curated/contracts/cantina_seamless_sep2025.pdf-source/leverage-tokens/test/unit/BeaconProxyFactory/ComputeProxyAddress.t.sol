// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Internal imports
import {BeaconProxyFactoryTest} from "./BeaconProxyFactory.t.sol";
import {MockValue} from "../mock/MockValue.sol";

contract ComputeProxyAddressTest is BeaconProxyFactoryTest {
    function testFuzz_computeProxyAddress_DifferentSalt(bytes32 saltA, bytes32 saltB) public view {
        vm.assume(saltA != saltB);
        bytes memory emptyData = hex"";
        address expectedProxyAddressA = factory.computeProxyAddress(address(this), emptyData, saltA);
        address expectedProxyAddressB = factory.computeProxyAddress(address(this), emptyData, saltB);

        assertNotEq(expectedProxyAddressA, expectedProxyAddressB);

        bytes memory initializeData = abi.encodeWithSelector(MockValue.initialize.selector, 100);
        address expectedProxyAddressC = factory.computeProxyAddress(address(this), initializeData, saltA);
        address expectedProxyAddressD = factory.computeProxyAddress(address(this), initializeData, saltB);

        assertNotEq(expectedProxyAddressC, expectedProxyAddressD);
    }

    function testFuzz_computeProxyAddress_SameInitializationDataAndSaltDifferentDeployers(
        address deployerA,
        address deployerB
    ) public view {
        vm.assume(deployerA != deployerB);

        bytes memory initializeData = abi.encodeWithSelector(MockValue.initialize.selector, 100);
        bytes32 salt = bytes32(uint256(1));

        address expectedProxyAddressA = factory.computeProxyAddress(deployerA, initializeData, salt);
        address expectedProxyAddressB = factory.computeProxyAddress(deployerB, initializeData, salt);

        assertNotEq(expectedProxyAddressA, expectedProxyAddressB);
    }
}
