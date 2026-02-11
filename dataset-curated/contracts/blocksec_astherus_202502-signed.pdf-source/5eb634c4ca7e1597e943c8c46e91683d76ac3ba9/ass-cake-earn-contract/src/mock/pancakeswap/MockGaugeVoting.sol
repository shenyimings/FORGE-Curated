// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract MockGaugeVoting {
  function voteForGaugeWeightsBulk(
    address[] memory _gauge_addrs,
    uint256[] memory _user_weights,
    uint256[] memory _chainIds,
    bool _skipNative,
    bool _skipProxy
  ) external {
    uint256 len = _gauge_addrs.length;
    require(len == _user_weights.length, "length is not same");
    require(len == _chainIds.length, "length is not same");
  }
}
