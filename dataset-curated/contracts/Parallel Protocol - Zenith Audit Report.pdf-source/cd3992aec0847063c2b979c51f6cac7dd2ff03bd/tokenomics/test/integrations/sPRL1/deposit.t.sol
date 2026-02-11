// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";

import "test/Integrations.t.sol";

contract SPRL1_Deposit_Integrations_Test is Integrations_Test {
    function setUp() public override {
        super.setUp();
        sigUtils = new SigUtils(prl.DOMAIN_SEPARATOR());
        vm.startPrank(users.alice.addr);
        prl.approve(address(sprl1), type(uint256).max);
    }

    function test_SPRL1_Deposit() external {
        vm.expectEmit(address(sprl1));
        emit TimeLockPenaltyERC20.Deposited(users.alice.addr, INITIAL_BALANCE);
        sprl1.deposit(INITIAL_BALANCE);
        assertEq(prl.balanceOf(address(sprl1)), INITIAL_BALANCE);
        assertEq(prl.balanceOf(users.alice.addr), 0);
        assertEq(sprl1.balanceOf(users.alice.addr), INITIAL_BALANCE);
    }

    function test_SPRL1_DepositWithPermit() external {
        vm.startPrank(users.alice.addr);
        (uint256 deadline, uint8 v, bytes32 r, bytes32 s) =
            _signPermitData(users.alice.privateKey, address(sprl1), INITIAL_BALANCE, address(prl));

        vm.expectEmit(address(sprl1));
        emit TimeLockPenaltyERC20.Deposited(users.alice.addr, INITIAL_BALANCE);
        sprl1.depositWithPermit(INITIAL_BALANCE, deadline, v, r, s);
        assertEq(prl.balanceOf(address(sprl1)), INITIAL_BALANCE);
        assertEq(prl.balanceOf(users.alice.addr), 0);
        assertEq(sprl1.balanceOf(users.alice.addr), INITIAL_BALANCE);
    }
}
