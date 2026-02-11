// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { Test } from "forge-std/Test.sol";

import { BridgeCoordinatorL1, IERC20, IWhitelabeledUnit } from "../../src/BridgeCoordinatorL1.sol";

import { BridgeCoordinatorL1Harness } from "../harness/BridgeCoordinatorL1Harness.sol";

abstract contract BridgeCoordinatorL1Test is Test {
    BridgeCoordinatorL1Harness coordinator;

    address unit = makeAddr("unit");
    address admin = makeAddr("admin");
    address whitelabel = makeAddr("whitelabel");

    function _resetInitializableStorageSlot() internal {
        // reset the Initializable storage slot to allow usage of deployed instance in tests
        vm.store(address(coordinator), coordinator.exposed_initializableStorageSlot(), bytes32(0));
    }

    function setUp() public virtual {
        coordinator = new BridgeCoordinatorL1Harness();
        _resetInitializableStorageSlot();
        coordinator.initialize(unit, admin);

        vm.mockCall(unit, abi.encodeWithSelector(IERC20.transfer.selector), abi.encode(true));
        vm.mockCall(unit, abi.encodeWithSelector(IERC20.transferFrom.selector), abi.encode(true));
        vm.mockCall(whitelabel, abi.encodeWithSelector(IWhitelabeledUnit.wrap.selector), "");
        vm.mockCall(whitelabel, abi.encodeWithSelector(IWhitelabeledUnit.unwrap.selector), "");
    }
}

contract BridgeCoordinatorL1_RestrictUnits_Test is BridgeCoordinatorL1Test {
    function testFuzz_shouldLockUnits_whenZeroWhitelabel(address owner, uint256 amount) public {
        vm.assume(owner != address(0));
        amount = bound(amount, 1, type(uint256).max / 2);

        bytes[] memory returnData = new bytes[](2);
        returnData[0] = abi.encode(1000e18);
        returnData[1] = abi.encode(1000e18 + amount);
        vm.mockCalls(unit, abi.encodeCall(IERC20.balanceOf, (address(coordinator))), returnData);

        vm.expectCall(unit, abi.encodeCall(IERC20.transferFrom, (owner, address(coordinator), amount)));

        coordinator.exposed_restrictUnits(address(0), owner, amount);
    }

    function testFuzz_shouldUnwrapAndLockUnits_whenWhitelabel(address owner, uint256 amount) public {
        vm.assume(owner != address(0));
        amount = bound(amount, 1, type(uint256).max / 2);

        bytes[] memory returnData = new bytes[](2);
        returnData[0] = abi.encode(1000e18);
        returnData[1] = abi.encode(1000e18 + amount);
        vm.mockCalls(unit, abi.encodeCall(IERC20.balanceOf, (address(coordinator))), returnData);

        vm.expectCall(whitelabel, abi.encodeCall(IWhitelabeledUnit.unwrap, (owner, address(coordinator), amount)));

        coordinator.exposed_restrictUnits(whitelabel, owner, amount);
    }

    function test_shouldRevert_whenIncorrectAmountUpdated() public {
        address owner = makeAddr("owner");
        uint256 amount = 500;

        bytes[] memory returnData = new bytes[](2);
        returnData[0] = abi.encode(1000e18);
        returnData[1] = abi.encode(1000e18 + amount + 1); // incorrect balance after transfer
        vm.mockCalls(unit, abi.encodeCall(IERC20.balanceOf, (address(coordinator))), returnData);

        vm.expectRevert(BridgeCoordinatorL1.IncorrectEscrowBalance.selector);
        coordinator.exposed_restrictUnits(address(0), owner, amount);
    }
}

contract BridgeCoordinatorL1_ReleaseUnits_Test is BridgeCoordinatorL1Test {
    function testFuzz_shouldUnlockUnits_whenZeroWhitelabel(address recipient, uint256 amount) public {
        vm.assume(recipient != address(0));
        amount = bound(amount, 1, 1000e18);

        vm.expectCall(unit, abi.encodeCall(IERC20.transfer, (recipient, amount)));

        coordinator.exposed_releaseUnits(address(0), recipient, amount);
    }

    function testFuzz_shouldUnlockAndWrapUnits_whenWhitelabel(address recipient, uint256 amount) public {
        vm.assume(recipient != address(0));
        amount = bound(amount, 1, 1000e18);

        vm.expectCall(whitelabel, abi.encodeCall(IWhitelabeledUnit.wrap, (recipient, amount)));

        coordinator.exposed_releaseUnits(whitelabel, recipient, amount);
    }
}
