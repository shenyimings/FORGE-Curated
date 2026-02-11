// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

interface IProtocolAdapter {
    function vault() external view returns (address);

    function maxDeposit(address subvault) external view returns (uint256);

    function stakedAt(address subvault) external view returns (uint256);

    function assetOf(address subvault) external view returns (address);

    function validateRewardData(bytes calldata data) external view;

    function pushRewards(address rewardToken, bytes calldata farmData, bytes memory rewardData)
        external;

    function withdraw(
        address subvault,
        address withdrawalQueue,
        address receiver,
        uint256 request,
        address owner
    ) external;

    function deposit(address subvault, uint256 assets) external;

    function handleVault(address subvault) external returns (address withdrawalQueue);

    function areWithdrawalsPaused(address subvault, address account) external view returns (bool);
}
