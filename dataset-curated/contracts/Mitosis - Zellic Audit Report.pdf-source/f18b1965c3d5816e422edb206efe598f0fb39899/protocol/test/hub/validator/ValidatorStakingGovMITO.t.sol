// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { console } from '@std/console.sol';

import { WETH } from '@solady/tokens/WETH.sol';

import { IVotes } from '@oz/governance/utils/IVotes.sol';

import { ValidatorStakingGovMITO } from '../../../src/hub/validator/ValidatorStakingGovMITO.sol';
import { IValidatorManager } from '../../../src/interfaces/hub/validator/IValidatorManager.sol';
import { IValidatorStakingHub } from '../../../src/interfaces/hub/validator/IValidatorStakingHub.sol';
import { ISudoVotes } from '../../../src/interfaces/lib/ISudoVotes.sol';
import { MockContract } from '../../util/MockContract.sol';
import { Toolkit } from '../../util/Toolkit.sol';

contract ValidatorStakingGovMITOTest is Toolkit {
  address owner = makeAddr('owner');
  address val = makeAddr('val');
  address user1 = makeAddr('user1');
  address user2 = makeAddr('user2');
  address delegationManager = makeAddr('delegationManager');

  WETH weth;
  MockContract manager;
  MockContract hub;
  ValidatorStakingGovMITO vault;

  uint48 UNSTAKING_COOLDOWN = 1 days;
  uint48 REDELEGATION_COOLDOWN = 1 days;

  function setUp() public {
    // use real time to avoid arithmatic overflow on withdrawalPeriod calculation
    vm.warp(1743061332);

    weth = new WETH();
    manager = new MockContract();
    hub = new MockContract();
    vault = ValidatorStakingGovMITO(
      payable(
        _proxy(
          address(
            new ValidatorStakingGovMITO(
              address(weth), //
              IValidatorManager(address(manager)),
              IValidatorStakingHub(address(hub))
            )
          ),
          abi.encodeCall(
            ValidatorStakingGovMITO.initialize,
            (
              owner, //
              100,
              100,
              UNSTAKING_COOLDOWN,
              REDELEGATION_COOLDOWN
            )
          )
        )
      )
    );
  }

  function test_delegate() public {
    vm.expectRevert(_errNotSupported());
    vm.prank(user1);
    vault.delegate(user1);
  }

  function test_delegateBySig() public {
    vm.expectRevert(_errNotSupported());
    vm.prank(user1);
    vault.delegateBySig(user1, 0, 0, 0, bytes32(0), bytes32(0));
  }

  function test_setDelegationManager() public {
    vm.expectRevert(_errUnauthorized());
    vm.prank(user1);
    vault.setDelegationManager(delegationManager);

    vm.prank(owner);
    vm.expectEmit();
    emit ISudoVotes.DelegationManagerSet(address(0), delegationManager);
    vault.setDelegationManager(delegationManager);

    assertEq(vault.delegationManager(), delegationManager);
  }

  function test_sudoDelegate() public {
    test_setDelegationManager();

    manager.setRet(abi.encodeCall(IValidatorManager.isValidator, (val)), false, abi.encode(true));

    // user1: stake 100
    _mintAndApprove(user1, 100);
    vm.prank(user1);
    vault.stake(val, user1, 100);

    vm.expectRevert(_errUnauthorized());
    vm.prank(user1);
    vault.sudoDelegate(user1, user1);

    vm.prank(delegationManager);
    vm.expectEmit();
    emit IVotes.DelegateChanged(user1, address(0), user1);
    vm.expectEmit();
    emit IVotes.DelegateVotesChanged(user1, 0, 100);
    vault.sudoDelegate(user1, user1);
  }

  function test_stake() public {
    test_setDelegationManager();

    manager.setRet(abi.encodeCall(IValidatorManager.isValidator, (val)), false, abi.encode(true));

    // user1: without delegate
    _mintAndApprove(user1, 100);

    // user2: with delegate
    _mintAndApprove(user2, 100);

    vm.prank(delegationManager);
    vault.sudoDelegate(user2, user2);

    // user1: stake
    vm.prank(user1);
    vault.stake(val, user1, 100);

    // user2: stake & check voting power transfer
    vm.prank(user2);
    vm.expectEmit();
    emit IVotes.DelegateVotesChanged(user2, 0, 100);
    vault.stake(val, user2, 100);

    vm.warp(_now() + 1);
    assertEq(vault.getPastTotalSupply(_now() - 1), 0);
    assertEq(vault.getVotes(user1), 0);
    assertEq(vault.getVotes(user2), 100);

    // user1: delegate later

    vm.prank(delegationManager);
    vault.sudoDelegate(user1, user1);

    assertEq(vault.getVotes(user1), 100);
  }

  function test_stake_nonTransferable() public {
    _mintAndApprove(user1, 100);

    vm.prank(user1);
    vm.expectRevert(ValidatorStakingGovMITO.ValidatorStakingGovMITO__NonTransferable.selector);
    vault.stake(val, user2, 100);
  }

  function test_requestUnstake() public {
    test_setDelegationManager();

    manager.setRet(abi.encodeCall(IValidatorManager.isValidator, (val)), false, abi.encode(true));

    _mintAndApprove(user1, 200);

    vm.prank(user1);
    vault.stake(val, user1, 200);

    vm.prank(user1);
    vault.requestUnstake(val, user1, 100);

    vm.prank(delegationManager);
    vault.sudoDelegate(user1, user1);

    vm.warp(_now() + 1);
    assertEq(vault.getVotes(user1), 200); // 100 + 100
    assertEq(vault.getPastTotalSupply(_now() - 1), 0);
  }

  function test_requestUnstake_nonTransferable() public {
    _mintAndApprove(user1, 200);

    vm.prank(user1);
    vm.expectRevert(ValidatorStakingGovMITO.ValidatorStakingGovMITO__NonTransferable.selector);
    vault.requestUnstake(val, user2, 100);
  }

  function test_claimUnstake() public {
    test_requestUnstake(); // now = unstake request time + 1

    vm.warp(_now() + UNSTAKING_COOLDOWN - 1);

    vm.prank(user1);
    vm.expectEmit();
    emit IVotes.DelegateVotesChanged(user1, 200, 100);
    uint256 claimed = vault.claimUnstake(user1);

    vm.warp(_now() + 1);
    assertEq(claimed, 100);
    assertEq(vault.getVotes(user1), 100);
    assertEq(vault.getPastTotalSupply(_now() - 1), 0);
  }

  function _mintAndApprove(address user, uint256 amount) internal {
    vm.deal(user, amount);
    vm.prank(user);
    weth.deposit{ value: amount }();

    vm.prank(user);
    weth.approve(address(vault), amount);
  }
}
