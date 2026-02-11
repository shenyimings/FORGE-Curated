// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "../interfaces/adapters/ISymbioticAdapter.sol";
import {SymbioticWithdrawalQueue} from "../queues/SymbioticWithdrawalQueue.sol";

contract SymbioticAdapter is ISymbioticAdapter {
    using SafeERC20 for IERC20;

    /// @inheritdoc IProtocolAdapter
    address public immutable vault;
    /// @inheritdoc ISymbioticAdapter
    IRegistry public immutable vaultFactory;

    address public immutable withdrawalQueueSingleton;

    address public immutable proxyAdmin;
    /// @inheritdoc ISymbioticAdapter
    mapping(address symbioticVault => address withdrawalQueue) public withdrawalQueues;

    constructor(
        address vault_,
        address vaultFactory_,
        address withdrawalQueueSingleton_,
        address proxyAdmin_
    ) {
        vault = vault_;
        vaultFactory = IRegistry(vaultFactory_);
        withdrawalQueueSingleton = withdrawalQueueSingleton_;
        proxyAdmin = proxyAdmin_;
    }

    /// @inheritdoc IProtocolAdapter
    function maxDeposit(address symbioticVault) external view returns (uint256) {
        ISymbioticVault vault_ = ISymbioticVault(symbioticVault);
        if (vault_.depositWhitelist() && !vault_.isDepositorWhitelisted(vault)) {
            return 0;
        }
        if (!vault_.isDepositLimit()) {
            return type(uint256).max;
        }
        uint256 activeStake = vault_.activeStake();
        uint256 limit = vault_.depositLimit();
        if (limit > activeStake) {
            return limit - activeStake;
        }
        return 0;
    }

    /// @inheritdoc IProtocolAdapter
    function assetOf(address symbioticVault) external view returns (address) {
        return ISymbioticVault(symbioticVault).collateral();
    }

    /// @inheritdoc IProtocolAdapter
    function stakedAt(address symbioticVault) external view returns (uint256) {
        return ISymbioticVault(symbioticVault).activeBalanceOf(vault);
    }

    /// @inheritdoc IProtocolAdapter
    function handleVault(address symbioticVault) external returns (address withdrawalQueue) {
        require(msg.sender == vault, "SymbioticAdapter: only vault");
        withdrawalQueue = withdrawalQueues[symbioticVault];
        if (withdrawalQueue != address(0)) {
            return withdrawalQueue;
        }
        require(vaultFactory.isEntity(symbioticVault), "SymbioticAdapter: invalid symbiotic vault");
        withdrawalQueue = address(
            new TransparentUpgradeableProxy{salt: keccak256(abi.encodePacked(symbioticVault))}(
                withdrawalQueueSingleton,
                proxyAdmin,
                abi.encodeCall(SymbioticWithdrawalQueue.initialize, (vault, symbioticVault))
            )
        );
        withdrawalQueues[symbioticVault] = withdrawalQueue;
    }

    /// @inheritdoc IProtocolAdapter
    function validateRewardData(bytes calldata data) external pure {
        require(data.length == 32, "SymbioticAdapter: invalid reward data");
        address symbioticFarm = abi.decode(data, (address));
        require(symbioticFarm != address(0), "SymbioticAdapter: invalid reward data");
    }

    /// @inheritdoc IProtocolAdapter
    function pushRewards(address rewardToken, bytes calldata farmData, bytes memory rewardData)
        external
    {
        require(address(this) == vault, "SymbioticAdapter: delegate call only");
        address symbioticFarm = abi.decode(rewardData, (address));
        IStakerRewards(symbioticFarm).claimRewards(vault, address(rewardToken), farmData);
    }

    /// @inheritdoc IProtocolAdapter
    function withdraw(
        address symbioticVault,
        address withdrawalQueue,
        address receiver,
        uint256 request,
        address /* owner */
    ) external {
        require(address(this) == vault, "SymbioticAdapter: delegate call only");
        (, uint256 requestedShares) =
            ISymbioticVault(symbioticVault).withdraw(withdrawalQueue, request);
        ISymbioticWithdrawalQueue(withdrawalQueue).request(receiver, requestedShares);
    }

    /// @inheritdoc IProtocolAdapter
    function deposit(address symbioticVault, uint256 assets) external {
        require(address(this) == vault, "SymbioticAdapter: delegate call only");
        IERC20(IERC4626(vault).asset()).safeIncreaseAllowance(symbioticVault, assets);
        ISymbioticVault(symbioticVault).deposit(vault, assets);
    }

    /// @inheritdoc IProtocolAdapter
    function areWithdrawalsPaused(address, /* symbioticVault */ address /* account */ )
        external
        view
        returns (bool)
    {}
}
