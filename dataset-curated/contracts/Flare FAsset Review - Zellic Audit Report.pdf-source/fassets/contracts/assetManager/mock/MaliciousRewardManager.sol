// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IRewardManager} from "@flarenetwork/flare-periphery-contracts/flare/IRewardManager.sol";

contract MaliciousRewardManager {
    uint256 public amount = 0;

    constructor (uint256 _claim) {
        amount = _claim;
    }

    function claim(
        address /* _rewardOwner */,
        address payable /* _recipient */,
        uint24 /* _rewardEpochId */,
        bool /* _wrap */,
        IRewardManager.RewardClaimWithProof[] calldata /* _proofs */
    )
        external
        returns (uint256 _rewardAmountWei)
    {
        return amount;
    }
}
