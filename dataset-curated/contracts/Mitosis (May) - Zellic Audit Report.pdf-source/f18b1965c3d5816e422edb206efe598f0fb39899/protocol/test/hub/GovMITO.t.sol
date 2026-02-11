// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { console } from '@std/console.sol';
import { Vm } from '@std/Vm.sol';

import { IVotes } from '@oz/governance/utils/IVotes.sol';
import { ERC1967Proxy } from '@oz/proxy/ERC1967/ERC1967Proxy.sol';

import { GovMITO } from '../../src/hub/GovMITO.sol';
import { IGovMITO } from '../../src/interfaces/hub/IGovMITO.sol';
import { ISudoVotes } from '../../src/interfaces/lib/ISudoVotes.sol';
import { LibQueue } from '../../src/lib/LibQueue.sol';
import { StdError } from '../../src/lib/StdError.sol';
import { Toolkit } from '../util/Toolkit.sol';

contract GovMITOTest is Toolkit {
  GovMITO govMITO;

  address immutable owner = makeAddr('owner');
  address immutable minter = makeAddr('minter');
  address immutable user1 = makeAddr('user1');
  address immutable user2 = makeAddr('user2');
  address immutable module = makeAddr('module');
  address immutable delegationManager = makeAddr('delegationManager');

  uint48 constant WITHDRAWAL_PERIOD = 21 days;

  function setUp() public {
    // use real time to avoid arithmatic overflow on withdrawalPeriod calculation
    vm.warp(1743061332);
    govMITO =
      GovMITO(payable(_proxy(address(new GovMITO()), abi.encodeCall(GovMITO.initialize, (owner, WITHDRAWAL_PERIOD)))));

    vm.prank(owner);
    govMITO.setMinter(minter);
  }

  function test_init() public view {
    assertEq(govMITO.name(), 'Mitosis Governance Token');
    assertEq(govMITO.symbol(), 'gMITO');
    assertEq(govMITO.decimals(), 18);

    assertEq(govMITO.owner(), owner);
    assertEq(govMITO.minter(), minter);
    assertEq(govMITO.delegationManager(), address(0));
    assertEq(govMITO.withdrawalPeriod(), WITHDRAWAL_PERIOD);
  }

  function test_mint() public {
    payable(minter).transfer(100);
    vm.prank(minter);
    govMITO.mint{ value: 100 }(user1);
    assertEq(govMITO.balanceOf(user1), 100);
  }

  function test_mint_NotMinter() public {
    payable(user1).transfer(100);
    vm.prank(user1);
    vm.expectRevert(_errUnauthorized());
    govMITO.mint{ value: 100 }(user1);
  }

  function test_withdraw_basic() public {
    payable(minter).transfer(100);
    vm.prank(minter);
    govMITO.mint{ value: 100 }(user1);

    vm.startPrank(user1);

    uint256 requestedAt = block.timestamp;
    govMITO.requestWithdraw(user1, 30);
    assertEq(user1.balance, 0);
    assertEq(govMITO.balanceOf(user1), 70);
    assertEq(govMITO.previewClaimWithdraw(user1), 0);

    vm.warp(requestedAt + WITHDRAWAL_PERIOD - 1);
    assertEq(govMITO.previewClaimWithdraw(user1), 0);

    vm.expectRevert(_errNothingToClaim());
    uint256 claimed = govMITO.claimWithdraw(user1);

    vm.warp(requestedAt + WITHDRAWAL_PERIOD);
    assertEq(govMITO.previewClaimWithdraw(user1), 30);

    claimed = govMITO.claimWithdraw(user1);
    assertEq(claimed, 30);
    assertEq(user1.balance, 30);
    assertEq(govMITO.balanceOf(user1), 70);
    assertEq(govMITO.previewClaimWithdraw(user1), 0);

    requestedAt = block.timestamp;
    govMITO.requestWithdraw(user1, 70);
    assertEq(user1.balance, 30);
    assertEq(govMITO.balanceOf(user1), 0);
    assertEq(govMITO.previewClaimWithdraw(user1), 0);

    vm.warp(requestedAt + WITHDRAWAL_PERIOD - 1);
    assertEq(govMITO.previewClaimWithdraw(user1), 0);

    vm.expectRevert(_errNothingToClaim());
    claimed = govMITO.claimWithdraw(user1);

    vm.warp(requestedAt + WITHDRAWAL_PERIOD);
    assertEq(govMITO.previewClaimWithdraw(user1), 70);

    claimed = govMITO.claimWithdraw(user1);
    assertEq(claimed, 70);
    assertEq(user1.balance, 100);
    assertEq(govMITO.balanceOf(user1), 0);
    assertEq(govMITO.previewClaimWithdraw(user1), 0);

    vm.stopPrank();
  }

  function test_withdraw_requestTwiceAndClaimOnce() public {
    payable(minter).transfer(100);
    vm.prank(minter);
    govMITO.mint{ value: 100 }(user1);

    vm.startPrank(user1);

    uint256 requestedAt = block.timestamp;
    govMITO.requestWithdraw(user1, 30);
    assertEq(user1.balance, 0);
    assertEq(govMITO.balanceOf(user1), 70);
    assertEq(govMITO.previewClaimWithdraw(user1), 0);

    vm.warp(requestedAt + WITHDRAWAL_PERIOD / 2);
    assertEq(govMITO.previewClaimWithdraw(user1), 0);

    govMITO.requestWithdraw(user1, 50);
    assertEq(user1.balance, 0);
    assertEq(govMITO.balanceOf(user1), 20);
    assertEq(govMITO.previewClaimWithdraw(user1), 0);

    vm.warp(requestedAt + WITHDRAWAL_PERIOD / 2 + WITHDRAWAL_PERIOD);
    assertEq(govMITO.previewClaimWithdraw(user1), 80);

    uint256 claimed = govMITO.claimWithdraw(user1);
    assertEq(claimed, 80);
    assertEq(user1.balance, 80);
    assertEq(govMITO.balanceOf(user1), 20);
    assertEq(govMITO.previewClaimWithdraw(user1), 0);

    vm.stopPrank();
  }

  function test_withdraw_requestTwiceAndClaimTwice() public {
    payable(minter).transfer(100);
    vm.prank(minter);
    govMITO.mint{ value: 100 }(user1);

    vm.startPrank(user1);

    uint256 requestedAt = block.timestamp;
    govMITO.requestWithdraw(user1, 30);
    assertEq(user1.balance, 0);
    assertEq(govMITO.balanceOf(user1), 70);
    assertEq(govMITO.previewClaimWithdraw(user1), 0);

    vm.warp(requestedAt + WITHDRAWAL_PERIOD / 2);
    assertEq(govMITO.previewClaimWithdraw(user1), 0);

    govMITO.requestWithdraw(user1, 50);
    assertEq(user1.balance, 0);
    assertEq(govMITO.balanceOf(user1), 20);
    assertEq(govMITO.previewClaimWithdraw(user1), 0);

    vm.warp(requestedAt + WITHDRAWAL_PERIOD);
    assertEq(govMITO.previewClaimWithdraw(user1), 30);

    uint256 claimed = govMITO.claimWithdraw(user1);
    assertEq(claimed, 30);
    assertEq(user1.balance, 30);
    assertEq(govMITO.balanceOf(user1), 20);
    assertEq(govMITO.previewClaimWithdraw(user1), 0);

    vm.warp(requestedAt + WITHDRAWAL_PERIOD / 2 + WITHDRAWAL_PERIOD - 1);
    assertEq(govMITO.previewClaimWithdraw(user1), 0);

    vm.expectRevert(_errNothingToClaim());
    claimed = govMITO.claimWithdraw(user1);

    vm.warp(requestedAt + WITHDRAWAL_PERIOD / 2 + WITHDRAWAL_PERIOD);
    assertEq(govMITO.previewClaimWithdraw(user1), 50);

    claimed = govMITO.claimWithdraw(user1);
    assertEq(claimed, 50);
    assertEq(user1.balance, 80);
    assertEq(govMITO.balanceOf(user1), 20);
    assertEq(govMITO.previewClaimWithdraw(user1), 0);

    vm.stopPrank();
  }

  function test_withdraw_requestAfterClaimable() public {
    payable(minter).transfer(100);
    vm.prank(minter);
    govMITO.mint{ value: 100 }(user1);

    vm.startPrank(user1);

    uint256 requestedAt = block.timestamp;
    govMITO.requestWithdraw(user1, 30);
    assertEq(user1.balance, 0);
    assertEq(govMITO.balanceOf(user1), 70);
    assertEq(govMITO.previewClaimWithdraw(user1), 0);

    vm.warp(requestedAt + WITHDRAWAL_PERIOD);
    assertEq(govMITO.previewClaimWithdraw(user1), 30);

    govMITO.requestWithdraw(user1, 50);
    assertEq(user1.balance, 0);
    assertEq(govMITO.balanceOf(user1), 20);
    assertEq(govMITO.previewClaimWithdraw(user1), 30);

    vm.warp(requestedAt + WITHDRAWAL_PERIOD * 2 - 1);
    assertEq(govMITO.previewClaimWithdraw(user1), 30);

    uint256 claimed = govMITO.claimWithdraw(user1);
    assertEq(claimed, 30);
    assertEq(user1.balance, 30);
    assertEq(govMITO.balanceOf(user1), 20);
    assertEq(govMITO.previewClaimWithdraw(user1), 0);

    vm.warp(requestedAt + WITHDRAWAL_PERIOD * 2);
    assertEq(govMITO.previewClaimWithdraw(user1), 50);

    claimed = govMITO.claimWithdraw(user1);
    assertEq(claimed, 50);
    assertEq(user1.balance, 80);
    assertEq(govMITO.balanceOf(user1), 20);
    assertEq(govMITO.previewClaimWithdraw(user1), 0);

    vm.stopPrank();
  }

  function test_withdraw_severalUsers() public {
    payable(minter).transfer(100);
    vm.startPrank(minter);
    govMITO.mint{ value: 50 }(user1);
    govMITO.mint{ value: 50 }(user2);
    vm.stopPrank();

    uint256 requestedAt = block.timestamp;

    vm.prank(user1);
    govMITO.requestWithdraw(user1, 30);
    assertEq(user1.balance, 0);
    assertEq(govMITO.balanceOf(user1), 20);
    assertEq(govMITO.previewClaimWithdraw(user1), 0);

    vm.prank(user2);
    govMITO.requestWithdraw(user2, 40);
    assertEq(user2.balance, 0);
    assertEq(govMITO.balanceOf(user2), 10);
    assertEq(govMITO.previewClaimWithdraw(user2), 0);

    vm.warp(requestedAt + WITHDRAWAL_PERIOD);
    assertEq(govMITO.previewClaimWithdraw(user1), 30);
    assertEq(govMITO.previewClaimWithdraw(user2), 40);

    vm.prank(user1);
    uint256 claimed = govMITO.claimWithdraw(user1);
    assertEq(claimed, 30);
    assertEq(user1.balance, 30);
    assertEq(user2.balance, 0);
    assertEq(govMITO.balanceOf(user1), 20);
    assertEq(govMITO.balanceOf(user2), 10);
    assertEq(govMITO.previewClaimWithdraw(user1), 0);
    assertEq(govMITO.previewClaimWithdraw(user2), 40);

    vm.prank(user2);
    claimed = govMITO.claimWithdraw(user2);
    assertEq(claimed, 40);
    assertEq(user1.balance, 30);
    assertEq(user2.balance, 40);
    assertEq(govMITO.balanceOf(user1), 20);
    assertEq(govMITO.balanceOf(user2), 10);
    assertEq(govMITO.previewClaimWithdraw(user1), 0);
    assertEq(govMITO.previewClaimWithdraw(user2), 0);
  }

  function test_withdraw_differentReceiver() public {
    payable(minter).transfer(100);
    vm.prank(minter);
    govMITO.mint{ value: 100 }(user1);

    uint256 requestedAt = block.timestamp;
    vm.prank(user1);
    govMITO.requestWithdraw(user2, 30);
    assertEq(user1.balance, 0);
    assertEq(user2.balance, 0);
    assertEq(govMITO.balanceOf(user1), 70);
    assertEq(govMITO.previewClaimWithdraw(user2), 0);

    vm.warp(requestedAt + WITHDRAWAL_PERIOD);
    assertEq(govMITO.previewClaimWithdraw(user2), 30);

    vm.prank(user2);
    uint256 claimed = govMITO.claimWithdraw(user2);
    assertEq(claimed, 30);
    assertEq(user1.balance, 0);
    assertEq(user2.balance, 30);
    assertEq(govMITO.balanceOf(user1), 70);
    assertEq(govMITO.previewClaimWithdraw(user2), 0);
  }

  function test_withdraw_anyoneCanClaim() public {
    payable(minter).transfer(100);
    vm.prank(minter);
    govMITO.mint{ value: 100 }(user1);

    uint256 requestedAt = block.timestamp;
    vm.prank(user1);
    govMITO.requestWithdraw(user1, 30);
    assertEq(user1.balance, 0);
    assertEq(govMITO.balanceOf(user1), 70);
    assertEq(govMITO.previewClaimWithdraw(user1), 0);

    vm.warp(requestedAt + WITHDRAWAL_PERIOD);
    assertEq(govMITO.previewClaimWithdraw(user1), 30);

    vm.prank(user2);
    uint256 claimed = govMITO.claimWithdraw(user1);
    assertEq(claimed, 30);
    assertEq(user1.balance, 30);
    assertEq(govMITO.balanceOf(user1), 70);
    assertEq(govMITO.previewClaimWithdraw(user1), 0);
  }

  function test_withdraw_ERC20InsufficientBalance() public {
    payable(minter).transfer(100);
    vm.prank(minter);
    govMITO.mint{ value: 100 }(user1);

    vm.startPrank(user1);

    govMITO.requestWithdraw(user1, 30);
    assertEq(govMITO.previewClaimWithdraw(user1), 0);

    vm.expectRevert();
    govMITO.requestWithdraw(user1, 71);

    vm.stopPrank();
  }

  function test_whiteListedSender() public {
    payable(minter).transfer(200);
    vm.startPrank(minter);
    govMITO.mint{ value: 100 }(user1);
    assertEq(govMITO.balanceOf(user1), 100);
    assertEq(govMITO.balanceOf(user2), 0);
    vm.stopPrank();

    assertFalse(govMITO.isWhitelistedSender(user1));
    vm.prank(owner);
    govMITO.setWhitelistedSender(user1, true);
    assertTrue(govMITO.isWhitelistedSender(user1));

    vm.prank(user1);
    govMITO.transfer(user2, 30);
    assertEq(govMITO.balanceOf(user1), 70);
    assertEq(govMITO.balanceOf(user2), 30);

    vm.prank(user1);
    govMITO.approve(user2, 20);

    assertFalse(govMITO.isWhitelistedSender(user2));
    vm.prank(owner);
    govMITO.setWhitelistedSender(user2, true);
    assertTrue(govMITO.isWhitelistedSender(user2));

    vm.prank(user2);
    govMITO.transferFrom(user1, user2, 20);
    assertEq(govMITO.balanceOf(user1), 50);
    assertEq(govMITO.balanceOf(user2), 50);
  }

  function test_whiteListedSender_NotWhitelisted() public {
    payable(minter).transfer(200);
    vm.startPrank(minter);
    govMITO.mint{ value: 100 }(user1);
    assertEq(govMITO.balanceOf(user1), 100);
    assertEq(govMITO.balanceOf(user2), 0);
    vm.stopPrank();

    assertFalse(govMITO.isWhitelistedSender(user1));
    assertFalse(govMITO.isWhitelistedSender(user2));

    vm.prank(user1);
    vm.expectRevert(_errUnauthorized());
    govMITO.transfer(user2, 30);

    vm.prank(user1);
    vm.expectRevert(_errUnauthorized());
    govMITO.approve(user2, 20);

    vm.prank(user1);
    vm.expectRevert(_errUnauthorized());
    govMITO.transferFrom(user1, user2, 20); // user1 is not whitelisted. It is not important that user2 is whitelisted
  }

  function test_delegate() public {
    vm.expectRevert(_errNotSupported());
    vm.prank(user1);
    govMITO.delegate(user1);
  }

  function test_delegateBySig() public {
    vm.expectRevert(_errNotSupported());
    vm.prank(user1);
    govMITO.delegateBySig(user1, 0, 0, 0, bytes32(0), bytes32(0));
  }

  function test_setMinter() public {
    vm.prank(user1);
    vm.expectRevert(_errOwnableUnauthorizedAccount(user1));
    govMITO.setMinter(minter);

    // set to zero address
    vm.prank(owner);
    vm.expectEmit();
    emit IGovMITO.MinterSet(address(0));
    govMITO.setMinter(address(0));

    assertEq(govMITO.minter(), address(0));

    // rollback to minter
    vm.prank(owner);
    vm.expectEmit();
    emit IGovMITO.MinterSet(minter);
    govMITO.setMinter(minter);

    assertEq(govMITO.minter(), minter);
  }

  function test_setDelegationManager() public {
    vm.expectRevert(_errUnauthorized());
    vm.prank(user1);
    govMITO.setDelegationManager(delegationManager);

    vm.prank(owner);
    vm.expectEmit();
    emit ISudoVotes.DelegationManagerSet(address(0), delegationManager);
    govMITO.setDelegationManager(delegationManager);

    assertEq(govMITO.delegationManager(), delegationManager);
  }

  function test_sudoDelegate() public {
    test_setDelegationManager();
    test_mint();

    vm.expectRevert(_errUnauthorized());
    vm.prank(user1);
    govMITO.sudoDelegate(user1, user1);

    vm.prank(delegationManager);
    vm.expectEmit();
    emit IVotes.DelegateChanged(user1, address(0), user1);
    vm.expectEmit();
    emit IVotes.DelegateVotesChanged(user1, 0, 100);
    govMITO.sudoDelegate(user1, user1);
  }

  function test_module() public {
    test_mint();

    vm.prank(user1);
    vm.expectRevert(_errOwnableUnauthorizedAccount(user1));
    govMITO.setModule(module, true);

    vm.prank(owner);
    vm.expectEmit();
    emit IGovMITO.ModuleSet(module, true);
    govMITO.setModule(module, true);

    assertTrue(govMITO.isModule(module));

    vm.prank(user1);
    govMITO.approve(module, 100);

    vm.prank(module);
    govMITO.transferFrom(user1, module, 100);

    assertEq(govMITO.balanceOf(user1), 0);
    assertEq(govMITO.balanceOf(module), 100);

    vm.prank(module);
    govMITO.transfer(user1, 100);

    assertEq(govMITO.balanceOf(user1), 100);
    assertEq(govMITO.balanceOf(module), 0);
  }

  function _errNothingToClaim() internal pure returns (bytes memory) {
    return abi.encodeWithSelector(LibQueue.LibQueue__NothingToClaim.selector);
  }
}
