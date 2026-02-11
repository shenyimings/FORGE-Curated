// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Time } from '@oz/utils/types/Time.sol';
import { OwnableUpgradeable } from '@ozu/access/OwnableUpgradeable.sol';

import { IValidatorManager } from '../../interfaces/hub/validator/IValidatorManager.sol';
import { IValidatorStakingHub } from '../../interfaces/hub/validator/IValidatorStakingHub.sol';
import { SudoVotes } from '../../lib/SudoVotes.sol';
import { ValidatorStaking } from './ValidatorStaking.sol';

contract ValidatorStakingGovMITO is ValidatorStaking, SudoVotes {
  error ValidatorStakingGovMITO__NonTransferable();

  constructor(address baseAsset_, IValidatorManager manager_, IValidatorStakingHub hub_)
    ValidatorStaking(baseAsset_, manager_, hub_)
  {
    _disableInitializers();
  }

  function initialize(
    address initialOwner,
    uint256 initialMinStakingAmount,
    uint256 initialMinUnstakingAmount,
    uint48 unstakeCooldown_,
    uint48 redelegationCooldown_
  ) public override initializer {
    super.initialize(
      initialOwner, //
      initialMinStakingAmount,
      initialMinUnstakingAmount,
      unstakeCooldown_,
      redelegationCooldown_
    );

    __Votes_init();
  }

  function owner() public view override(OwnableUpgradeable, SudoVotes) returns (address) {
    return super.owner();
  }

  function clock() public view override returns (uint48) {
    return Time.timestamp();
  }

  function CLOCK_MODE() public view override returns (string memory) {
    // Check that the clock was not modified
    require(clock() == Time.timestamp(), ERC6372InconsistentClock());
    return 'mode=timestamp';
  }

  function _getVotingUnits(address account) internal view override returns (uint256) {
    uint48 now_ = clock();
    (uint256 totalUnstakingAmount,) = unstaking(account, now_);
    return stakerTotal(account, now_) + totalUnstakingAmount;
  }

  /// @dev Mints voting units to the recipient. No need to care about the validator
  function _stake(StorageV1 storage $, address valAddr, address payer, address recipient, uint256 amount)
    internal
    override
    returns (uint256)
  {
    require(recipient == payer, ValidatorStakingGovMITO__NonTransferable());

    // mint the voting units
    _moveDelegateVotes(address(0), delegates(recipient), amount);

    return super._stake($, valAddr, payer, recipient, amount);
  }

  /// @dev Prevent the other users to receive unstaked tokens. Otherwise, users can perform transfer tokens to the others.
  function _requestUnstake(StorageV1 storage $, address valAddr, address payer, address receiver, uint256 amount)
    internal
    override
    returns (uint256)
  {
    require(receiver == payer, ValidatorStakingGovMITO__NonTransferable());
    return super._requestUnstake($, valAddr, payer, receiver, amount);
  }

  /// @dev Burns the voting units from the recipient
  function _claimUnstake(StorageV1 storage $, address receiver) internal override returns (uint256) {
    uint256 claimed = super._claimUnstake($, receiver);

    // burn the voting units
    _moveDelegateVotes(delegates(receiver), address(0), claimed);

    return claimed;
  }
}
