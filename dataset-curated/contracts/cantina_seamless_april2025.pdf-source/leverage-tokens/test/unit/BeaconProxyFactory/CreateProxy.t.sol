// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Internal imports
import {BeaconProxyFactoryTest} from "./BeaconProxyFactory.t.sol";
import {BeaconProxyFactory} from "src/BeaconProxyFactory.sol";
import {IBeaconProxyFactory} from "src/interfaces/IBeaconProxyFactory.sol";
import {MockValue} from "../mock/MockValue.sol";

contract CreateProxyTest is BeaconProxyFactoryTest {
    /// forge-config: default.fuzz.runs = 1
    function testFuzz_createProxy_WithoutInitializationData(bytes32 salt) public {
        bytes memory data = hex"";
        address expectedProxyAddress = factory.computeProxyAddress(address(this), data, salt);

        vm.expectEmit(true, true, true, true);
        emit IBeaconProxyFactory.BeaconProxyCreated(expectedProxyAddress, data, salt);
        address proxy = factory.createProxy(data, salt);

        assertEq(proxy, expectedProxyAddress);
        assertEq(factory.numProxies(), 1);
        assertEq(MockValue(proxy).mockFunction(), 0); // Zero because it was not initialized
    }

    /// forge-config: default.fuzz.runs = 1
    function testFuzz_createProxy_WithInitializationData(bytes32 salt) public {
        uint256 value = 100;
        bytes memory data = abi.encodeWithSelector(MockValue.initialize.selector, value);
        address expectedProxyAddress = factory.computeProxyAddress(address(this), data, salt);

        vm.expectCall(implementation, data);
        vm.expectEmit(true, true, true, true);
        emit IBeaconProxyFactory.BeaconProxyCreated(expectedProxyAddress, data, salt);
        address proxy = factory.createProxy(data, salt);

        assertEq(MockValue(proxy).mockFunction(), value);
        assertEq(MockValue(proxy).initialized(), true);
        assertEq(factory.numProxies(), 1);
        assertEq(proxy, expectedProxyAddress);
    }

    /// forge-config: default.fuzz.runs = 1
    function testFuzz_createProxy_SameInitializationDataAndSaltDifferentDeployers(address deployerA, address deployerB)
        public
        view
    {
        vm.assume(deployerA != deployerB);

        bytes memory initializeData = abi.encodeWithSelector(MockValue.initialize.selector, 100);
        bytes32 salt = bytes32(uint256(1));

        // Expect neither to revert
        factory.computeProxyAddress(deployerA, initializeData, salt);
        factory.computeProxyAddress(deployerB, initializeData, salt);
    }
}
