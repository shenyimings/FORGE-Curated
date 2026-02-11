// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Forge imports
import {Test} from "forge-std/Test.sol";

// Dependency imports
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

// Internal imports
import {BeaconProxyFactory} from "src/BeaconProxyFactory.sol";
import {MockValue} from "../mock/MockValue.sol";

contract BeaconProxyFactoryTest is Test {
    BeaconProxyFactory public factory;

    address public implementation;
    address public owner = makeAddr("owner");
    UpgradeableBeacon public beacon;

    function setUp() public {
        implementation = address(new MockValue());
        factory = new BeaconProxyFactory(implementation, owner);
        beacon = UpgradeableBeacon(address(factory));
    }

    function test_constructor() public view {
        assertEq(factory.implementation(), implementation);
        assertEq(factory.owner(), owner);
    }
}
