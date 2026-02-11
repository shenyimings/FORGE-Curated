// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import "./IStaking.sol";

interface IOperatorStaking is IStaking {
    function getRemovedPrincipal(address _staker) external view returns (uint256);
}
