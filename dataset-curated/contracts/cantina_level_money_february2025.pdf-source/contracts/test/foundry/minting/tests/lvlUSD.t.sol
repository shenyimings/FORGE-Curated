// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19;

/*
    solhint-disable private-vars-leading-underscore
    solhint-disable contract-name-camelcase
*/

import {stdStorage, StdStorage, Test} from "forge-std/Test.sol";
import {SigUtils} from "../../../utils/SigUtils.sol";
import {Vm} from "forge-std/Vm.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/access/IAccessControl.sol";
import {lvlUSD} from "../../../../src/lvlUSD.sol";
import {LevelMintingUtils} from "../LevelMinting.utils.sol";
import "../../../mocks/MockSlasher.sol";
import {IlvlUSDDefinitions} from "../../../../src/interfaces/IlvlUSDDefinitions.sol";
import "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

contract lvlUSDTest is Test, IlvlUSDDefinitions, LevelMintingUtils {
    lvlUSD internal _lvlusdToken;

    uint256 internal _ownerPrivateKey;
    uint256 internal _newOwnerPrivateKey;
    uint256 internal _minterPrivateKey;
    uint256 internal _newMinterPrivateKey;
    uint256 internal _burnerPrivateKey;
    uint256 internal _otherBurnerPrivateKey;

    address internal _owner;
    address internal _newOwner;
    address internal _minter;
    address internal _newMinter;
    address internal _burner;
    address internal _otherBurner;
    address internal _burnerContract;

    function setUp() public virtual override {
        _ownerPrivateKey = 0xA11CE;
        _newOwnerPrivateKey = 0xA14CE;
        _minterPrivateKey = 0xB44DE;
        _newMinterPrivateKey = 0xB45DE;
        _burnerPrivateKey = 0xC55EE;
        _otherBurnerPrivateKey = 0xC56EE;

        _owner = vm.addr(_ownerPrivateKey);
        _newOwner = vm.addr(_newOwnerPrivateKey);
        _minter = vm.addr(_minterPrivateKey);
        _newMinter = vm.addr(_newMinterPrivateKey);
        _burner = vm.addr(_burnerPrivateKey);
        _otherBurner = vm.addr(_otherBurnerPrivateKey);

        vm.label(_minter, "minter");
        vm.label(_owner, "owner");
        vm.label(_newMinter, "_newMinter");
        vm.label(_newOwner, "newOwner");
        vm.label(_burner, "burner");
        vm.label(_otherBurner, "otherBurner");

        _lvlusdToken = new lvlUSD(_owner);
        vm.startPrank(_owner);
        _lvlusdToken.setMinter(_minter);
        vm.stopPrank();

        vm.startPrank(_minter);
        _lvlusdToken.mint(_burner, 100);
        _lvlusdToken.mint(_otherBurner, 100);
        vm.stopPrank();

        _burnerContract = address(new MockSlasher());
    }

    function testCorrectInitialConfig() public {
        assertEq(_lvlusdToken.owner(), _owner);
        assertEq(_lvlusdToken.minter(), _minter);
    }

    function testCantInitWithNoOwner() public {
        vm.expectRevert(ZeroAddressExceptionErr);
        new lvlUSD(address(0));
    }

    function testOwnershipCannotBeRenounced() public {
        vm.startPrank(_owner);
        vm.expectRevert(OperationNotAllowedErr);
        _lvlusdToken.renounceRole(adminRole, _owner);
        vm.stopPrank();
        assertEq(_lvlusdToken.owner(), _owner);
        assertNotEq(_lvlusdToken.owner(), address(0));
    }

    function testOwnershipTransferRequiresTwoSteps() public {
        vm.prank(_owner);
        _lvlusdToken.transferAdmin(_newOwner);
        assertEq(_lvlusdToken.owner(), _owner);
        assertNotEq(_lvlusdToken.owner(), _newOwner);
    }

    function testCanTransferAdmin() public {
        vm.prank(_owner);
        _lvlusdToken.transferAdmin(_newOwner);
        vm.prank(_newOwner);
        _lvlusdToken.acceptAdmin();
        assertEq(_lvlusdToken.owner(), _newOwner);
        assertNotEq(_lvlusdToken.owner(), _owner);
    }

    function testCanCancelOwnershipChange() public {
        vm.startPrank(_owner);
        _lvlusdToken.transferAdmin(_newOwner);
        _lvlusdToken.transferAdmin(address(0));
        vm.stopPrank();

        vm.prank(_newOwner);
        vm.expectRevert();
        _lvlusdToken.acceptAdmin();
        assertEq(_lvlusdToken.owner(), _owner);
        assertNotEq(_lvlusdToken.owner(), _newOwner);
    }

    function testNewOwnerCanPerformOwnerActions() public {
        vm.prank(_owner);
        _lvlusdToken.transferAdmin(_newOwner);
        vm.startPrank(_newOwner);
        _lvlusdToken.acceptAdmin();
        _lvlusdToken.setMinter(_newMinter);
        vm.stopPrank();
        assertEq(_lvlusdToken.minter(), _newMinter);
        assertNotEq(_lvlusdToken.minter(), _minter);
    }

    function testOnlyOwnerCanSetMinter() public {
        vm.startPrank(_newOwner);
        vm.expectRevert(
            "AccessControl: account 0x15ad6f3eb96192d0013eae1890fd5d0472f601d2 is missing role 0x0000000000000000000000000000000000000000000000000000000000000000"
        );
        _lvlusdToken.setMinter(_newMinter);
        vm.stopPrank();

        assertEq(_lvlusdToken.minter(), _minter);
    }

    function testOwnerCantMint() public {
        vm.prank(_owner);
        vm.expectRevert(OnlyMinterErr);
        _lvlusdToken.mint(_newMinter, 100);
    }

    function testMinterCanMint() public {
        assertEq(_lvlusdToken.balanceOf(_newMinter), 0);
        vm.prank(_minter);
        _lvlusdToken.mint(_newMinter, 100);
        assertEq(_lvlusdToken.balanceOf(_newMinter), 100);
    }

    function testMinterCantMintToZeroAddress() public {
        vm.prank(_minter);
        vm.expectRevert("ERC20: mint to the zero address");
        _lvlusdToken.mint(address(0), 100);
    }

    function testNewMinterCanMint() public {
        assertEq(_lvlusdToken.balanceOf(_newMinter), 0);
        vm.prank(_owner);
        _lvlusdToken.setMinter(_newMinter);
        vm.prank(_newMinter);
        _lvlusdToken.mint(_newMinter, 100);
        assertEq(_lvlusdToken.balanceOf(_newMinter), 100);
    }

    function testOldMinterCantMint() public {
        assertEq(_lvlusdToken.balanceOf(_newMinter), 0);
        vm.prank(_owner);
        _lvlusdToken.setMinter(_newMinter);
        vm.prank(_minter);
        vm.expectRevert(OnlyMinterErr);
        _lvlusdToken.mint(_newMinter, 100);
        assertEq(_lvlusdToken.balanceOf(_newMinter), 0);
    }

    function testOldOwnerCanttransferAdmin() public {
        vm.prank(_owner);
        _lvlusdToken.transferAdmin(_newOwner);
        vm.prank(_newOwner);
        _lvlusdToken.acceptAdmin();
        assertNotEq(_lvlusdToken.owner(), _owner);
        assertEq(_lvlusdToken.owner(), _newOwner);

        vm.startPrank(_owner);
        vm.expectRevert(
            "AccessControl: account 0xe05fcc23807536bee418f142d19fa0d21bb0cff7 is missing role 0x0000000000000000000000000000000000000000000000000000000000000000"
        );
        _lvlusdToken.transferAdmin(_newMinter);
        vm.stopPrank();

        assertEq(_lvlusdToken.owner(), _newOwner);
    }

    function testOldOwnerCantSetMinter() public {
        vm.prank(_owner);
        _lvlusdToken.transferAdmin(_newOwner);
        vm.prank(_newOwner);
        _lvlusdToken.acceptAdmin();
        assertNotEq(_lvlusdToken.owner(), _owner);
        assertEq(_lvlusdToken.owner(), _newOwner);

        vm.startPrank(_owner);
        vm.expectRevert(
            "AccessControl: account 0xe05fcc23807536bee418f142d19fa0d21bb0cff7 is missing role 0x0000000000000000000000000000000000000000000000000000000000000000"
        );
        _lvlusdToken.setMinter(_newMinter);
        vm.stopPrank();

        assertEq(_lvlusdToken.minter(), _minter);
    }

    function testBurnerCanBurn() public {
        vm.prank(_burner);
        _lvlusdToken.burn(51);

        assertEq(_lvlusdToken.balanceOf(_burner), 49);
    }

    function testOtherBurnerCanBurn() public {
        assertEq(_lvlusdToken.balanceOf(_otherBurner), 100);

        vm.prank(_otherBurner);
        _lvlusdToken.burn(100);
        assertEq(_lvlusdToken.balanceOf(_otherBurner), 0);
    }

    function testFunctionCanBurn() public {
        vm.prank(_minter);
        _lvlusdToken.mint(_burnerContract, 100);
        assertEq(_lvlusdToken.balanceOf(_burnerContract), 100);

        MockSlasher burner = MockSlasher(_burnerContract);
        burner.burn(100, _lvlusdToken);
        assertEq(_lvlusdToken.balanceOf(_burnerContract), 0);
    }

    function testFunctionRevertsIfNoBalance() public {
        MockSlasher burner = MockSlasher(_burnerContract);
        vm.expectRevert("ERC20: burn amount exceeds balance");
        burner.burn(1, _lvlusdToken);
    }

    // Ensure that even if an address approved the burner contract
    // to transfer tokens, the burner contract cannot since it does
    // not own them directly.
    function testFunctionCannotBurnDelegated() public {
        vm.prank(_minter);
        _lvlusdToken.mint(_newMinter, 100);
        assertEq(_lvlusdToken.balanceOf(_newMinter), 100);

        vm.prank(_newMinter);
        _lvlusdToken.approve(_burnerContract, 100);

        MockSlasher burner = MockSlasher(_burnerContract);

        vm.expectRevert("ERC20: burn amount exceeds balance");
        burner.burn(100, _lvlusdToken);
    }
}
