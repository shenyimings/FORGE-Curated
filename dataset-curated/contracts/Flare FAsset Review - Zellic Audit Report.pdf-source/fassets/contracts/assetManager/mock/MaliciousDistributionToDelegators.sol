// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

contract MaliciousDistributionToDelegators {
    uint256 public amount = 0;

    constructor (uint256 _claim) {
        amount = _claim;
    }

    function claim(
        address /* _rewardOwner */,
        address /* _recipient */,
        uint256 /* _month */,
        bool /* _wrap */
    )
        external
        returns(uint256 _rewardAmount)
    {
        return amount;
    }
}
