// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { Test } from "forge-std/Test.sol";

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { GenericUnitL2 } from "../../../src/unit/GenericUnitL2.sol";

abstract contract GenericUnitL2Test is Test {
    GenericUnitL2 unit;

    address owner = makeAddr("owner");

    function setUp() public virtual {
        unit = new GenericUnitL2(owner, "name", "symbol");
    }
}

contract GenericUnitL2_Constructor_Test is GenericUnitL2Test {
    function test_shouldSetsInitialValues() public {
        address otherOwner = makeAddr("otherOwner");
        unit = new GenericUnitL2(otherOwner, "name", "symbol");

        assertEq(unit.owner(), otherOwner);
        assertEq(unit.name(), "name");
        assertEq(unit.symbol(), "symbol");
        assertEq(unit.decimals(), 18);
        assertEq(unit.totalSupply(), 0);
    }

    function test_shouldRevert_whenZeroOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        unit = new GenericUnitL2(address(0), "name", "symbol");
    }
}

contract GenericUnitL2_SupportsInterface_Test is GenericUnitL2Test {
    bytes4 constant INTERFACE_ID_ERC165 = 0x01ffc9a7;
    bytes4 constant INTERFACE_ID_ERC20 = 0x36372b07;

    function test_shouldSupportIERC165() public view {
        assertTrue(unit.supportsInterface(INTERFACE_ID_ERC165));
    }

    function test_shouldSupportIERC20() public view {
        assertTrue(unit.supportsInterface(INTERFACE_ID_ERC20));
    }

    function testFuzz_shouldNotSupportRandomInterface(bytes4 interfaceId) public view {
        vm.assume(interfaceId != INTERFACE_ID_ERC165);
        vm.assume(interfaceId != INTERFACE_ID_ERC20);

        assertFalse(unit.supportsInterface(interfaceId));
    }
}
