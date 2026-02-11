// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

interface IResolvStaking {

    function deposit(
        uint256 _amount,
        address _receiver
    ) external;

    function withdraw(
        bool _claimRewards,
        address _receiver
    ) external;

    function initiateWithdrawal(uint256 _amount) external;

    function claim(address _user, address _receiver) external;

    function updateCheckpoint(address _user) external;

    function depositReward(
        address _token,
        uint256 _amount,
        uint256 _duration
    ) external;

    function setRewardsReceiver(address _receiver) external;

    function setCheckpointDelegatee(address _delegatee) external;

    function setClaimEnabled(bool _enabled) external;

    function setWithdrawalCooldown(uint256 _cooldown) external;

    function getUserAccumulatedRewardPerToken(address _user, address _token) external view returns (uint256 amount);

    function getUserClaimableAmounts(address _user, address _token) external view returns (uint256 amount);

    function getUserEffectiveBalance(address _user) external view returns (uint256 balance);

    function claimEnabled() external view returns (bool isEnabled);

    function rewardTokens(uint256 _index) external view returns (address token);
}
