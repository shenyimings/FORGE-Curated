// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "../interfaces/vaults/IMultiVault.sol";
import {ERC4626Vault} from "./ERC4626Vault.sol";
import {MultiVaultStorage} from "./MultiVaultStorage.sol";
import {VaultControlStorage} from "./VaultControlStorage.sol";

contract MultiVault is IMultiVault, ERC4626Vault, MultiVaultStorage {
    using SafeERC20 for IERC20;
    using Math for uint256;

    uint256 private constant D6 = 1e6;
    bytes32 public constant ADD_SUBVAULT_ROLE = keccak256("ADD_SUBVAULT_ROLE");
    bytes32 public constant REMOVE_SUBVAULT_ROLE = keccak256("REMOVE_SUBVAULT_ROLE");
    bytes32 public constant SET_STRATEGY_ROLE = keccak256("SET_STRATEGY_ROLE");
    bytes32 public constant SET_FARM_ROLE = keccak256("SET_FARM_ROLE");
    bytes32 public constant REBALANCE_ROLE = keccak256("REBALANCE_ROLE");
    bytes32 public constant SET_DEFAULT_COLLATERAL_ROLE = keccak256("SET_DEFAULT_COLLATERAL_ROLE");
    bytes32 public constant SET_ADAPTER_ROLE = keccak256("SET_ADAPTER_ROLE");

    constructor(bytes32 name_, uint256 version_)
        VaultControlStorage(name_, version_)
        MultiVaultStorage(name_, version_)
    {
        _disableInitializers();
    }

    // ------------------------------- EXTERNAL VIEW FUNCTIONS -------------------------------

    /// @inheritdoc IERC4626
    function totalAssets()
        public
        view
        virtual
        override(IERC4626, ERC4626Upgradeable)
        returns (uint256 assets_)
    {
        address this_ = address(this);
        assets_ = IERC20(asset()).balanceOf(this_);
        IDefaultCollateral collateral = defaultCollateral();
        if (address(collateral) != address(0)) {
            assets_ += collateral.balanceOf(this_);
        }

        uint256 length = subvaultsCount();
        Subvault memory subvault;
        for (uint256 i = 0; i < length; i++) {
            subvault = subvaultAt(i);
            assets_ += adapterOf(subvault.protocol).stakedAt(subvault.vault);
            if (subvault.withdrawalQueue != address(0)) {
                assets_ += IWithdrawalQueue(subvault.withdrawalQueue).claimableAssetsOf(this_)
                    + IWithdrawalQueue(subvault.withdrawalQueue).pendingAssetsOf(this_);
            }
        }
    }

    // ------------------------------- EXTERNAL MUTATIVE FUNCTIONS -------------------------------

    /// @inheritdoc IMultiVault
    function initialize(InitParams calldata initParams) public virtual reinitializer(2) {
        __initializeERC4626(
            initParams.admin,
            initParams.limit,
            initParams.depositPause,
            initParams.withdrawalPause,
            initParams.depositWhitelist,
            initParams.asset,
            initParams.name,
            initParams.symbol
        );
        __initializeMultiVaultStorage(
            initParams.depositStrategy,
            initParams.withdrawalStrategy,
            initParams.rebalanceStrategy,
            initParams.defaultCollateral,
            initParams.symbioticAdapter,
            initParams.eigenLayerAdapter,
            initParams.erc4626Adapter
        );
        require(
            initParams.defaultCollateral == address(0)
                || IDefaultCollateral(initParams.defaultCollateral).asset() == initParams.asset,
            "MultiVault: default collateral asset does not match the vault asset"
        );
    }

    /// @inheritdoc IMultiVault
    function addSubvault(address vault, Protocol protocol) external onlyRole(ADD_SUBVAULT_ROLE) {
        IProtocolAdapter adapter = adapterOf(protocol);
        require(
            adapter.assetOf(vault) == asset(),
            "MultiVault: subvault asset does not match the vault asset"
        );
        _addSubvault(vault, adapter.handleVault(vault), protocol);
    }

    /// @inheritdoc IMultiVault
    function removeSubvault(address subvault) external onlyRole(REMOVE_SUBVAULT_ROLE) {
        _removeSubvault(subvault);
    }

    /// @inheritdoc IMultiVault
    function setDepositStrategy(address newDepositStrategy) external onlyRole(SET_STRATEGY_ROLE) {
        require(
            newDepositStrategy != address(0), "MultiVault: deposit strategy cannot be zero address"
        );
        _setDepositStrategy(newDepositStrategy);
    }

    /// @inheritdoc IMultiVault
    function setWithdrawalStrategy(address newWithdrawalStrategy)
        external
        onlyRole(SET_STRATEGY_ROLE)
    {
        require(
            newWithdrawalStrategy != address(0),
            "MultiVault: withdrawal strategy cannot be zero address"
        );
        _setWithdrawalStrategy(newWithdrawalStrategy);
    }

    /// @inheritdoc IMultiVault
    function setRebalanceStrategy(address newRebalanceStrategy)
        external
        onlyRole(SET_STRATEGY_ROLE)
    {
        require(
            newRebalanceStrategy != address(0),
            "MultiVault: rebalance strategy cannot be zero address"
        );
        _setRebalanceStrategy(newRebalanceStrategy);
    }

    /// @inheritdoc IMultiVault
    function setDefaultCollateral(address defaultCollateral_)
        external
        onlyRole(SET_DEFAULT_COLLATERAL_ROLE)
    {
        require(
            address(defaultCollateral()) == address(0) && defaultCollateral_ != address(0),
            "MultiVault: default collateral already set or cannot be zero address"
        );
        require(
            IDefaultCollateral(defaultCollateral_).asset() == asset(),
            "MultiVault: default collateral asset does not match the vault asset"
        );
        _setDefaultCollateral(defaultCollateral_);
    }

    /// @inheritdoc IMultiVault
    function setSymbioticAdapter(address adapter_) external onlyRole(SET_ADAPTER_ROLE) {
        require(adapter_ != address(0), "MultiVault: adapter cannot be zero address");
        _setSymbioticAdapter(adapter_);
    }

    /// @inheritdoc IMultiVault
    function setEigenLayerAdapter(address adapter_) external onlyRole(SET_ADAPTER_ROLE) {
        require(adapter_ != address(0), "MultiVault: adapter cannot be zero address");
        _setEigenLayerAdapter(adapter_);
    }

    /// @inheritdoc IMultiVault
    function setERC4626Adapter(address adapter_) external onlyRole(SET_ADAPTER_ROLE) {
        require(adapter_ != address(0), "MultiVault: adapter cannot be zero address");
        _setERC4626Adapter(adapter_);
    }

    /// @inheritdoc IMultiVault
    function setRewardsData(uint256 farmId, RewardData calldata rewardData)
        external
        onlyRole(SET_FARM_ROLE)
    {
        if (rewardData.token != address(0)) {
            require(
                rewardData.token != asset() && rewardData.token != address(defaultCollateral()),
                "MultiVault: reward token cannot be the same as the asset or default collateral"
            );
            require(rewardData.curatorFeeD6 <= D6, "MultiVault: curator fee exceeds 100%");
            require(
                rewardData.distributionFarm != address(0),
                "MultiVault: distribution farm address cannot be zero"
            );
            if (rewardData.curatorFeeD6 != 0) {
                require(
                    rewardData.curatorTreasury != address(0),
                    "MultiVault: curator treasury address cannot be zero when fee is set"
                );
            }
            adapterOf(rewardData.protocol).validateRewardData(rewardData.data);
        }
        _setRewardData(farmId, rewardData);
    }

    /// @inheritdoc IMultiVault
    function rebalance() external onlyRole(REBALANCE_ROLE) {
        address this_ = address(this);
        IRebalanceStrategy.RebalanceData[] memory data =
            rebalanceStrategy().calculateRebalanceAmounts(this_);
        for (uint256 i = 0; i < data.length; i++) {
            _withdraw(data[i].subvaultIndex, data[i].staked, 0, data[i].claimable, this_, this_);
        }
        IDefaultCollateral collateral = defaultCollateral();
        if (address(collateral) != address(0)) {
            uint256 balance = collateral.balanceOf(this_);
            if (balance != 0) {
                collateral.withdraw(this_, balance);
            }
        }
        for (uint256 i = 0; i < data.length; i++) {
            _deposit(data[i].subvaultIndex, data[i].deposit);
        }
        _depositIntoCollateral();
        emit Rebalance(data, block.timestamp);
    }

    /// @inheritdoc IMultiVault
    function pushRewards(uint256 farmId, bytes calldata farmData) external nonReentrant {
        require(farmIdsContains(farmId), "MultiVault: farm not found");
        IMultiVaultStorage.RewardData memory data = rewardData(farmId);
        IERC20 rewardToken = IERC20(data.token);

        address this_ = address(this);
        uint256 rewardAmount = rewardToken.balanceOf(this_);

        Address.functionDelegateCall(
            address(adapterOf(data.protocol)),
            abi.encodeCall(
                IProtocolAdapter.pushRewards, (address(rewardToken), farmData, data.data)
            )
        );

        rewardAmount = rewardToken.balanceOf(this_) - rewardAmount;
        if (rewardAmount == 0) {
            return;
        }

        uint256 curatorFee = rewardAmount.mulDiv(data.curatorFeeD6, D6);
        if (curatorFee != 0) {
            rewardToken.safeTransfer(data.curatorTreasury, curatorFee);
        }
        rewardAmount = rewardAmount - curatorFee;
        if (rewardAmount != 0) {
            rewardToken.safeTransfer(data.distributionFarm, rewardAmount);
        }
        emit RewardsPushed(farmId, rewardAmount, curatorFee, block.timestamp);
    }

    // ------------------------------- INTERNAL MUTATIVE FUNCTIONS -------------------------------

    /// @dev Deposits assets into the specified subvault
    function _deposit(uint256 subvaultIndex, uint256 assets) private {
        if (assets == 0) {
            return;
        }
        Subvault memory subvault = subvaultAt(subvaultIndex);
        Address.functionDelegateCall(
            address(adapterOf(subvault.protocol)),
            abi.encodeCall(IProtocolAdapter.deposit, (subvault.vault, assets))
        );
    }

    /// @dev Withdraws assets from the specified subvault
    function _withdraw(
        uint256 subvaultIndex,
        uint256 request,
        uint256 pending,
        uint256 claimable,
        address owner,
        address receiver
    ) private {
        Subvault memory subvault = subvaultAt(subvaultIndex);
        address this_ = address(this);
        if (claimable != 0) {
            IWithdrawalQueue(subvault.withdrawalQueue).claim(this_, receiver, claimable);
        }
        if (pending != 0) {
            IWithdrawalQueue(subvault.withdrawalQueue).transferPendingAssets(receiver, pending);
        }
        if (request != 0) {
            Address.functionDelegateCall(
                address(adapterOf(subvault.protocol)),
                abi.encodeCall(
                    IProtocolAdapter.withdraw,
                    (subvault.vault, subvault.withdrawalQueue, receiver, request, owner)
                )
            );
        }
    }

    /// @dev Deposits assets into the default collateral
    function _depositIntoCollateral() private {
        IDefaultCollateral collateral = defaultCollateral();
        if (address(collateral) == address(0)) {
            return;
        }
        uint256 limit_ = collateral.limit();
        uint256 supply_ = collateral.totalSupply();
        if (supply_ >= limit_) {
            return;
        }
        address this_ = address(this);
        IERC20 asset_ = IERC20(asset());
        uint256 assets = asset_.balanceOf(this_).min(limit_ - supply_);
        if (assets == 0) {
            return;
        }
        asset_.safeIncreaseAllowance(address(collateral), assets);
        collateral.deposit(this_, assets);
        emit DepositIntoCollateral(assets);
    }

    function _deposit(address caller, address receiver, uint256 assets, uint256 shares)
        internal
        virtual
        override
    {
        address this_ = address(this);
        IDepositStrategy.DepositData[] memory data =
            depositStrategy().calculateDepositAmounts(this_, assets);
        super._deposit(caller, receiver, assets, shares);
        for (uint256 i = 0; i < data.length; i++) {
            if (data[i].deposit != 0) {
                _deposit(data[i].subvaultIndex, data[i].deposit);
                assets -= data[i].deposit;
            }
        }

        _depositIntoCollateral();
    }

    function _withdraw(
        address caller,
        address receiver,
        address owner,
        uint256 assets,
        uint256 shares
    ) internal virtual override {
        address this_ = address(this);

        IWithdrawalStrategy.WithdrawalData[] memory data =
            withdrawalStrategy().calculateWithdrawalAmounts(this_, assets);

        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }

        _burn(owner, shares);

        uint256 liquid = assets;
        IWithdrawalStrategy.WithdrawalData memory d;
        for (uint256 i = 0; i < data.length; i++) {
            d = data[i];
            _withdraw(d.subvaultIndex, d.staked, d.pending, d.claimable, owner, receiver);
            liquid -= d.staked + d.pending + d.claimable;
        }

        if (liquid != 0) {
            IERC20 asset_ = IERC20(asset());
            uint256 balance = asset_.balanceOf(this_);
            if (balance < liquid) {
                if (balance != 0) {
                    asset_.safeTransfer(receiver, balance);
                    liquid -= balance;
                }
                defaultCollateral().withdraw(receiver, liquid);
            } else {
                asset_.safeTransfer(receiver, liquid);
            }
        }

        // emitting event with transferred + new pending assets
        emit Withdraw(caller, receiver, owner, assets, shares);
    }
}
