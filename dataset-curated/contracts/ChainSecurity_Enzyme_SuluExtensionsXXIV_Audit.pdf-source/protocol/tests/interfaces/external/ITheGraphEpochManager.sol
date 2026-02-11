// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.6.0 <0.9.0;

interface ITheGraphEpochManager {
    function currentEpoch() external view returns (uint256 epoch_);

    function runEpoch() external;

    function setEpochLength(uint256 _epochLength) external;
}
