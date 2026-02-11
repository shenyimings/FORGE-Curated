// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { Test } from "forge-std/Test.sol";

import { IERC20Metadata, IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import { IWhitelabeledUnit } from "../../../../src/interfaces/IWhitelabeledUnit.sol";

import { WhitelabeledUnitUpgradeableHarness } from "../../../harness/WhitelabeledUnitUpgradeableHarness.sol";

abstract contract WhitelabeledUnitUpgradeableTest is Test {
    WhitelabeledUnitUpgradeableHarness whitelabel;

    address unitToken = makeAddr("unitToken");

    function _resetInitializableStorageSlot() internal {
        // reset the Initializable storage slot to allow usage of deployed instance in tests
        vm.store(address(whitelabel), whitelabel.exposed_initializableStorageSlot(), bytes32(0));
    }

    function setUp() public virtual {
        whitelabel = new WhitelabeledUnitUpgradeableHarness();
        _resetInitializableStorageSlot();
        whitelabel.workaround_initialize("Generic USD", "GUSD", IERC20(unitToken));

        vm.mockCall(unitToken, abi.encodeWithSelector(IERC20.transferFrom.selector), abi.encode(true));
        vm.mockCall(unitToken, abi.encodeWithSelector(IERC20.transfer.selector), abi.encode(true));
    }
}

contract WhitelabeledUnitUpgradeable_Initialize_Test is WhitelabeledUnitUpgradeableTest {
    function testFuzz_shouldInitialize(string memory name, string memory symbol, address unitToken) public {
        // We allow zero address for unitToken
        whitelabel = new WhitelabeledUnitUpgradeableHarness();
        _resetInitializableStorageSlot();
        whitelabel.workaround_initialize(name, symbol, IERC20(unitToken));

        assertEq(whitelabel.name(), name);
        assertEq(whitelabel.symbol(), symbol);
        assertEq(whitelabel.genericUnit(), unitToken);
    }
}

contract WhitelabeledUnitUpgradeable_Wrap_Test is WhitelabeledUnitUpgradeableTest {
    function testFuzz_shouldWrapShareTokens(address owner, uint256 amount) public {
        vm.assume(owner != address(0));

        address caller = makeAddr("caller");

        vm.expectCall(
            unitToken, abi.encodeWithSelector(IERC20.transferFrom.selector, caller, address(whitelabel), amount)
        );

        vm.expectEmit();
        emit IWhitelabeledUnit.Wrapped(owner, amount);

        vm.prank(caller);
        whitelabel.wrap(owner, amount);

        assertEq(whitelabel.balanceOf(owner), amount);
    }
}

contract WhitelabeledUnitUpgradeable_Unwrap_Test is WhitelabeledUnitUpgradeableTest {
    address owner = makeAddr("owner");
    address recipient = makeAddr("recipient");
    address spender = makeAddr("spender");
    uint256 initialBalance = 1000e18;

    function setUp() public override {
        super.setUp();

        // Pre-mint some whitelabeled tokens to test unwrapping
        vm.startPrank(owner);
        whitelabel.wrap(owner, initialBalance);
        whitelabel.approve(address(whitelabel), type(uint256).max);
        vm.stopPrank();
    }

    function testFuzz_shouldUnwrapUnitTokens_whenCallerIsOwner(uint256 amount) public {
        amount = bound(amount, 0, initialBalance);

        vm.expectCall(unitToken, abi.encodeWithSelector(IERC20.transfer.selector, recipient, amount));

        vm.expectEmit();
        emit IWhitelabeledUnit.Unwrapped(owner, recipient, amount);

        vm.prank(owner);
        whitelabel.unwrap(owner, recipient, amount);

        assertEq(whitelabel.balanceOf(owner), initialBalance - amount);
    }

    function testFuzz_shouldUnwrapShareTokens_whenSpenderIsNotOwner(uint256 amount) public {
        amount = bound(amount, 0, initialBalance);

        vm.expectCall(unitToken, abi.encodeWithSelector(IERC20.transfer.selector, recipient, amount));

        vm.prank(owner);
        whitelabel.approve(spender, amount);

        vm.expectEmit();
        emit IWhitelabeledUnit.Unwrapped(owner, recipient, amount);

        vm.prank(spender);
        whitelabel.unwrap(owner, recipient, amount);

        assertEq(whitelabel.balanceOf(owner), initialBalance - amount);
    }

    function test_shouldRevert_whenSpenderNotApproved() public {
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, initialBalance)
        );
        vm.prank(spender);
        whitelabel.unwrap(owner, recipient, initialBalance);
    }
}

contract WhitelabeledUnitUpgradeable_Decimals_Test is WhitelabeledUnitUpgradeableTest {
    function testFuzz_shouldReturnShareTokenDecimals(uint8 decimals) public {
        vm.mockCall(unitToken, abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(decimals));

        assertEq(whitelabel.decimals(), decimals);
    }
}
