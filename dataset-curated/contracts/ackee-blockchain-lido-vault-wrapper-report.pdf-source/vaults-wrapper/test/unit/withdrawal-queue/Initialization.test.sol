// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {Test} from "forge-std/Test.sol";
import {WithdrawalQueue} from "src/WithdrawalQueue.sol";
import {OssifiableProxy} from "src/proxy/OssifiableProxy.sol";

contract InitializationTest is Test {
    WithdrawalQueue internal withdrawalQueueProxy;
    WithdrawalQueue internal withdrawalQueueImpl;
    address internal owner;
    address internal finalizeRoleHolder;

    function setUp() public {
        owner = makeAddr("owner");
        finalizeRoleHolder = makeAddr("finalizeRoleHolder");

        withdrawalQueueImpl = new WithdrawalQueue(
            makeAddr("pool"),
            makeAddr("dashboard"),
            makeAddr("vaultHub"),
            makeAddr("steth"),
            makeAddr("stakingVault"),
            makeAddr("lazyOracle"),
            1 days,
            true
        );
        OssifiableProxy proxy = new OssifiableProxy(address(withdrawalQueueImpl), owner, "");
        withdrawalQueueProxy = WithdrawalQueue(payable(proxy));
    }

    function test_Initialize_RevertOnImplementation() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        withdrawalQueueImpl.initialize(address(0), finalizeRoleHolder, address(0), address(0));
    }

    function test_Initialize_RevertWhenAdminZero() public {
        vm.expectRevert(WithdrawalQueue.ZeroAddress.selector);
        withdrawalQueueProxy.initialize(address(0), finalizeRoleHolder, address(0), address(0));
    }

    function test_Initialize_RevertWhenFinalizerZero() public {
        vm.expectRevert(WithdrawalQueue.ZeroAddress.selector);
        withdrawalQueueProxy.initialize(owner, address(0), address(0), address(0));
    }

    function test_Initialize_RevertWhenCalledTwice() public {
        withdrawalQueueProxy.initialize(owner, finalizeRoleHolder, owner, owner);

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        withdrawalQueueProxy.initialize(owner, finalizeRoleHolder, owner, owner);
    }
}
