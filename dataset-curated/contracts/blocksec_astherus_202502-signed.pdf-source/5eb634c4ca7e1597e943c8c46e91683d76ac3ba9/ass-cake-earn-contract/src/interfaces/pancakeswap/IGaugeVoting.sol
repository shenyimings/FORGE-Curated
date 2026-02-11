// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title GaugeVoting Contract interface
/// @notice Voting for Gauge with weights
interface IGaugeVoting {
  function voteForGaugeWeightsBulk(
    address[] memory _gauge_addrs,
    uint256[] memory _user_weights,
    uint256[] memory _chainIds,
    bool _skipNative,
    bool _skipProxy
  ) external;
}
