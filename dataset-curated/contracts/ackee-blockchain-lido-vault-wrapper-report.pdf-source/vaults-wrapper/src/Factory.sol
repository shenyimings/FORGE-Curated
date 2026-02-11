// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ShortString, ShortStrings} from "@openzeppelin/contracts/utils/ShortStrings.sol";

import {StvPool} from "./StvPool.sol";
import {StvStETHPool} from "./StvStETHPool.sol";
import {WithdrawalQueue} from "./WithdrawalQueue.sol";
import {DistributorFactory} from "./factories/DistributorFactory.sol";
import {StvPoolFactory} from "./factories/StvPoolFactory.sol";
import {StvStETHPoolFactory} from "./factories/StvStETHPoolFactory.sol";
import {TimelockFactory} from "./factories/TimelockFactory.sol";
import {WithdrawalQueueFactory} from "./factories/WithdrawalQueueFactory.sol";
import {IStrategy} from "./interfaces/IStrategy.sol";
import {IStrategyFactory} from "./interfaces/IStrategyFactory.sol";
import {ILidoLocator} from "./interfaces/core/ILidoLocator.sol";
import {IVaultHub} from "./interfaces/core/IVaultHub.sol";
import {DummyImplementation} from "./proxy/DummyImplementation.sol";
import {OssifiableProxy} from "./proxy/OssifiableProxy.sol";

import {IDashboard} from "./interfaces/core/IDashboard.sol";
import {IVaultFactory} from "./interfaces/core/IVaultFactory.sol";

/**
 * @title Factory
 * @notice Main factory contract for deploying complete pool ecosystems with vaults, withdrawal queues, distributors, etc
 * @dev Implements a two-phase deployment process (start/finish) to ensure robust setup of all components and roles
 */
contract Factory {
    //
    // Structs
    //

    /**
     * @notice Addresses of all sub-factory contracts used for deploying components
     * @param stvPoolFactory Factory for deploying StvPool implementations
     * @param stvStETHPoolFactory Factory for deploying StvStETHPool implementations
     * @param withdrawalQueueFactory Factory for deploying WithdrawalQueue implementations
     * @param distributorFactory Factory for deploying Distributor implementations
     * @param timelockFactory Factory for deploying Timelock controllers
     */
    struct SubFactories {
        address stvPoolFactory;
        address stvStETHPoolFactory;
        address withdrawalQueueFactory;
        address distributorFactory;
        address timelockFactory;
    }

    /**
     * @notice Configuration parameters for vault creation
     * @param nodeOperator Address of the node operator managing the vault
     * @param nodeOperatorManager Address authorized to manage node operator settings
     * @param nodeOperatorFeeBP Node operator fee in basis points (1 BP = 0.01%)
     * @param confirmExpiry Time period for confirmation expiry
     */
    struct VaultConfig {
        address nodeOperator;
        address nodeOperatorManager;
        uint256 nodeOperatorFeeBP;
        uint256 confirmExpiry;
    }

    /**
     * @notice Configuration for timelock controller deployment
     * @param minDelaySeconds Minimum delay before executing queued operations
     * @param proposer Address authorized to propose operations
     * @param executor Address authorized to execute operations
     */
    struct TimelockConfig {
        uint256 minDelaySeconds;
        address proposer;
        address executor;
    }

    /**
     * @notice Common configuration shared across all pool types
     * @param minWithdrawalDelayTime Minimum delay time for processing withdrawals
     * @param name ERC20 token name for the pool shares
     * @param symbol ERC20 token symbol for the pool shares
     * @param emergencyCommittee Address of the emergency committee
     */
    struct CommonPoolConfig {
        uint256 minWithdrawalDelayTime;
        string name;
        string symbol;
        address emergencyCommittee;
    }

    /**
     * @notice Configuration specific to StvStETH pools (deprecated, kept for compatibility)
     * @param allowListEnabled Whether the pool requires allowlist for deposits
     * @param reserveRatioGapBP Maximum allowed gap in reserve ratio in basis points
     */
    struct StvStETHPoolConfig {
        bool allowListEnabled;
        uint256 reserveRatioGapBP;
    }

    /**
     * @notice Extended configuration for pools with minting or strategy capabilities
     * @param allowListEnabled Whether the pool requires allowlist for deposits
     * @param allowListManager Address to be granted ALLOW_LIST_MANAGER_ROLE (ignored for strategy pools)
     * @param mintingEnabled Whether the pool can mint stETH tokens
     * @param reserveRatioGapBP Maximum allowed gap in reserve ratio in basis points
     */
    struct AuxiliaryPoolConfig {
        bool allowListEnabled;
        address allowListManager;
        bool mintingEnabled;
        uint256 reserveRatioGapBP;
    }

    /**
     * @notice Intermediate state returned by deployment start functions
     * @param dashboard Address of the deployed dashboard
     * @param poolProxy Address of the deployed pool proxy (not yet initialized)
     * @param poolImpl Address of the deployed pool implementation (not yet initialized)
     * @param withdrawalQueueProxy Address of the deployed withdrawal queue proxy (not yet initialized)
     * @param wqImpl Address of the deployed withdrawal queue implementation (not yet initialized)
     * @param timelock Address of the deployed timelock controller
     */
    struct PoolIntermediate {
        address dashboard;
        address poolProxy;
        address poolImpl;
        address withdrawalQueueProxy;
        address wqImpl;
        address timelock;
    }

    /**
     * @notice Complete deployment result returned by createPoolFinish
     * @param poolType Type identifier for the pool (StvPool, StvStETHPool, or StvStrategyPool)
     * @param vault Address of the deployed vault (staking vault)
     * @param dashboard Address of the deployed dashboard (manages vault roles and interactions)
     * @param pool Address of the deployed pool (initialized with ERC20 token functionality)
     * @param withdrawalQueue Address of the deployed withdrawal queue (handles withdrawal requests)
     * @param distributor Address of the deployed distributor (handles fee distribution)
     * @param timelock Address of the deployed timelock controller (admin for all components)
     * @param strategy Address of the deployed strategy (zero if not using strategies)
     */
    struct PoolDeployment {
        bytes32 poolType;
        address vault;
        address dashboard;
        address pool;
        address withdrawalQueue;
        address distributor;
        address timelock;
        address strategy;
    }

    //
    // Events
    //

    /**
     * @notice Emitted when pool deployment is initiated in the start phase
     * @param sender Address that initiated the deployment (msg.sender)
     * @param vaultConfig Configuration for the vault
     * @param commonPoolConfig Common pool parameters
     * @param auxiliaryConfig Additional pool configuration
     * @param timelockConfig Configuration for the timelock controller
     * @param strategyFactory Address of strategy factory (zero if not using strategies)
     * @param strategyDeployBytes ABI-encoded parameters for strategy deployment (empty if no strategy)
     * @param intermediate Contains addresses of deployed components (dashboard, pool proxy, withdrawal queue proxy, timelock) needed for finish phase
     * @param finishDeadline Timestamp by which createPoolFinish must be called (inclusive)
     */
    event PoolCreationStarted(
        address indexed sender,
        VaultConfig vaultConfig,
        CommonPoolConfig commonPoolConfig,
        AuxiliaryPoolConfig auxiliaryConfig,
        TimelockConfig timelockConfig,
        address indexed strategyFactory,
        bytes strategyDeployBytes,
        PoolIntermediate intermediate,
        uint256 finishDeadline
    );

    /**
     * @notice Emitted when pool deployment is completed in the finish phase
     * @param vault Address of the deployed vault
     * @param pool Address of the deployed pool
     * @param poolType Type identifier for the pool (StvPool, StvStETHPool, or StvStrategyPool)
     * @param withdrawalQueue Address of the deployed withdrawal queue
     * @param strategyFactory Address of the strategy factory used (zero if none)
     * @param strategyDeployBytes ABI-encoded parameters used for strategy deployment (empty if no strategy)
     * @param strategy Address of the deployed strategy (zero if not using strategies)
     */
    event PoolCreated(
        address vault,
        address pool,
        bytes32 indexed poolType,
        address withdrawalQueue,
        address indexed strategyFactory,
        bytes strategyDeployBytes,
        address strategy
    );

    //
    // Custom errors
    //

    /**
     * @notice Thrown when configuration parameters are invalid or inconsistent
     * @param reason Human-readable description of the configuration error
     */
    error InvalidConfiguration(string reason);

    /**
     * @notice Thrown when insufficient ETH is sent for the vault connection deposit
     * @param provided Amount of ETH provided in msg.value
     * @param required Required amount for VAULT_HUB.CONNECT_DEPOSIT()
     */
    error InsufficientConnectDeposit(uint256 provided, uint256 required);

    //
    // Constants and immutables
    //

    /**
     * @notice Lido vault factory for creating vaults and dashboards
     */
    IVaultFactory public immutable VAULT_FACTORY;

    /**
     * @notice Lido V3 VaultHub (cached from LidoLocator for gas cost reduction)
     */
    IVaultHub public immutable VAULT_HUB;

    /**
     * @notice Lido stETH token address (cached from LidoLocator for gas cost reduction)
     */
    address public immutable STETH;

    /**
     * @notice Lido wstETH token address (cached from LidoLocator for gas cost reduction)
     */
    address public immutable WSTETH;

    /**
     * @notice Lido V3 LazyOracle (cached from LidoLocator for gas cost reduction)
     */
    address public immutable LAZY_ORACLE;

    /**
     * @notice Pool type identifier for basic StvPool
     */
    bytes32 public immutable STV_POOL_TYPE;

    /**
     * @notice Pool type identifier for StvStETHPool with minting capabilities
     */
    bytes32 public immutable STV_STETH_POOL_TYPE;

    /**
     * @notice Pool type identifier for StvStrategyPool with strategy integration
     */
    bytes32 public immutable STRATEGY_POOL_TYPE;

    /**
     * @notice Factory for deploying StvPool implementations
     */
    StvPoolFactory public immutable STV_POOL_FACTORY;

    /**
     * @notice Factory for deploying StvStETHPool implementations
     */
    StvStETHPoolFactory public immutable STV_STETH_POOL_FACTORY;

    /**
     * @notice Factory for deploying WithdrawalQueue implementations
     */
    WithdrawalQueueFactory public immutable WITHDRAWAL_QUEUE_FACTORY;

    /**
     * @notice Factory for deploying Distributor implementations
     */
    DistributorFactory public immutable DISTRIBUTOR_FACTORY;

    /**
     * @notice Factory for deploying Timelock controllers
     */
    TimelockFactory public immutable TIMELOCK_FACTORY;

    /**
     * @notice Dummy implementation used for temporary proxy initialization
     */
    address public immutable DUMMY_IMPLEMENTATION;

    /**
     * @notice Default admin role identifier (keccak256("") = 0x00)
     */
    bytes32 public immutable DEFAULT_ADMIN_ROLE = 0x00;

    /**
     * @notice Maximum time allowed between start and finish deployment phases
     */
    uint256 public constant DEPLOY_START_FINISH_SPAN_SECONDS = 1 days;

    /**
     * @notice Sentinel value marking a deployment as complete
     */
    uint256 public constant DEPLOY_FINISHED = type(uint256).max;

    //
    // Structured storage
    //

    /**
     * @notice Tracks deployment state by hash of intermediate state and sender
     * @dev Maps deployment hash to finish deadline (0 = not started, DEPLOY_FINISHED = finished)
     */
    mapping(bytes32 => uint256) public intermediateState;

    /**
     * @notice Initializes the factory with Lido locator and sub-factory addresses
     * @param _locatorAddress Address of the Lido locator contract containing core protocol addresses
     * @param _subFactories Struct containing addresses of all required sub-factory contracts
     */
    constructor(address _locatorAddress, SubFactories memory _subFactories) {
        ILidoLocator locator = ILidoLocator(_locatorAddress);
        VAULT_FACTORY = IVaultFactory(locator.vaultFactory());
        STETH = address(locator.lido());
        WSTETH = address(locator.wstETH());
        LAZY_ORACLE = locator.lazyOracle();
        VAULT_HUB = IVaultHub(locator.vaultHub());

        STV_POOL_FACTORY = StvPoolFactory(_subFactories.stvPoolFactory);
        STV_STETH_POOL_FACTORY = StvStETHPoolFactory(_subFactories.stvStETHPoolFactory);
        WITHDRAWAL_QUEUE_FACTORY = WithdrawalQueueFactory(_subFactories.withdrawalQueueFactory);
        DISTRIBUTOR_FACTORY = DistributorFactory(_subFactories.distributorFactory);
        TIMELOCK_FACTORY = TimelockFactory(_subFactories.timelockFactory);

        DUMMY_IMPLEMENTATION = address(new DummyImplementation());

        STV_POOL_TYPE = ShortString.unwrap(ShortStrings.toShortString("StvPool"));
        STV_STETH_POOL_TYPE = ShortString.unwrap(ShortStrings.toShortString("StvStETHPool"));
        STRATEGY_POOL_TYPE = ShortString.unwrap(ShortStrings.toShortString("StvStrategyPool"));
    }

    /**
     * @notice Initiates deployment of a basic StvPool (first phase)
     * @param _vaultConfig Configuration for the vault
     * @param _timelockConfig Configuration for the timelock controller
     * @param _commonPoolConfig Common pool parameters (name, symbol, withdrawal delay)
     * @param _allowListEnabled Whether to enable allowlist for deposits
     * @param _allowListManager Address to be granted ALLOW_LIST_MANAGER_ROLE
     * @return intermediate Deployment state needed for finish phase
     * @dev ETH for vault connection deposit should be sent in createPoolFinish
     */
    function createPoolStvStart(
        VaultConfig memory _vaultConfig,
        TimelockConfig memory _timelockConfig,
        CommonPoolConfig memory _commonPoolConfig,
        bool _allowListEnabled,
        address _allowListManager
    ) external returns (PoolIntermediate memory intermediate) {
        AuxiliaryPoolConfig memory _auxiliaryPoolConfig = AuxiliaryPoolConfig({
            allowListEnabled: _allowListEnabled,
            allowListManager: _allowListManager,
            mintingEnabled: false,
            reserveRatioGapBP: 0
        });
        intermediate =
            createPoolStart(_vaultConfig, _timelockConfig, _commonPoolConfig, _auxiliaryPoolConfig, address(0), "");
    }

    /**
     * @notice Initiates deployment of an StvStETHPool with minting capabilities (first phase)
     * @param _vaultConfig Configuration for the vault
     * @param _timelockConfig Configuration for the timelock controller
     * @param _commonPoolConfig Common pool parameters (name, symbol, withdrawal delay)
     * @param _allowListEnabled Whether to enable allowlist for deposits
     * @param _allowListManager Address to be granted ALLOW_LIST_MANAGER_ROLE
     * @param _reserveRatioGapBP Maximum allowed reserve ratio gap in basis points
     * @return intermediate Deployment state needed for finish phase
     * @dev ETH for vault connection deposit should be sent in createPoolFinish
     */
    function createPoolStvStETHStart(
        VaultConfig memory _vaultConfig,
        TimelockConfig memory _timelockConfig,
        CommonPoolConfig memory _commonPoolConfig,
        bool _allowListEnabled,
        address _allowListManager,
        uint256 _reserveRatioGapBP
    ) external returns (PoolIntermediate memory intermediate) {
        AuxiliaryPoolConfig memory _auxiliaryPoolConfig = AuxiliaryPoolConfig({
            allowListEnabled: _allowListEnabled,
            allowListManager: _allowListManager,
            mintingEnabled: true,
            reserveRatioGapBP: _reserveRatioGapBP
        });

        intermediate =
            createPoolStart(_vaultConfig, _timelockConfig, _commonPoolConfig, _auxiliaryPoolConfig, address(0), "");
    }

    /**
     * @notice Generic pool deployment start function (first phase)
     * @param _vaultConfig Configuration for the vault
     * @param _timelockConfig Configuration for the timelock controller
     * @param _commonPoolConfig Common pool parameters
     * @param _auxiliaryConfig Additional pool configuration
     * @param _strategyFactory Address of strategy factory (zero for pools without strategy)
     * @param _strategyDeployBytes ABI-encoded parameters for strategy deployment
     * @return intermediate Deployment state required to finish deployment createPoolFinish call
     * @dev This is the main deployment function called by all pool-specific start functions
     * @dev ETH for vault connection deposit should be sent in createPoolFinish
     * @dev Must be followed by createPoolFinish within DEPLOY_START_FINISH_SPAN_SECONDS
     */
    function createPoolStart(
        VaultConfig memory _vaultConfig,
        TimelockConfig memory _timelockConfig,
        CommonPoolConfig memory _commonPoolConfig,
        AuxiliaryPoolConfig memory _auxiliaryConfig,
        address _strategyFactory,
        bytes memory _strategyDeployBytes
    ) public returns (PoolIntermediate memory intermediate) {
        if (bytes(_commonPoolConfig.name).length == 0 || bytes(_commonPoolConfig.symbol).length == 0) {
            revert InvalidConfiguration("name and symbol must be set");
        }

        // Validate allowListManager configuration
        // For strategy pools, allowListManager is ignored so we don't validate it
        if (_strategyFactory == address(0)) {
            if (_auxiliaryConfig.allowListEnabled && _auxiliaryConfig.allowListManager == address(0)) {
                revert InvalidConfiguration("allowListManager must be set when allowlist is enabled");
            }
            if (!_auxiliaryConfig.allowListEnabled && _auxiliaryConfig.allowListManager != address(0)) {
                revert InvalidConfiguration("allowListManager must be zero when allowlist is disabled");
            }
        }

        // Validate proposer and executor addresses
        if (_timelockConfig.proposer == address(0)) {
            revert InvalidConfiguration("proposer must not be zero address");
        }
        if (_timelockConfig.executor == address(0)) {
            revert InvalidConfiguration("executor must not be zero address");
        }

        address timelock = TIMELOCK_FACTORY.deploy(
            _timelockConfig.minDelaySeconds, _timelockConfig.proposer, _timelockConfig.executor
        );

        address tempAdmin = address(this);

        address poolProxy = payable(address(new OssifiableProxy(DUMMY_IMPLEMENTATION, tempAdmin, bytes(""))));
        address wqProxy = payable(address(new OssifiableProxy(DUMMY_IMPLEMENTATION, tempAdmin, bytes(""))));

        (, address dashboardAddress) = VAULT_FACTORY.createVaultWithDashboardWithoutConnectingToVaultHub(
            tempAdmin,
            _vaultConfig.nodeOperator,
            _vaultConfig.nodeOperatorManager,
            _vaultConfig.nodeOperatorFeeBP,
            _vaultConfig.confirmExpiry,
            new IVaultFactory.RoleAssignment[](0)
        );

        address wqImpl = WITHDRAWAL_QUEUE_FACTORY.deploy(
            poolProxy,
            dashboardAddress,
            address(VAULT_HUB),
            STETH,
            address(IDashboard(payable(dashboardAddress)).stakingVault()),
            LAZY_ORACLE,
            _commonPoolConfig.minWithdrawalDelayTime,
            _auxiliaryConfig.mintingEnabled
        );

        address distributor = DISTRIBUTOR_FACTORY.deploy(timelock, _vaultConfig.nodeOperatorManager);

        bytes32 poolType = derivePoolType(_auxiliaryConfig, _strategyFactory);
        address poolImpl = address(0);
        if (poolType == STV_POOL_TYPE) {
            poolImpl = STV_POOL_FACTORY.deploy(
                dashboardAddress, _auxiliaryConfig.allowListEnabled, wqProxy, distributor, poolType
            );
        } else if (poolType == STV_STETH_POOL_TYPE || poolType == STRATEGY_POOL_TYPE) {
            poolImpl = STV_STETH_POOL_FACTORY.deploy(
                dashboardAddress,
                _auxiliaryConfig.allowListEnabled,
                _auxiliaryConfig.reserveRatioGapBP,
                wqProxy,
                distributor,
                poolType
            );
        } else {
            assert(false);
        }

        intermediate = PoolIntermediate({
            dashboard: dashboardAddress,
            poolProxy: poolProxy,
            poolImpl: poolImpl,
            withdrawalQueueProxy: wqProxy,
            wqImpl: wqImpl,
            timelock: timelock
        });

        bytes32 deploymentHash = _hashDeploymentConfiguration(
            msg.sender,
            _vaultConfig,
            _commonPoolConfig,
            _auxiliaryConfig,
            _timelockConfig,
            _strategyFactory,
            _strategyDeployBytes,
            intermediate
        );
        uint256 finishDeadline = block.timestamp + DEPLOY_START_FINISH_SPAN_SECONDS;
        intermediateState[deploymentHash] = finishDeadline;

        emit PoolCreationStarted(
            msg.sender,
            _vaultConfig,
            _commonPoolConfig,
            _auxiliaryConfig,
            _timelockConfig,
            _strategyFactory,
            _strategyDeployBytes,
            intermediate,
            finishDeadline
        );
    }

    /**
     * @notice Completes pool deployment (second phase)
     *         Requires at least `VAULT_HUB.CONNECT_DEPOSIT()` ether sent with the transaction.
     *
     *         All ether sent above `CONNECT_DEPOSIT` is used the same way as `CONNECT_DEPOSIT`
     *         amount: corresponding STV is minted to the pool contract, available for
     *         retrieval upon pool shutdown. Increased connect deposit value would increase
     *         vault's health factor sustainability.
     * @param _vaultConfig Configuration for the vault (must match createPoolStart)
     * @param _timelockConfig Configuration for the timelock controller (must match createPoolStart)
     * @param _commonPoolConfig Common pool parameters (must match createPoolStart)
     * @param _auxiliaryConfig Additional pool configuration (must match createPoolStart)
     * @param _strategyFactory Address of strategy factory (must match createPoolStart)
     * @param _strategyDeployBytes ABI-encoded parameters for strategy deployment (must match createPoolStart)
     * @param _intermediate Deployment state returned by createPoolStart
     * @return deployment Complete deployment information with all component addresses
     * @dev Must be called by the same address that called createPoolStart
     * @dev Must be called within DEPLOY_START_FINISH_SPAN_SECONDS of start
     * @dev All parameters must exactly match those used in createPoolStart
     * @dev Requires msg.value >= VAULT_HUB.CONNECT_DEPOSIT() for vault connection
     */
    function createPoolFinish(
        VaultConfig memory _vaultConfig,
        TimelockConfig memory _timelockConfig,
        CommonPoolConfig memory _commonPoolConfig,
        AuxiliaryPoolConfig memory _auxiliaryConfig,
        address _strategyFactory,
        bytes memory _strategyDeployBytes,
        PoolIntermediate calldata _intermediate
    ) external payable returns (PoolDeployment memory deployment) {
        if (msg.value < VAULT_HUB.CONNECT_DEPOSIT()) {
            revert InsufficientConnectDeposit(msg.value, VAULT_HUB.CONNECT_DEPOSIT());
        }

        bytes32 deploymentHash = _hashDeploymentConfiguration(
            msg.sender,
            _vaultConfig,
            _commonPoolConfig,
            _auxiliaryConfig,
            _timelockConfig,
            _strategyFactory,
            _strategyDeployBytes,
            _intermediate
        );
        uint256 finishDeadline = intermediateState[deploymentHash];
        if (finishDeadline == 0) {
            revert InvalidConfiguration("deploy not started");
        } else if (finishDeadline == DEPLOY_FINISHED) {
            revert InvalidConfiguration("deploy already finished");
        }
        if (block.timestamp > finishDeadline) {
            revert InvalidConfiguration("deploy finish deadline passed");
        }
        intermediateState[deploymentHash] = DEPLOY_FINISHED;

        address tempAdmin = address(this);

        IDashboard dashboard = IDashboard(payable(_intermediate.dashboard));

        dashboard.connectToVaultHub{value: msg.value}();

        address wqImpl = _intermediate.wqImpl;
        address poolImpl = _intermediate.poolImpl;

        OssifiableProxy(payable(_intermediate.poolProxy))
            .proxy__upgradeToAndCall(
                poolImpl,
                abi.encodeCall(StvPool.initialize, (tempAdmin, _commonPoolConfig.name, _commonPoolConfig.symbol))
            );
        OssifiableProxy(payable(_intermediate.poolProxy)).proxy__changeAdmin(_intermediate.timelock);

        OssifiableProxy(payable(_intermediate.withdrawalQueueProxy))
            .proxy__upgradeToAndCall(
                wqImpl,
                abi.encodeCall(
                    WithdrawalQueue.initialize,
                    (
                        _intermediate.timelock,
                        _vaultConfig.nodeOperator,
                        _commonPoolConfig.emergencyCommittee,
                        _commonPoolConfig.emergencyCommittee
                    )
                )
            );
        OssifiableProxy(payable(_intermediate.withdrawalQueueProxy)).proxy__changeAdmin(_intermediate.timelock);

        StvPool pool = StvPool(payable(_intermediate.poolProxy));
        WithdrawalQueue withdrawalQueue = WithdrawalQueue(payable(_intermediate.withdrawalQueueProxy));

        address strategyProxy = address(0);
        if (_strategyFactory != address(0)) {
            address strategyImpl = IStrategyFactory(_strategyFactory).deploy(address(pool), _strategyDeployBytes);
            strategyProxy = address(
                new OssifiableProxy(
                    strategyImpl,
                    _intermediate.timelock,
                    abi.encodeCall(IStrategy.initialize, (_intermediate.timelock, _commonPoolConfig.emergencyCommittee))
                )
            );
            pool.addToAllowList(strategyProxy);
        }

        if (_commonPoolConfig.emergencyCommittee != address(0)) {
            pool.grantRole(pool.DEPOSITS_PAUSE_ROLE(), _commonPoolConfig.emergencyCommittee);
            if (_auxiliaryConfig.mintingEnabled) {
                StvStETHPool stvStETHPool = StvStETHPool(payable(address(pool)));
                stvStETHPool.grantRole(stvStETHPool.MINTING_PAUSE_ROLE(), _commonPoolConfig.emergencyCommittee);
            }
        }

        if (_auxiliaryConfig.allowListEnabled) {
            if (_strategyFactory == address(0)) {
                pool.grantRole(pool.ALLOW_LIST_MANAGER_ROLE(), _auxiliaryConfig.allowListManager);
            }
            pool.revokeRole(pool.ALLOW_LIST_MANAGER_ROLE(), tempAdmin);
        }

        pool.grantRole(DEFAULT_ADMIN_ROLE, _intermediate.timelock);
        pool.revokeRole(DEFAULT_ADMIN_ROLE, tempAdmin);

        dashboard.grantRole(dashboard.FUND_ROLE(), _intermediate.poolProxy);
        dashboard.grantRole(dashboard.REBALANCE_ROLE(), _intermediate.poolProxy);
        dashboard.grantRole(dashboard.WITHDRAW_ROLE(), _intermediate.withdrawalQueueProxy);
        if (_auxiliaryConfig.mintingEnabled) {
            dashboard.grantRole(dashboard.MINT_ROLE(), _intermediate.poolProxy);
            dashboard.grantRole(dashboard.BURN_ROLE(), _intermediate.poolProxy);
        }
        if (address(0) != _commonPoolConfig.emergencyCommittee) {
            dashboard.grantRole(dashboard.PAUSE_BEACON_CHAIN_DEPOSITS_ROLE(), _commonPoolConfig.emergencyCommittee);
        }

        dashboard.grantRole(DEFAULT_ADMIN_ROLE, _intermediate.timelock);
        dashboard.revokeRole(DEFAULT_ADMIN_ROLE, tempAdmin);

        deployment = PoolDeployment({
            poolType: derivePoolType(_auxiliaryConfig, _strategyFactory),
            vault: address(dashboard.stakingVault()),
            dashboard: address(dashboard),
            pool: address(pool),
            withdrawalQueue: address(withdrawalQueue),
            distributor: address(pool.DISTRIBUTOR()),
            timelock: _intermediate.timelock,
            strategy: strategyProxy
        });

        emit PoolCreated(
            deployment.vault,
            deployment.pool,
            deployment.poolType,
            deployment.withdrawalQueue,
            _strategyFactory,
            _strategyDeployBytes,
            deployment.strategy
        );
    }

    function derivePoolType(AuxiliaryPoolConfig memory _auxiliaryConfig, address _strategyFactory)
        public
        view
        returns (bytes32 poolType)
    {
        poolType = STV_POOL_TYPE;
        if (_strategyFactory != address(0)) {
            poolType = STRATEGY_POOL_TYPE;
            if (!_auxiliaryConfig.allowListEnabled) {
                revert InvalidConfiguration("allowListEnabled must be true if strategy factory is set");
            }
            if (!_auxiliaryConfig.mintingEnabled) {
                revert InvalidConfiguration("mintingEnabled must be true if strategy factory is set");
            }
        } else if (_auxiliaryConfig.mintingEnabled) {
            poolType = STV_STETH_POOL_TYPE;
        }
    }

    /**
     * @notice Computes a unique hash for tracking deployment state
     * @param _sender Address that initiated the deployment
     * @param _vaultConfig Configuration for the vault
     * @param _commonPoolConfig Common pool parameters
     * @param _auxiliaryConfig Additional pool configuration
     * @param _timelockConfig Configuration for the timelock controller
     * @param _strategyFactory Address of strategy factory
     * @param _strategyDeployBytes ABI-encoded parameters for strategy deployment
     * @param _intermediate The intermediate deployment state
     * @return result Keccak256 hash of all deployment configuration parameters
     */
    function _hashDeploymentConfiguration(
        address _sender,
        VaultConfig memory _vaultConfig,
        CommonPoolConfig memory _commonPoolConfig,
        AuxiliaryPoolConfig memory _auxiliaryConfig,
        TimelockConfig memory _timelockConfig,
        address _strategyFactory,
        bytes memory _strategyDeployBytes,
        PoolIntermediate memory _intermediate
    ) internal pure returns (bytes32 result) {
        result = keccak256(
            abi.encode(
                _sender,
                abi.encode(_vaultConfig),
                abi.encode(_commonPoolConfig),
                abi.encode(_auxiliaryConfig),
                abi.encode(_timelockConfig),
                _strategyFactory,
                _strategyDeployBytes,
                abi.encode(_intermediate)
            )
        );
    }
}
