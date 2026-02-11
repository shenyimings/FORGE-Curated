// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";

import "../../interfaces/pancakeswap/IVeCake.sol";

contract MockVeCake is IVeCake {
  using SafeERC20 for IERC20;
  IERC20 public cake;
  mapping(address => LockedBalance) public lockedBalances;
  uint256 public constant WEEK = 7 days;
  // MAX_LOCK 209 weeks - 1 seconds
  uint256 public constant MAX_LOCK = (209 * WEEK) - 1;

  constructor(address _cake){
    cake = IERC20(_cake);
  }

  function locks(address user) external view override returns (LockedBalance memory) {
    return lockedBalances[user];
  }

  function createLock(uint256 _amount, uint256 _unlockTime) external override {
    cake.safeTransferFrom(msg.sender, address(this), _amount);
    lockedBalances[msg.sender].amount += SafeCast.toInt128(int256(_amount));
    lockedBalances[msg.sender].end = _unlockTime / WEEK * WEEK;
  }

  function increaseLockAmount(uint256 _amount) external override {
    cake.safeTransferFrom(msg.sender, address(this), _amount);
    lockedBalances[msg.sender].amount += SafeCast.toInt128(int256(_amount));
  }

  function increaseUnlockTime(uint256 _newUnlockTime) external override {
    require(_newUnlockTime >= lockedBalances[msg.sender].end, "VeCake: new unlock time must be after current unlock time");
    lockedBalances[msg.sender].end = _newUnlockTime / WEEK * WEEK;
  }

  function getUserInfo(address _user)
  external
  view
  override
  returns (
    int128 amount,
    uint256 end,
    address cakePoolProxy,
    uint128 cakeAmount,
    uint48 lockEndTime,
    uint48 migrationTime,
    uint16 cakePoolType,
    uint16 withdrawFlag
  ) {
    LockedBalance memory locked = lockedBalances[_user];
    return (locked.amount, locked.end, address(0), uint128(0), SafeCast.toUint48(locked.end), uint48(0), uint16(0), uint16(0));
  }
}
