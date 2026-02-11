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

import {lvlUSD} from "../../../../src/lvlUSD.sol";
import {LevelMintingUtils} from "../LevelMinting.utils.sol";
import {IlvlUSDDefinitions} from "../../../../src/interfaces/IlvlUSDDefinitions.sol";

contract lvlUSDDenylistTest is Test, IlvlUSDDefinitions, LevelMintingUtils {
    lvlUSD internal _lvlusdToken;

    uint256 internal _ownerPrivateKey;
    uint256 internal _newOwnerPrivateKey;
    uint256 internal _minterPrivateKey;
    uint256 internal _newMinterPrivateKey;

    address internal _owner;
    address internal _newOwner;
    address internal _minter;
    address internal _newMinter;
    address internal _denylister;

    address internal _denylisted;

    function setUp() public virtual override {
        _ownerPrivateKey = 0xA11CE;
        _newOwnerPrivateKey = 0xA14CE;
        _minterPrivateKey = 0xB44DE;
        _newMinterPrivateKey = 0xB45DE;

        _owner = vm.addr(_ownerPrivateKey);
        _newOwner = vm.addr(_newOwnerPrivateKey);
        _minter = vm.addr(_minterPrivateKey);
        _newMinter = vm.addr(_newMinterPrivateKey);
        _denylister = _owner;

        _denylisted = vm.addr(0xC0FFEE);

        vm.label(_minter, "minter");
        vm.label(_owner, "owner");
        vm.label(_newMinter, "_newMinter");
        vm.label(_newOwner, "newOwner");

        _lvlusdToken = new lvlUSD(_owner);
        vm.prank(_owner);
        _lvlusdToken.setMinter(_minter);
    }

    function testDenylisterCannotBeRenounced() public {
        vm.startPrank(_owner);
        vm.expectRevert(OperationNotAllowedErr);
        _lvlusdToken.renounceRole(denylisterRole, _owner);
        vm.stopPrank();
        assertEq(_lvlusdToken.owner(), _owner);
        assertNotEq(_lvlusdToken.owner(), address(0));
    }

    function testOnlyDenylisterCanDenylist() public {
        assertEq(_lvlusdToken.denylisted(_denylisted), false);

        vm.prank(_denylister);
        _lvlusdToken.addToDenylist(_denylisted);

        assertEq(_lvlusdToken.denylisted(_denylisted), true);

        vm.prank(_denylisted);
        vm.expectRevert(
            "AccessControl: account 0xf5a5e415061470a8b9137959180901aea72450a4 is missing role 0xd15a633a037a8cb1e45b365d4ebd232aae2a8d891c9de0523b8e2fe68362d066"
        );
        _lvlusdToken.addToDenylist(_minter);
    }

    function testOnlyDenylisterCanRemoveFromDenylist() public {
        assertEq(_lvlusdToken.denylisted(_denylisted), false);

        vm.prank(_denylister);
        _lvlusdToken.addToDenylist(_denylisted);
        assertEq(_lvlusdToken.denylisted(_denylisted), true);

        vm.prank(_denylisted);
        vm.expectRevert(
            "AccessControl: account 0xf5a5e415061470a8b9137959180901aea72450a4 is missing role 0xd15a633a037a8cb1e45b365d4ebd232aae2a8d891c9de0523b8e2fe68362d066"
        );
        _lvlusdToken.removeFromDenylist(_minter);

        vm.prank(_denylister);
        _lvlusdToken.removeFromDenylist(_denylisted);
        assertEq(_lvlusdToken.denylisted(_denylisted), false);
    }

    function cannotAddOwnerToDenylist() public {
        vm.prank(_denylister);
        vm.expectRevert(IsOwnerErr);
        _lvlusdToken.addToDenylist(_owner);
    }

    function testDenylistPreventMinting() public {
        assertEq(_lvlusdToken.denylisted(_denylisted), false);

        vm.prank(_denylister);
        _lvlusdToken.addToDenylist(_denylisted);

        vm.prank(_minter);
        vm.expectRevert(DenylistedErr);
        _lvlusdToken.mint(_denylisted, 100);
    }

    function testDenylistPreventsTransfersFrom() public {
        vm.prank(_minter);
        _lvlusdToken.mint(_denylisted, 100);

        assertEq(_lvlusdToken.balanceOf(_denylisted), 100);

        vm.prank(_denylister);
        _lvlusdToken.addToDenylist(_denylisted);

        vm.prank(_denylisted);
        vm.expectRevert(DenylistedErr);
        _lvlusdToken.transfer(_owner, 100);
    }

    function testDenylistPreventsTransfersTo() public {
        vm.prank(_minter);
        _lvlusdToken.mint(_minter, 100);

        assertEq(_lvlusdToken.balanceOf(_minter), 100);

        vm.prank(_denylister);
        _lvlusdToken.addToDenylist(_denylisted);

        vm.prank(_minter);
        vm.expectRevert(DenylistedErr);
        _lvlusdToken.transfer(_denylisted, 100);
    }
}
