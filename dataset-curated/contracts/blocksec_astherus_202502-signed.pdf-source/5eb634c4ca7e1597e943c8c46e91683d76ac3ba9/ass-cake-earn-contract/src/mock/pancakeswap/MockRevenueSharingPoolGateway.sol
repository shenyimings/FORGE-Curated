// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./MockRevenueSharingPool.sol";

contract MockRevenueSharingPoolGateway {
  using SafeERC20 for IERC20;

  function claimMultipleWithoutProxy(address[] calldata _revenueSharingPools, address _for) external {
    for (uint256 i = 0; i < _revenueSharingPools.length; i++) {
      MockRevenueSharingPool(_revenueSharingPools[i]).claimForUser(_for);
    }
  }

}
