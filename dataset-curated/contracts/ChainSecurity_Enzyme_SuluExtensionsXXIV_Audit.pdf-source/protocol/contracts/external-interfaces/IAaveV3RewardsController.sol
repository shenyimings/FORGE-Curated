// SPDX-License-Identifier: GPL-3.0

/*
    This file is part of the Enzyme Protocol.

    (c) Enzyme Foundation <security@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity >=0.6.0 <0.9.0;

/// @title IAaveV3RewardsController interface
/// @author Enzyme Foundation <security@enzyme.finance>
interface IAaveV3RewardsController {
    function claimRewards(address[] calldata _assets, uint256 _amount, address _to, address _rewardToken)
        external
        returns (uint256 amountClaimed_);
}
