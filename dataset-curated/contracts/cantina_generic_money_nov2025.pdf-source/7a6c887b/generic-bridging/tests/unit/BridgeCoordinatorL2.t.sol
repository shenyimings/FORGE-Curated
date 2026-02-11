// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { Test } from "forge-std/Test.sol";

import { IERC20Mintable, IWhitelabeledUnit } from "../../src/BridgeCoordinatorL2.sol";

import { BridgeCoordinatorL2Harness } from "../harness/BridgeCoordinatorL2Harness.sol";

abstract contract BridgeCoordinatorL2Test is Test {
    BridgeCoordinatorL2Harness coordinator;

    address unit = makeAddr("unit");
    address admin = makeAddr("admin");
    address whitelabel = makeAddr("whitelabel");

    function _resetInitializableStorageSlot() internal {
        // reset the Initializable storage slot to allow usage of deployed instance in tests
        vm.store(address(coordinator), coordinator.exposed_initializableStorageSlot(), bytes32(0));
    }

    function setUp() public virtual {
        coordinator = new BridgeCoordinatorL2Harness();
        _resetInitializableStorageSlot();
        coordinator.initialize(unit, admin);

        vm.mockCall(unit, abi.encodeWithSelector(IERC20Mintable.mint.selector), "");
        vm.mockCall(unit, abi.encodeWithSelector(IERC20Mintable.burn.selector), "");
        vm.mockCall(whitelabel, abi.encodeWithSelector(IWhitelabeledUnit.wrap.selector), "");
        vm.mockCall(whitelabel, abi.encodeWithSelector(IWhitelabeledUnit.unwrap.selector), "");
    }
}

contract BridgeCoordinatorL2_RestrictUnits_Test is BridgeCoordinatorL2Test {
    function testFuzz_shouldBurnTokens_whenZeroWhitelabel(address owner, uint256 amount) public {
        vm.assume(owner != address(0));
        vm.assume(amount > 0);

        vm.expectCall(unit, abi.encodeWithSelector(IERC20Mintable.burn.selector, owner, address(coordinator), amount));

        coordinator.exposed_restrictUnits(address(0), owner, amount);
    }

    function testFuzz_shouldUnwrapAndBurnTokens_whenWhitelabel(address owner, uint256 amount) public {
        vm.assume(owner != address(0));
        vm.assume(amount > 0);

        vm.expectCall(whitelabel, abi.encodeCall(IWhitelabeledUnit.unwrap, (owner, address(coordinator), amount)));
        vm.expectCall(unit, abi.encodeCall(IERC20Mintable.burn, (address(coordinator), address(coordinator), amount)));

        coordinator.exposed_restrictUnits(whitelabel, owner, amount);
    }
}

contract BridgeCoordinatorL2_ReleaseUnits_Test is BridgeCoordinatorL2Test {
    function testFuzz_shouldMintTokens_whenZeroWhitelabel(address recipient, uint256 amount) public {
        vm.assume(recipient != address(0));
        vm.assume(amount > 0);

        vm.expectCall(unit, abi.encodeWithSelector(IERC20Mintable.mint.selector, recipient, amount));

        coordinator.exposed_releaseUnits(address(0), recipient, amount);
    }

    function testFuzz_shouldMintAndWrapTokens_whenWhitelabel(address recipient, uint256 amount) public {
        vm.assume(recipient != address(0));
        vm.assume(amount > 0);

        vm.expectCall(unit, abi.encodeCall(IERC20Mintable.mint, (address(coordinator), amount)));
        vm.expectCall(whitelabel, abi.encodeCall(IWhitelabeledUnit.wrap, (recipient, amount)));

        coordinator.exposed_releaseUnits(whitelabel, recipient, amount);
    }
}
