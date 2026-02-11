// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;
import {StableWrapper} from "../../src/StableWrapper.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Base} from "./Base.t.sol";

/************************************************
 *  DEPOSIT TESTS
 ***********************************************/
contract StableWrapperDepositTest is Base {
    /************************************************
     *  DEPOSIT TO VAULT
     ***********************************************/
    function test_RevertIfAmountIsZero_Vault(address _depositor) public {
        vm.assume(_depositor != address(0));
        vm.startPrank(keeper);
        vm.expectRevert(StableWrapper.AmountMustBeGreaterThanZero.selector);
        stableWrapper.depositToVault(_depositor, 0);
        vm.stopPrank();
    }

    function test_RevertIfCallerIsNotTheKeeper_Vault(
        address _caller,
        address _depositor,
        uint256 _amount
    ) public {
        vm.assume(_amount != 0);
        vm.assume(_caller != keeper);
        vm.assume(_depositor != address(0));
        vm.assume(_caller != address(0));
        vm.startPrank(_caller);
        vm.expectRevert(StableWrapper.NotKeeper.selector);
        stableWrapper.depositToVault(_depositor, _amount);
        vm.stopPrank();
    }

    function test_RevertIfInsufficientApproval_Vault(uint256 _amount) public {
        vm.assume(_amount != 0);
        vm.startPrank(keeper);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector,
                address(stableWrapper),
                0,
                _amount
            )
        );
        stableWrapper.depositToVault(vm.addr(1001), _amount);
        vm.stopPrank();
    }

    function test_SuccessfullDepositToVault_Vault(uint256 _amount) public {
        vm.assume(_amount != 0);
        vm.assume(_amount <= startingBal);
        vm.startPrank(keeper);
        stableWrapper.depositToVault(depositor1, _amount);
        vm.stopPrank();

        assertEq(usdc.balanceOf(depositor1), startingBal - _amount);
        assertEq(stableWrapper.balanceOf(keeper), _amount);
        assertEq(stableWrapper.totalSupply(), _amount);
        assertEq(usdc.balanceOf(address(stableWrapper)), _amount);
    }

    /************************************************
     * REGULAR DEPOSIT
     ***********************************************/
    function test_RevertIfAmountIsZero_Regular(address _depositor) public {
        vm.assume(_depositor != address(0));
        vm.prank(owner);
        stableWrapper.setAllowIndependence(true);

        vm.startPrank(depositor1);
        vm.expectRevert(StableWrapper.AmountMustBeGreaterThanZero.selector);
        stableWrapper.deposit(_depositor, 0);
        vm.stopPrank();
    }

    function test_RevertIfInsufficientApproval_Regular(uint256 _amount) public {
        vm.assume(_amount != 0);
        vm.prank(owner);
        stableWrapper.setAllowIndependence(true);
        vm.startPrank(vm.addr(1001));
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector,
                address(stableWrapper),
                0,
                _amount
            )
        );
        stableWrapper.deposit(vm.addr(1001), _amount);
        vm.stopPrank();
    }

    function test_SuccessfullDeposit_Regular(uint256 _amount) public {
        vm.assume(_amount != 0);
        vm.assume(_amount <= startingBal);
        vm.prank(owner);
        stableWrapper.setAllowIndependence(true);
        vm.startPrank(depositor1);
        stableWrapper.deposit(depositor1, _amount);
        vm.stopPrank();

        assertEq(usdc.balanceOf(depositor1), startingBal - _amount);
        assertEq(stableWrapper.balanceOf(depositor1), _amount);
        assertEq(stableWrapper.balanceOf(owner), 0);
        assertEq(stableWrapper.totalSupply(), _amount);
        assertEq(usdc.balanceOf(address(stableWrapper)), _amount);
    }

    function test_SuccessfullDepositForOtherAddy_Regular(
        uint256 _amount
    ) public {
        vm.assume(_amount != 0);
        vm.assume(_amount <= startingBal);
        vm.prank(owner);
        stableWrapper.setAllowIndependence(true);
        vm.startPrank(depositor2);
        stableWrapper.deposit(depositor1, _amount);
        vm.stopPrank();

        assertEq(usdc.balanceOf(depositor2), startingBal - _amount);
        assertEq(usdc.balanceOf(depositor1), startingBal);
        assertEq(stableWrapper.balanceOf(depositor1), _amount);
        assertEq(stableWrapper.balanceOf(owner), 0);
        assertEq(stableWrapper.totalSupply(), _amount);
        assertEq(usdc.balanceOf(address(stableWrapper)), _amount);
    }
}
