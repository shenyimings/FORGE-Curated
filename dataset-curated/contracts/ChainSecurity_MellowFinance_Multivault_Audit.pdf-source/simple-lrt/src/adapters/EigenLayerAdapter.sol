// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "../interfaces/adapters/IEigenLayerAdapter.sol";

contract EigenLayerAdapter is IEigenLayerAdapter {
    using SafeERC20 for IERC20;

    uint8 public constant PAUSED_DEPOSITS = 0;
    uint8 public constant PAUSED_WITHDRAWALS = 1;
    uint8 public constant PAUSED_ENTER_WITHDRAWAL_QUEUE = 1;
    uint8 public constant PAUSED_EXIT_WITHDRAWAL_QUEUE = 2;

    address public immutable vault;

    IIsolatedEigenLayerVaultFactory public immutable factory;
    IRewardsCoordinator public immutable rewardsCoordinator;
    IStrategyManager public immutable strategyManager;
    IDelegationManager public immutable delegationManager;

    modifier delegateCallOnly() {
        require(address(this) == vault, "Delegate call only");
        _;
    }

    constructor(
        address factory_,
        address vault_,
        IStrategyManager strategyManager_,
        IRewardsCoordinator rewardsCoordinator_
    ) {
        vault = vault_;
        factory = IIsolatedEigenLayerVaultFactory(factory_);
        rewardsCoordinator = rewardsCoordinator_;
        strategyManager = strategyManager_;
        delegationManager = strategyManager_.delegation();
    }

    /// @inheritdoc IProtocolAdapter
    function maxDeposit(address isolatedVault) external view virtual returns (uint256) {
        (, address strategy,, address withdrawalQueue) = factory.instances(isolatedVault);
        if (IEigenLayerWithdrawalQueue(withdrawalQueue).isShutdown()) {
            return 0;
        }
        if (
            IPausable(address(strategyManager)).paused(PAUSED_DEPOSITS)
                || IPausable(address(strategy)).paused(PAUSED_DEPOSITS)
                || !strategyManager.strategyIsWhitelistedForDeposit(IStrategy(strategy))
        ) {
            return 0;
        }
        (bool success, bytes memory data) =
            strategy.staticcall(abi.encodeWithSignature("getTVLLimits()"));
        if (!success) {
            return type(uint256).max;
        }
        (uint256 maxPerDeposit, uint256 maxTotalDeposits) = abi.decode(data, (uint256, uint256));
        uint256 assets = IERC20(assetOf(isolatedVault)).balanceOf(strategy);
        if (assets >= maxTotalDeposits) {
            return 0;
        }
        return Math.min(maxPerDeposit, maxTotalDeposits - assets);
    }

    /// @inheritdoc IProtocolAdapter
    function stakedAt(address isolatedVault) external view virtual returns (uint256) {
        (, address strategy,, address withdrawalQueue) = factory.instances(isolatedVault);
        if (
            !delegationManager.isDelegated(isolatedVault)
                && !IEigenLayerWithdrawalQueue(withdrawalQueue).isShutdown()
        ) {
            revert("EigenLayerAdapter: isolated vault is neither delegated nor shut down");
        }
        return IStrategy(strategy).userUnderlyingView(isolatedVault);
    }

    /// @inheritdoc IProtocolAdapter
    function assetOf(address isolatedVault) public view returns (address) {
        return IIsolatedEigenLayerVault(isolatedVault).asset();
    }

    /// @inheritdoc IProtocolAdapter
    function handleVault(address isolatedVault) external view returns (address withdrawalQueue) {
        address owner;
        (owner,,, withdrawalQueue) = factory.instances(isolatedVault);
        if (owner != address(vault)) {
            revert("EigenLayerAdapter: invalid isolated vault owner");
        }
    }

    /// @inheritdoc IProtocolAdapter
    function validateRewardData(bytes calldata data) external view {
        require(data.length == 32, "EigenLayerAdapter: invalid reward data");
        address isolatedVault = abi.decode(data, (address));
        (address owner,,,) = factory.instances(isolatedVault);
        require(owner == vault, "EigenLayerAdapter: invalid reward data");
    }

    /// @inheritdoc IProtocolAdapter
    function pushRewards(address rewardToken, bytes calldata farmData, bytes calldata rewardData)
        external
        delegateCallOnly
    {
        IRewardsCoordinator.RewardsMerkleClaim memory eigenLayerFarmData =
            abi.decode(farmData, (IRewardsCoordinator.RewardsMerkleClaim));
        require(
            eigenLayerFarmData.tokenLeaves.length == 1
                && address(eigenLayerFarmData.tokenLeaves[0].token) == address(rewardToken),
            "EigenLayerAdapter: invalid farm data"
        );
        address isolatedVault = abi.decode(rewardData, (address));
        IIsolatedEigenLayerVault(isolatedVault).processClaim(
            rewardsCoordinator, eigenLayerFarmData, IERC20(rewardToken)
        );
    }

    /// @inheritdoc IProtocolAdapter
    function withdraw(
        address isolatedVault,
        address withdrawalQueue,
        address reciever,
        uint256 request,
        address owner
    ) external delegateCallOnly {
        IIsolatedEigenLayerVault(isolatedVault).withdraw(
            withdrawalQueue, reciever, request, owner == reciever
        );
    }

    /// @inheritdoc IProtocolAdapter
    function deposit(address isolatedVault, uint256 assets) external delegateCallOnly {
        (, address strategy,,) = factory.instances(isolatedVault);
        IERC20 asset_ = IERC20(IERC4626(vault).asset());
        asset_.safeIncreaseAllowance(isolatedVault, assets);
        IIsolatedEigenLayerVault(isolatedVault).deposit(address(strategyManager), strategy, assets);
        if (asset_.allowance(address(this), isolatedVault) != 0) {
            asset_.forceApprove(isolatedVault, 0);
        }
    }

    /// @inheritdoc IProtocolAdapter
    function areWithdrawalsPaused(address isolatedVault, address /* account */ )
        external
        view
        returns (bool)
    {
        IPausable manager = IPausable(address(delegationManager));
        (, address strategy,,) = factory.instances(isolatedVault);
        return manager.paused(PAUSED_ENTER_WITHDRAWAL_QUEUE)
            || manager.paused(PAUSED_EXIT_WITHDRAWAL_QUEUE)
            || IPausable(strategy).paused(PAUSED_WITHDRAWALS);
    }
}
