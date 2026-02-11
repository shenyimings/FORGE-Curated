// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "./IMultiVaultStorage.sol";

interface IMultiVault is IMultiVaultStorage {
    struct InitParams {
        address admin;
        uint256 limit;
        bool depositPause;
        bool withdrawalPause;
        bool depositWhitelist;
        address asset;
        string name;
        string symbol;
        address depositStrategy;
        address withdrawalStrategy;
        address rebalanceStrategy;
        address defaultCollateral;
        address symbioticAdapter;
        address eigenLayerAdapter;
        address erc4626Adapter;
    }

    function initialize(InitParams calldata initParams) external;

    function rebalance() external;

    function addSubvault(address vault, Protocol protocol) external;

    function removeSubvault(address subvault) external;

    function setDepositStrategy(address newDepositStrategy) external;

    function setWithdrawalStrategy(address newWithdrawalStrategy) external;

    function setRebalanceStrategy(address newRebalanceStrategy) external;

    function setRewardsData(uint256 farmId, RewardData calldata rewardData) external;

    function setDefaultCollateral(address defaultCollateral_) external;

    function setSymbioticAdapter(address adapter_) external;

    function setEigenLayerAdapter(address adapter_) external;

    function setERC4626Adapter(address adapter_) external;

    function pushRewards(uint256 farmId, bytes calldata data) external;

    event Rebalance(IRebalanceStrategy.RebalanceData[] data, uint256 timestamp);

    event DepositIntoCollateral(uint256 assets);

    event RewardsPushed(
        uint256 indexed farmId,
        uint256 indexed rewardAmount,
        uint256 indexed curatorFee,
        uint256 timestamp
    );
}
