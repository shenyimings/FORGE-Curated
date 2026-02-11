// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import { LinearMultipleRewardDistributor } from "../common/rewards/distributor/LinearMultipleRewardDistributor.sol";

contract MockMultipleRewardDistributor is LinearMultipleRewardDistributor {
  constructor() LinearMultipleRewardDistributor(1 weeks) {}

  function initialize() external {
    _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
  }

  function _accumulateReward(address _token, uint256 _amount) internal virtual override {}
}
