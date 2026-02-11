// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {PDPVerifier} from "../src/PDPVerifier.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MyERC1967Proxy} from "../src/ERC1967Proxy.sol";
contract ERC1967ProxyTest is Test {
    PDPVerifier public implementation;
    PDPVerifier public proxy;
    address owner = address(0x123);

    function setUp() public {
         // Set owner for testing
        vm.startPrank(owner);
        // Deploy implementation contract
        implementation = new PDPVerifier();

        // Deploy proxy pointing to implementation
        bytes memory initData = abi.encodeWithSelector(
            PDPVerifier.initialize.selector,
            uint256(150) // challengeFinality
        );

        ERC1967Proxy proxyContract = new MyERC1967Proxy(
            address(implementation),
            initData
        );

        // Get PDPVerifier interface on proxy address
        proxy = PDPVerifier(address(proxyContract));
    }

    function testInitialSetup() public view {
        assertEq(proxy.getChallengeFinality(), 150);
        assertEq(proxy.owner(), owner);
    }

    function assertImplementationEquals(address checkImpl) public view {
        bytes32 implementationSlot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        assertEq(address(uint160(uint256(vm.load(address(proxy), implementationSlot)))), address(checkImpl));
    }

    function testUpgradeImplementation() public {
        assertImplementationEquals(address(implementation));

        // Deploy new implementation
        PDPVerifier newImplementation = new PDPVerifier();
    
        // Upgrade proxy to new implementation
        proxy.upgradeToAndCall(address(newImplementation), "");

        // Verify upgrade was successful
        assertImplementationEquals(address(newImplementation));
        assertEq(proxy.getChallengeFinality(), 150); // State is preserved
        assertEq(proxy.owner(), owner); // Owner is preserved
    }

    function testUpgradeFromNonOwnerNoGood() public {
        PDPVerifier newImplementation = new PDPVerifier();
        
        vm.stopPrank();
        vm.startPrank(address(0xdead));

        vm.expectRevert();
        proxy.upgradeToAndCall(address(newImplementation), "");
        assertEq(proxy.getChallengeFinality(), 150); // State is preserved
        assertEq(proxy.owner(), owner); // Owner is preserved
    }

    function testOwnershipTransfer() public {
        vm.stopPrank();
        vm.startPrank(owner);
        // Verify initial owner
        assertEq(proxy.owner(), owner);

        address newOwner = address(0x123);

        // Transfer ownership
        proxy.transferOwnership(newOwner);
        
        // Verify ownership changed
        assertEq(proxy.owner(), newOwner);
    }

    function testTransferFromNonOwneNoGood() public {
        // Switch to non-owner account
        vm.stopPrank();
        vm.startPrank(address(0xdead));

        address newOwner = address(0x123);

        // Attempt transfer should fail
        vm.expectRevert();
        proxy.transferOwnership(newOwner);

        // Verify owner unchanged
        assertEq(proxy.owner(), owner);
    }
}
