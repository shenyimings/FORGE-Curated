// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { Test } from "forge-std/Test.sol";

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { GenericUnit, IController } from "../../../src/unit/GenericUnit.sol";

abstract contract GenericUnitTest is Test {
    GenericUnit unit;

    address owner = makeAddr("owner");

    function setUp() public virtual {
        unit = new GenericUnit(owner, "name", "symbol");
    }
}

contract GenericUnit_Constructor_Test is GenericUnitTest {
    function test_shouldSetsInitialValues() public {
        address otherOwner = makeAddr("otherOwner");
        unit = new GenericUnit(otherOwner, "name", "symbol");

        assertEq(unit.owner(), otherOwner);
        assertEq(unit.name(), "name");
        assertEq(unit.symbol(), "symbol");
        assertEq(unit.decimals(), 18);
        assertEq(unit.totalSupply(), 0);
    }

    function test_shouldRevert_whenZeroOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        unit = new GenericUnit(address(0), "name", "symbol");
    }
}

contract GenericUnit_Vault_Test is GenericUnitTest {
    function setUp() public override {
        super.setUp();

        // Default mock to return zero address for any asset
        vm.mockCall(owner, abi.encodeWithSelector(IController.vaultFor.selector), abi.encode(address(0)));
    }

    function testFuzz_shouldReturnZeroAddress_whenNoVaultSet(address asset) public view {
        assertEq(unit.vault(asset), address(0));
    }

    function testFuzz_shouldReturnVault(address asset, address vault) public {
        vm.assume(asset != address(0));
        vm.assume(vault != address(0));

        vm.mockCall(owner, abi.encodeWithSelector(IController.vaultFor.selector, asset), abi.encode(vault));

        vm.expectCall(owner, abi.encodeWithSelector(IController.vaultFor.selector, asset));

        assertEq(unit.vault(asset), vault);
    }
}

contract GenericUnit_SupportsInterface_Test is GenericUnitTest {
    bytes4 constant INTERFACE_ID_ERC165 = 0x01ffc9a7;
    bytes4 constant INTERFACE_ID_ERC20 = 0x36372b07;
    bytes4 constant INTERFACE_ID_ERC7575_SHARE = 0xf815c03d;

    function test_shouldSupportIERC165() public view {
        assertTrue(unit.supportsInterface(INTERFACE_ID_ERC165));
    }

    function test_shouldSupportIERC20() public view {
        assertTrue(unit.supportsInterface(INTERFACE_ID_ERC20));
    }

    function test_shouldSupportIERC7575Share() public view {
        assertTrue(unit.supportsInterface(INTERFACE_ID_ERC7575_SHARE));
    }

    function testFuzz_shouldNotSupportRandomInterface(bytes4 interfaceId) public view {
        vm.assume(interfaceId != INTERFACE_ID_ERC165);
        vm.assume(interfaceId != INTERFACE_ID_ERC20);
        vm.assume(interfaceId != INTERFACE_ID_ERC7575_SHARE);

        assertFalse(unit.supportsInterface(interfaceId));
    }
}
