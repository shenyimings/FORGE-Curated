// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title VeCake Contract interface
/// @notice PancakeSwap VeCake Contract interface, interact with UniversalProxy for managing CAKE locking
interface IVeCake {

  struct LockedBalance {
    int128 amount;
    uint256 end;
  }

  function locks(address user) external view returns (LockedBalance memory);

  function createLock(uint256 _amount, uint256 _unlockTime) external;

  function increaseLockAmount(uint256 _amount) external;

  function increaseUnlockTime(uint256 _newUnlockTime) external;

  function getUserInfo(address _user)
  external
  view
  returns (
    int128 amount,
    uint256 end,
    address cakePoolProxy,
    uint128 cakeAmount,
    uint48 lockEndTime,
    uint48 migrationTime,
    uint16 cakePoolType,
    uint16 withdrawFlag
  );

}
