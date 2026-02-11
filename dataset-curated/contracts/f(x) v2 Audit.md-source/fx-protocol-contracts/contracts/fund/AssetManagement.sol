// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { AccessControlUpgradeable } from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

import { IStrategy } from "./IStrategy.sol";

abstract contract AssetManagement is AccessControlUpgradeable {
  using SafeERC20 for IERC20;

  bytes32 public constant ASSET_MANAGER_ROLE = keccak256("ASSET_MANAGER_ROLE");

  struct Allocation {
    address strategy;
    uint96 capacity;
  }

  mapping(address => Allocation) public allocations;

  /**
   * @dev This empty reserved space is put in place to allow future versions to add new
   * variables without shifting down storage in the inheritance chain.
   */
  uint256[49] private __gap;

  function kill(address asset) public onlyRole(DEFAULT_ADMIN_ROLE) {
    Allocation memory curAlloc = allocations[asset];
    if (curAlloc.strategy != address(0)) {
      IStrategy(curAlloc.strategy).kill();
      curAlloc.strategy = address(0);
      curAlloc.capacity = 0;
      allocations[asset] = curAlloc;
    }
  }

  function alloc(address asset, address strategy, uint96 capacity) external onlyRole(DEFAULT_ADMIN_ROLE) {
    Allocation memory oldAlloc = allocations[asset];
    if (oldAlloc.strategy != address(0)) kill(asset);
    allocations[asset] = Allocation({ strategy: strategy, capacity: capacity });
  }

  function manage(address asset, uint256 amount) external onlyRole(ASSET_MANAGER_ROLE) {
    Allocation memory curAlloc = allocations[asset];
    uint256 managed = IStrategy(curAlloc.strategy).totalSupply();
    if (managed + amount > curAlloc.capacity) revert();
    IERC20(asset).safeTransfer(curAlloc.strategy, amount);
    IStrategy(curAlloc.strategy).deposit(amount);
  }

  function _transferOut(address asset, uint256 amount, address receiver) internal {
    uint256 balance = IERC20(asset).balanceOf(address(this));
    if (balance >= amount) {
      IERC20(asset).safeTransfer(receiver, amount);
    } else {
      IERC20(asset).safeTransfer(receiver, balance);
      uint256 diff = amount - balance;
      Allocation memory curAlloc = allocations[asset];
      if (curAlloc.strategy == address(0)) revert();
      IStrategy(curAlloc.strategy).withdraw(diff, receiver);
    }
  }
}
