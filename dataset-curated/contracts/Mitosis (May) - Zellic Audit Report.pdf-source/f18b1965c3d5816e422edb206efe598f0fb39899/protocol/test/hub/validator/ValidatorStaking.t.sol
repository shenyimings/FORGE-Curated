// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { WETH } from '@solady/tokens/WETH.sol';

import { ValidatorStaking } from '../../../src/hub/validator/ValidatorStaking.sol';
import { IValidatorManager } from '../../../src/interfaces/hub/validator/IValidatorManager.sol';
import { IValidatorStaking } from '../../../src/interfaces/hub/validator/IValidatorStaking.sol';
import { IValidatorStakingHub } from '../../../src/interfaces/hub/validator/IValidatorStakingHub.sol';
import { MockContract } from '../../util/MockContract.sol';
import { Toolkit } from '../../util/Toolkit.sol';

contract ValidatorStakingTest is Toolkit {
  mapping(address vault => mapping(address user => uint256)) globalReqId;

  address owner = makeAddr('owner');
  address val1 = makeAddr('val1');
  address val2 = makeAddr('val2');
  address val3 = makeAddr('val3');
  address user1 = makeAddr('user1');
  address user2 = makeAddr('user2');

  WETH weth;
  MockContract hub;
  MockContract manager;

  ValidatorStaking erc20Vault;
  ValidatorStaking nativeVault;

  function setUp() public {
    // use real time to avoid arithmatic overflow on withdrawalPeriod calculation
    vm.warp(1743061332);

    weth = new WETH();
    hub = new MockContract();
    hub.setCall(IValidatorStakingHub.notifyStake.selector);
    hub.setCall(IValidatorStakingHub.notifyUnstake.selector);
    hub.setCall(IValidatorStakingHub.notifyRedelegation.selector);

    manager = new MockContract();

    erc20Vault = ValidatorStaking(
      payable(
        _proxy(
          address(
            new ValidatorStaking(
              address(weth), // erc20
              IValidatorManager(address(manager)),
              IValidatorStakingHub(address(hub))
            )
          ),
          abi.encodeCall(ValidatorStaking.initialize, (owner, 1 ether, 1 ether, 1 days, 1 days))
        )
      )
    );

    nativeVault = ValidatorStaking(
      payable(
        _proxy(
          address(
            new ValidatorStaking(
              address(0), // native
              IValidatorManager(address(manager)),
              IValidatorStakingHub(address(hub))
            )
          ),
          abi.encodeCall(ValidatorStaking.initialize, (owner, 1 ether, 1 ether, 1 days, 1 days))
        )
      )
    );
  }

  function test_init() public view {
    assertEq(erc20Vault.owner(), owner);
    assertEq(erc20Vault.baseAsset(), address(weth));
    assertEq(address(erc20Vault.manager()), address(manager));
    assertEq(address(erc20Vault.hub()), address(hub));
    assertEq(erc20Vault.minStakingAmount(), 1 ether);
    assertEq(erc20Vault.minUnstakingAmount(), 1 ether);
    assertEq(erc20Vault.unstakeCooldown(), 1 days);
    assertEq(erc20Vault.redelegationCooldown(), 1 days);

    assertEq(nativeVault.owner(), owner);
    assertEq(nativeVault.baseAsset(), nativeVault.NATIVE_TOKEN());
    assertEq(address(nativeVault.manager()), address(manager));
    assertEq(address(nativeVault.hub()), address(hub));
    assertEq(nativeVault.minStakingAmount(), 1 ether);
    assertEq(nativeVault.minUnstakingAmount(), 1 ether);
    assertEq(nativeVault.unstakeCooldown(), 1 days);
    assertEq(nativeVault.redelegationCooldown(), 1 days);
  }

  function test_minStakingAmount() public {
    vm.expectRevert(_errOwnableUnauthorizedAccount(address(this)));
    erc20Vault.setMinStakingAmount(0);

    vm.prank(owner);
    erc20Vault.setMinStakingAmount(0);

    assertEq(erc20Vault.minStakingAmount(), 0);

    vm.prank(owner);
    erc20Vault.setMinStakingAmount(1 ether);

    assertEq(erc20Vault.minStakingAmount(), 1 ether);
  }

  function test_minUnstakingAmount() public {
    vm.expectRevert(_errOwnableUnauthorizedAccount(address(this)));
    erc20Vault.setMinUnstakingAmount(0);

    vm.prank(owner);
    erc20Vault.setMinUnstakingAmount(0);

    assertEq(erc20Vault.minUnstakingAmount(), 0);

    vm.prank(owner);
    erc20Vault.setMinUnstakingAmount(1 ether);

    assertEq(erc20Vault.minUnstakingAmount(), 1 ether);
  }

  function test_stake() public {
    _test_stake(erc20Vault);
    _test_stake(nativeVault);
  }

  function test_stake_minAmount() public {
    _fund();

    _regVal(val1, true);

    vm.prank(user1);
    vm.expectRevert(_errInsufficientMinimumAmount(1 ether));
    erc20Vault.stake(val1, user1, 1);

    vm.prank(user1);
    vm.expectRevert(_errInsufficientMinimumAmount(1 ether));
    erc20Vault.stake(val1, user1, 1 ether - 1);

    vm.prank(user1);
    erc20Vault.stake(val1, user1, 1 ether);

    // NativeVault

    vm.prank(user1);
    vm.expectRevert(_errInsufficientMinimumAmount(1 ether));
    nativeVault.stake{ value: 1 }(val1, user1, 1);

    vm.prank(user1);
    vm.expectRevert(_errInsufficientMinimumAmount(1 ether));
    nativeVault.stake{ value: 1 ether - 1 }(val1, user1, 1 ether - 1);

    vm.prank(user1);
    nativeVault.stake{ value: 1 ether }(val1, user1, 1 ether);
  }

  function test_stake_fromAnotherAddress() public {
    _fund();

    _regVal(val1, true);

    // ERC20 Vault

    vm.prank(user1);
    vm.expectEmit();
    emit IValidatorStaking.Staked(val1, user1, user2, 1 ether);
    erc20Vault.stake(val1, user2, 1 ether);

    assertEq(erc20Vault.staked(val1, user1, _now48()), 0);
    assertEq(erc20Vault.staked(val1, user2, _now48()), 1 ether);

    assertEq(erc20Vault.stakerTotal(user1, _now48()), 0);
    assertEq(erc20Vault.stakerTotal(user2, _now48()), 1 ether);

    // NativeVault

    vm.prank(user1);
    vm.expectEmit();
    emit IValidatorStaking.Staked(val1, user1, user2, 1 ether);
    nativeVault.stake{ value: 1 ether }(val1, user2, 1 ether);

    assertEq(nativeVault.staked(val1, user1, _now48()), 0);
    assertEq(nativeVault.staked(val1, user2, _now48()), 1 ether);

    assertEq(nativeVault.stakerTotal(user1, _now48()), 0);
    assertEq(nativeVault.stakerTotal(user2, _now48()), 1 ether);
  }

  function _test_stake(ValidatorStaking vault) private {
    _fund();

    _regVal(val1, true);
    _regVal(val2, false);
    _regVal(val3, true);

    // ===== not a validator

    if (vault.baseAsset() == vault.NATIVE_TOKEN()) {
      vm.prank(user1);
      vm.expectRevert(_errZeroAmount());
      vault.stake{ value: 0 }(val1, user1, 0);

      vm.prank(user1);
      vm.expectRevert(abi.encodeWithSelector(IValidatorStaking.IValidatorStaking__NotValidator.selector, val2));
      vault.stake{ value: 10 ether }(val2, user1, 10 ether);
    } else {
      vm.prank(user1);
      vm.expectRevert(_errZeroAmount());
      vault.stake(val1, user1, 0);

      vm.prank(user1);
      vm.expectRevert(abi.encodeWithSelector(IValidatorStaking.IValidatorStaking__NotValidator.selector, val2));
      vault.stake(val2, user1, 10 ether);
    }

    // =====

    _stake(vault, val1, user1, user1, 10 ether);
    _stake(vault, val1, user2, user2, 20 ether);

    vm.warp(block.timestamp + 1 days);

    _stake(vault, val1, user1, user1, 20 ether);
    _stake(vault, val3, user2, user2, 10 ether);

    // =====

    uint48 now_ = _now48();

    //======== present

    assertEq(vault.totalStaked(now_), 60 ether);

    // user 1
    assertEq(vault.staked(val1, user1, now_), 30 ether);
    assertEq(vault.staked(val3, user1, now_), 0);
    assertEq(vault.stakerTotal(user1, now_), 30 ether);

    // user 2
    assertEq(vault.staked(val1, user2, now_), 20 ether);
    assertEq(vault.staked(val3, user2, now_), 10 ether);
    assertEq(vault.stakerTotal(user2, now_), 30 ether);

    // vals
    assertEq(vault.validatorTotal(val1, now_), 50 ether);
    assertEq(vault.validatorTotal(val3, now_), 10 ether);

    //======== past

    assertEq(vault.totalStaked(now_ - 1), 30 ether);

    // user 1
    assertEq(vault.staked(val1, user1, now_ - 1), 10 ether);
    assertEq(vault.staked(val3, user1, now_ - 1), 0);
    assertEq(vault.stakerTotal(user1, now_ - 1), 10 ether);

    // user 2
    assertEq(vault.staked(val1, user2, now_ - 1), 20 ether);
    assertEq(vault.staked(val3, user2, now_ - 1), 0);
    assertEq(vault.stakerTotal(user2, now_ - 1), 20 ether);

    // vals
    assertEq(vault.validatorTotal(val1, now_ - 1), 30 ether);
    assertEq(vault.validatorTotal(val3, now_ - 1), 0);
  }

  function test_unstake() public {
    _test_unstake(erc20Vault);
    _test_unstake(nativeVault);
  }

  function test_unstake_minAmount() public {
    _fund();

    _regVal(val1, true);

    _stake(erc20Vault, val1, user1, user1, 1 ether);
    _stake(nativeVault, val1, user1, user1, 1 ether);

    vm.prank(user1);
    vm.expectRevert(_errInsufficientMinimumAmount(1 ether));
    erc20Vault.requestUnstake(val1, user1, 1);

    vm.prank(user1);
    vm.expectRevert(_errInsufficientMinimumAmount(1 ether));
    erc20Vault.requestUnstake(val1, user1, 1 ether - 1);

    vm.prank(user1);
    erc20Vault.requestUnstake(val1, user1, 1 ether);

    // NativeVault

    vm.prank(user1);
    vm.expectRevert(_errInsufficientMinimumAmount(1 ether));
    nativeVault.requestUnstake(val1, user1, 1);

    vm.prank(user1);
    vm.expectRevert(_errInsufficientMinimumAmount(1 ether));
    nativeVault.requestUnstake(val1, user1, 1 ether - 1);

    vm.prank(user1);
    nativeVault.requestUnstake(val1, user1, 1 ether);
  }

  function test_unstake_fromAnotherAddress() public {
    _fund();

    _regVal(val1, true);

    _stake(erc20Vault, val1, user1, user2, 1 ether);
    _stake(nativeVault, val1, user1, user2, 1 ether);

    vm.prank(user2);
    vm.expectEmit();
    emit IValidatorStaking.UnstakeRequested(val1, user2, user1, 1 ether, 0);
    erc20Vault.requestUnstake(val1, user1, 1 ether);

    assertEq(erc20Vault.staked(val1, user1, _now48()), 0);
    assertEq(erc20Vault.staked(val1, user2, _now48()), 0);

    assertEq(erc20Vault.stakerTotal(user1, _now48()), 0);
    assertEq(erc20Vault.stakerTotal(user2, _now48()), 0);

    _assertUnstaking(erc20Vault, user1, _now48(), 1 ether, 0);
    _assertUnstaking(erc20Vault, user2, _now48(), 0, 0);

    // NativeVault

    vm.prank(user2);
    vm.expectEmit();
    emit IValidatorStaking.UnstakeRequested(val1, user2, user1, 1 ether, 0);
    nativeVault.requestUnstake(val1, user1, 1 ether);

    assertEq(nativeVault.staked(val1, user1, _now48()), 0);
    assertEq(nativeVault.staked(val1, user2, _now48()), 0);

    assertEq(nativeVault.stakerTotal(user1, _now48()), 0);
    assertEq(nativeVault.stakerTotal(user2, _now48()), 0);

    _assertUnstaking(nativeVault, user1, _now48(), 1 ether, 0);
    _assertUnstaking(nativeVault, user2, _now48(), 0, 0);
  }

  function _test_unstake(ValidatorStaking vault) private {
    _fund();

    _regVal(val1, true);
    _regVal(val2, false);
    _regVal(val3, true);

    vm.prank(user1);
    vm.expectRevert(_errZeroAmount());
    vault.requestUnstake(val1, user1, 0);

    vm.prank(user1);
    vm.expectRevert(abi.encodeWithSelector(IValidatorStaking.IValidatorStaking__NotValidator.selector, val2));
    vault.requestUnstake(val2, user1, 10 ether);

    _stake(vault, val1, user1, user1, 10 ether);
    _stake(vault, val3, user1, user1, 10 ether);
    _stake(vault, val1, user2, user2, 20 ether);

    vm.warp(block.timestamp + 1 days);

    _requestUnstake(vault, val1, user1, user1, 5 ether);
    _requestUnstake(vault, val3, user1, user1, 5 ether);
    _requestUnstake(vault, val1, user2, user2, 10 ether);

    uint48 now_ = _now48();

    //======== present

    assertEq(vault.totalStaked(now_), 20 ether);
    assertEq(vault.totalUnstaking(now_), 20 ether);

    assertEq(vault.staked(val1, user1, now_), 5 ether);
    assertEq(vault.staked(val3, user1, now_), 5 ether);
    assertEq(vault.staked(val1, user2, now_), 10 ether);

    assertEq(vault.stakerTotal(user1, now_), 10 ether);
    assertEq(vault.stakerTotal(user2, now_), 10 ether);

    assertEq(vault.validatorTotal(val1, now_), 15 ether);
    assertEq(vault.validatorTotal(val3, now_), 5 ether);

    _assertUnstaking(vault, user1, now_, 10 ether, 0);
    _assertUnstaking(vault, user2, now_, 10 ether, 0);

    _assertUnstaking(vault, user1, now_ + vault.unstakeCooldown(), 10 ether, 10 ether);
    _assertUnstaking(vault, user2, now_ + vault.unstakeCooldown(), 10 ether, 10 ether);

    //======== past

    assertEq(vault.totalStaked(now_ - 1), 40 ether);
    assertEq(vault.totalUnstaking(now_ - 1), 0 ether);

    assertEq(vault.staked(val1, user1, now_ - 1), 10 ether);
    assertEq(vault.staked(val3, user1, now_ - 1), 10 ether);
    assertEq(vault.staked(val1, user2, now_ - 1), 20 ether);

    assertEq(vault.stakerTotal(user1, now_ - 1), 20 ether);
    assertEq(vault.stakerTotal(user2, now_ - 1), 20 ether);

    assertEq(vault.validatorTotal(val1, now_ - 1), 30 ether);
    assertEq(vault.validatorTotal(val3, now_ - 1), 10 ether);

    vm.warp(block.timestamp + 1 days);

    now_ = _now48();

    _claimUnstake(vault, user1, 0, 1);
    _claimUnstake(vault, user2, 0, 1);

    assertEq(vault.totalStaked(now_), 20 ether);
    assertEq(vault.totalUnstaking(now_), 0);

    _assertUnstaking(vault, user1, now_, 0, 0);
    _assertUnstaking(vault, user2, now_, 0, 0);
  }

  function test_redelegate() public {
    _test_redelegate(erc20Vault);
    _test_redelegate(nativeVault);
  }

  function test_redelegate_min_amount() public {
    _fund();

    _regVal(val1, true);
    _regVal(val2, true);

    _stake(erc20Vault, val1, user1, user1, 1 ether);
    _stake(nativeVault, val1, user1, user1, 1 ether);

    vm.warp(block.timestamp + 1 days);

    vm.prank(user1);
    vm.expectRevert(_errInsufficientMinimumAmount(1 ether));
    erc20Vault.redelegate(val1, val2, 1);

    vm.prank(user1);
    vm.expectRevert(_errInsufficientMinimumAmount(1 ether));
    erc20Vault.redelegate(val1, val2, 1 ether - 1);

    vm.prank(user1);
    erc20Vault.redelegate(val1, val2, 1 ether);

    // NativeVault

    vm.prank(user1);
    vm.expectRevert(_errInsufficientMinimumAmount(1 ether));
    nativeVault.redelegate(val1, val2, 1);

    vm.prank(user1);
    vm.expectRevert(_errInsufficientMinimumAmount(1 ether));
    nativeVault.redelegate(val1, val2, 1 ether - 1);

    vm.prank(user1);
    nativeVault.redelegate(val1, val2, 1 ether);
  }

  function _test_redelegate(ValidatorStaking vault) private {
    _fund();

    _regVal(val1, true);
    _regVal(val2, false);
    _regVal(val3, true);

    vm.prank(user1);
    vm.expectRevert(
      abi.encodeWithSelector(IValidatorStaking.IValidatorStaking__RedelegateToSameValidator.selector, val1)
    );
    vault.redelegate(val1, val1, 10 ether);

    vm.prank(user1);
    vm.expectRevert(abi.encodeWithSelector(IValidatorStaking.IValidatorStaking__NotValidator.selector, val2));
    vault.redelegate(val2, val1, 10 ether);

    vm.prank(user1);
    vm.expectRevert(abi.encodeWithSelector(IValidatorStaking.IValidatorStaking__NotValidator.selector, val2));
    vault.redelegate(val1, val2, 10 ether);

    _stake(vault, val1, user1, user1, 10 ether);
    _stake(vault, val3, user2, user2, 10 ether);

    vm.warp(block.timestamp + 1 days);

    uint48 now_;

    now_ = _now48();

    assertEq(vault.totalStaked(now_), 20 ether);
    assertEq(vault.staked(val1, user1, now_), 10 ether);
    assertEq(vault.staked(val3, user2, now_), 10 ether);
    assertEq(vault.stakerTotal(user1, now_), 10 ether);
    assertEq(vault.stakerTotal(user2, now_), 10 ether);
    assertEq(vault.validatorTotal(val1, now_), 10 ether);
    assertEq(vault.validatorTotal(val3, now_), 10 ether);

    _redelegate(vault, val1, val3, user1, 10 ether);
    _redelegate(vault, val3, val1, user2, 10 ether);

    uint48 cooldown = vault.redelegationCooldown();
    vm.warp(block.timestamp + cooldown - 1);

    now_ = _now48();

    assertEq(vault.totalStaked(now_), 20 ether);
    assertEq(vault.staked(val3, user1, now_), 10 ether);
    assertEq(vault.staked(val1, user2, now_), 10 ether);
    assertEq(vault.stakerTotal(user1, now_), 10 ether);
    assertEq(vault.stakerTotal(user2, now_), 10 ether);
    assertEq(vault.validatorTotal(val1, now_), 10 ether);
    assertEq(vault.validatorTotal(val3, now_), 10 ether);

    vm.prank(user1);
    vm.expectRevert(_errCooldownNotPassed((now_ + 1) - cooldown, now_, 1));
    vault.redelegate(val3, val1, 10 ether);

    vm.prank(user2);
    vm.expectRevert(_errCooldownNotPassed((now_ + 1) - cooldown, now_, 1));
    vault.redelegate(val1, val3, 10 ether);

    vm.warp(block.timestamp + 1);

    _redelegate(vault, val3, val1, user1, 10 ether);
    _redelegate(vault, val1, val3, user2, 10 ether);
  }

  function _fund() internal {
    vm.deal(user1, 100 ether);
    vm.deal(user2, 100 ether);

    // pre-mint

    vm.prank(user1);
    weth.deposit{ value: 50 ether }();

    vm.prank(user2);
    weth.deposit{ value: 50 ether }();

    // pre-approve

    vm.prank(user1);
    weth.approve(address(erc20Vault), 50 ether);

    vm.prank(user2);
    weth.approve(address(erc20Vault), 50 ether);
  }

  function _stake(ValidatorStaking vault, address val, address sender, address recipient, uint256 amount) internal {
    uint256 balanceBefore =
      vault.baseAsset() == vault.NATIVE_TOKEN() ? address(vault).balance : weth.balanceOf(address(vault));

    if (vault.baseAsset() == vault.NATIVE_TOKEN()) {
      vm.prank(sender);
      vm.expectEmit();
      emit IValidatorStaking.Staked(val, sender, recipient, amount);
      vault.stake{ value: amount }(val, recipient, amount);
    } else {
      vm.prank(sender);
      vm.expectEmit();
      emit IValidatorStaking.Staked(val, sender, recipient, amount);
      vault.stake(val, recipient, amount);
    }

    hub.assertLastCall(abi.encodeCall(IValidatorStakingHub.notifyStake, (val, recipient, amount)));

    if (vault.baseAsset() == vault.NATIVE_TOKEN()) assertEq(address(vault).balance, balanceBefore + amount);
    else assertEq(weth.balanceOf(address(vault)), balanceBefore + amount);
  }

  function _requestUnstake(ValidatorStaking vault, address val, address sender, address recipient, uint256 amount)
    internal
  {
    vm.prank(sender);
    vm.expectEmit();
    emit IValidatorStaking.UnstakeRequested(val, sender, recipient, amount, globalReqId[address(vault)][recipient]++);
    vault.requestUnstake(val, recipient, amount);

    hub.assertLastCall(abi.encodeCall(IValidatorStakingHub.notifyUnstake, (val, recipient, amount)));
  }

  function _claimUnstake(ValidatorStaking vault, address recipient, uint256 reqIdFrom, uint256 reqIdTo) internal {
    uint256 balanceBefore = vault.baseAsset() == vault.NATIVE_TOKEN() ? recipient.balance : weth.balanceOf(recipient);
    (uint256 claimable,) = vault.unstaking(recipient, _now48());

    vm.prank(recipient);
    vm.expectEmit();
    emit IValidatorStaking.UnstakeClaimed(recipient, claimable, reqIdFrom, reqIdTo);
    uint256 claimed = vault.claimUnstake(recipient);

    if (vault.baseAsset() == vault.NATIVE_TOKEN()) assertEq(recipient.balance, balanceBefore + claimed);
    else assertEq(weth.balanceOf(recipient), balanceBefore + claimed);
  }

  function _redelegate(ValidatorStaking vault, address fromVal, address toVal, address sender, uint256 amount) internal {
    vm.prank(sender);
    vm.expectEmit();
    emit IValidatorStaking.Redelegated(fromVal, toVal, sender, amount);
    vault.redelegate(fromVal, toVal, amount);

    hub.assertLastCall(abi.encodeCall(IValidatorStakingHub.notifyRedelegation, (fromVal, toVal, sender, amount)));
  }

  function _assertUnstaking(
    ValidatorStaking vault,
    address user,
    uint48 timestamp,
    uint256 expectedTotal,
    uint256 expectedClaimable
  ) internal view {
    (uint256 total, uint256 claimable) = vault.unstaking(user, timestamp);
    assertEq(total, expectedTotal);
    assertEq(claimable, expectedClaimable);
  }

  function _regVal(address val, bool ok) internal {
    manager.setRet(abi.encodeCall(IValidatorManager.isValidator, (val)), false, abi.encode(ok));
  }

  function _errCooldownNotPassed(uint48 lastTime, uint48 currentTime, uint48 requiredCooldown)
    internal
    pure
    returns (bytes memory)
  {
    return abi.encodeWithSelector(
      IValidatorStaking.IValidatorStaking__CooldownNotPassed.selector, lastTime, currentTime, requiredCooldown
    );
  }

  function _errInsufficientMinimumAmount(uint256 amount) internal pure returns (bytes memory) {
    return abi.encodeWithSelector(IValidatorStaking.IValidatorStaking__InsufficientMinimumAmount.selector, amount);
  }
}
