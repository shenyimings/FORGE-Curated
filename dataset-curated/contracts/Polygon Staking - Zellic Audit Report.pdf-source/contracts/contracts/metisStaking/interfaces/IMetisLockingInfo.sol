// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

interface IMetisLockingInfo {
    function minLock() external view returns (uint256);

    function maxLock() external view returns (uint256);

    function manager() external view returns (address);
}
