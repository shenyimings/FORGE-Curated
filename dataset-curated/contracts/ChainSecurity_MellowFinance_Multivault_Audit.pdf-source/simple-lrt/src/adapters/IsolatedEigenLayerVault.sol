// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "../interfaces/adapters/IIsolatedEigenLayerVault.sol";

contract IsolatedEigenLayerVault is IIsolatedEigenLayerVault, Initializable {
    using SafeERC20 for IERC20;

    /// @inheritdoc IIsolatedEigenLayerVault
    address public factory;
    /// @inheritdoc IIsolatedEigenLayerVault
    address public vault;
    /// @inheritdoc IIsolatedEigenLayerVault
    address public asset;
    /// @inheritdoc IIsolatedEigenLayerVault
    bool public isDelegated;

    modifier onlyVault() {
        require(msg.sender == vault, "Only vault");
        _;
    }

    constructor() {
        _disableInitializers();
    }

    /// --------------- EXTERNAL MUTABLE FUNCTIONS ---------------

    /// @inheritdoc IIsolatedEigenLayerVault
    function initialize(address vault_) external virtual initializer {
        __init_IsolatedEigenLayerVault(vault_);
    }

    /// @inheritdoc IIsolatedEigenLayerVault
    function delegateTo(
        address manager,
        address operator,
        ISignatureUtils.SignatureWithExpiry memory signature,
        bytes32 salt
    ) external {
        require(!isDelegated, "IsolatedEigenLayerVault: already delegated");
        isDelegated = true;
        IDelegationManager(manager).delegateTo(operator, signature, salt);
    }

    /// @inheritdoc IIsolatedEigenLayerVault
    function deposit(address manager, address strategy, uint256 assets)
        external
        virtual
        onlyVault
    {
        if (IStrategy(strategy).underlyingToSharesView(assets) == 0) {
            // insignificant amount
            return;
        }
        IERC20 asset_ = IERC20(asset);
        asset_.safeTransferFrom(vault, address(this), assets);
        asset_.safeIncreaseAllowance(manager, assets);
        IStrategyManager(manager).depositIntoStrategy(IStrategy(strategy), asset_, assets);
    }

    /// @inheritdoc IIsolatedEigenLayerVault
    function withdraw(address queue, address reciever, uint256 request, bool flag)
        external
        virtual
        onlyVault
    {
        IEigenLayerWithdrawalQueue(queue).request(reciever, request, flag);
    }

    /// @inheritdoc IIsolatedEigenLayerVault
    function processClaim(
        IRewardsCoordinator coodrinator,
        IRewardsCoordinator.RewardsMerkleClaim memory farmData,
        IERC20 rewardToken
    ) external onlyVault {
        address this_ = address(this);
        uint256 rewards = rewardToken.balanceOf(this_);
        coodrinator.processClaim(farmData, this_);
        rewards = rewardToken.balanceOf(this_) - rewards;
        if (rewards != 0) {
            rewardToken.safeTransfer(vault, rewards);
        }
    }

    /// @inheritdoc IIsolatedEigenLayerVault
    function claimWithdrawal(
        IDelegationManager manager,
        IDelegationManager.Withdrawal calldata data
    ) external virtual returns (uint256 assets) {
        address this_ = address(this);
        (,,, address queue) = IIsolatedEigenLayerVaultFactory(factory).instances(this_);
        require(msg.sender == queue, "IsolatedEigenLayerVault: forbidden");
        IERC20 asset_ = IERC20(asset);
        IERC20[] memory tokens = new IERC20[](1);
        tokens[0] = asset_;
        manager.completeQueuedWithdrawal(data, tokens, 0, true);
        assets = asset_.balanceOf(this_);
        asset_.safeTransfer(queue, assets);
    }

    /// @inheritdoc IIsolatedEigenLayerVault
    function queueWithdrawals(
        IDelegationManager manager,
        IDelegationManager.QueuedWithdrawalParams[] calldata requests
    ) external {
        (,,, address queue) = IIsolatedEigenLayerVaultFactory(factory).instances(address(this));
        require(msg.sender == queue, "IsolatedEigenLayerVault: forbidden");
        manager.queueWithdrawals(requests);
    }

    /// --------------- EXTERNAL VIEW FUNCTIONS ---------------

    function sharesToUnderlyingView(address strategy, uint256 shares)
        public
        view
        virtual
        returns (uint256)
    {
        return IStrategy(strategy).sharesToUnderlyingView(shares);
    }

    function underlyingToSharesView(address strategy, uint256 assets)
        public
        view
        virtual
        returns (uint256)
    {
        return IStrategy(strategy).underlyingToSharesView(assets);
    }

    /// --------------- INTERNAL MUTABLE FUNCTIONS ---------------

    function __init_IsolatedEigenLayerVault(address vault_) internal onlyInitializing {
        factory = msg.sender;
        vault = vault_;
        asset = IERC4626(vault_).asset();
    }
}
