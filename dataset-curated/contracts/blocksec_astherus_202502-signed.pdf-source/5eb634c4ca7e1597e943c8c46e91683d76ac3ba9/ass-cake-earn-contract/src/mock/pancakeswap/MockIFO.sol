// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MockIFO {
  using SafeERC20 for IERC20;
  uint8 pid;
  IERC20 public ifoToken;

  constructor(uint8 _pid, address token) {
    pid = _pid;
    ifoToken = IERC20(token);
  }

  function depositPool(uint256 _amount, uint8 _pid) external {
    // do nothing
    require(_amount > 0, "amount must be greater than 0");
    require(_pid == pid, "invalid pid");
  }

  function harvestPool(uint8 _pid) external {
    require(_pid == pid, "invalid pid");
    ifoToken.safeTransfer(msg.sender, ifoToken.balanceOf(address(this)));
  }
}
