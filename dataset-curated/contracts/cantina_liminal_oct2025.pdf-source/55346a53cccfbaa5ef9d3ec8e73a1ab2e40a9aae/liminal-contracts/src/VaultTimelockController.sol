// SPDX-License-Identifier: BUSL-1.1
// Terms: https://liminal.money/xtokens/license

pragma solidity 0.8.28;

import {TimelockControllerUpgradeable} from
    "@openzeppelin/contracts-upgradeable/governance/TimelockControllerUpgradeable.sol";

/**
 * @title VaultTimelockController
 * @notice Enhanced timelock controller with per-function delay configuration
 * @dev Extends OpenZeppelin's TimelockControllerUpgradeable with intelligent delay detection
 */
contract VaultTimelockController is TimelockControllerUpgradeable {
    // ERC-7201: Namespaced Storage Layout
    // keccak256(abi.encode(uint256(keccak256("liminal.vaultTimelock.v1")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant VAULT_TIMELOCK_STORAGE_POSITION =
        0x58dfca5daecbbb3808b7a2399a82d70b8b7f873e64331c276767d397a9844400;

    /**
     * @dev Storage struct for VaultTimelockController-specific data
     * @dev This struct is stored in a namespaced storage slot to prevent collisions
     */
    struct VaultTimelockStorage {
        /// @notice Mapping of function selectors to their required delays
        mapping(bytes4 => uint256) functionDelays;
        /// @notice Mapping to track which functions have explicit delay configuration
        mapping(bytes4 => bool) hasExplicitDelay;
        /// @notice Default delay for functions without specific configuration
        uint256 defaultFunctionDelay;
    }

    /**
     * @dev Returns the storage struct at the namespaced storage position
     * @return $ The VaultTimelockStorage struct
     */
    function _getVaultTimelockStorage() private pure returns (VaultTimelockStorage storage $) {
        assembly {
            $.slot := VAULT_TIMELOCK_STORAGE_POSITION
        }
    }
    /// @notice Time delay constants

    uint256 public constant MIN_FUNCTION_DELAY = 1 hours;
    uint256 public constant RECOVERY_DELAY = 12 hours;
    uint256 public constant MIN_DEFAULT_DELAY = 12 hours;
    uint256 public constant PARAMETER_DELAY = 24 hours;
    uint256 public constant ORACLE_DELAY = 36 hours;
    uint256 public constant CONFIG_DELAY = 48 hours;
    uint256 public constant ROLE_DELAY = 72 hours;
    uint256 public constant MAX_DELAY = 7 days;

    /// @notice Events
    event FunctionDelaySet(bytes4 indexed selector, uint256 delay);
    event DefaultDelayUpdated(uint256 newDelay);
    event OperationScheduledWithAutoDelay(
        bytes32 indexed id, address indexed target, bytes4 indexed selector, uint256 delay
    );
    event OperationExecuted(bytes32 indexed id, address indexed target, bytes4 indexed selector);
    event OperationBatchExecuted(bytes32 indexed id, uint256 operationCount);

    /**
     * @notice Get the delay for a specific function selector
     * @param selector Function selector
     * @return delay The delay in seconds
     */
    function functionDelays(bytes4 selector) public view returns (uint256 delay) {
        VaultTimelockStorage storage $ = _getVaultTimelockStorage();
        return $.functionDelays[selector];
    }

    /**
     * @notice Check if a function selector has explicit delay configuration
     * @param selector Function selector
     * @return hasExplicit True if the function has explicit delay configuration
     */
    function hasExplicitDelay(bytes4 selector) public view returns (bool hasExplicit) {
        VaultTimelockStorage storage $ = _getVaultTimelockStorage();
        return $.hasExplicitDelay[selector];
    }

    /**
     * @notice Get the default delay for unconfigured functions
     * @return delay The default delay in seconds
     */
    function defaultFunctionDelay() public view returns (uint256 delay) {
        VaultTimelockStorage storage $ = _getVaultTimelockStorage();
        return $.defaultFunctionDelay;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the enhanced timelock controller
     * @param minDelay Minimum delay for operations
     * @param proposers Array of proposer addresses
     * @param executors Array of executor addresses
     * @param admin Optional admin address
     */
    function initialize(uint256 minDelay, address[] memory proposers, address[] memory executors, address admin)
        public
        override
        initializer
    {
        __TimelockController_init(minDelay, proposers, executors, admin);

        // Set default delay for unconfigured functions
        VaultTimelockStorage storage $ = _getVaultTimelockStorage();
        $.defaultFunctionDelay = CONFIG_DELAY;

        // Configure critical function selectors with their specific delays
        _configureCriticalFunctions();
    }

    /**
     * @notice Configure function selectors with their specific delays
     */
    function _configureCriticalFunctions() internal {
        // Role management functions - Most critical
        _setFunctionDelay(bytes4(keccak256("addMinter(address)")), ROLE_DELAY);
        _setFunctionDelay(bytes4(keccak256("addBurner(address)")), ROLE_DELAY);
        _setFunctionDelay(bytes4(keccak256("removeMinter(address)")), ROLE_DELAY);
        _setFunctionDelay(bytes4(keccak256("removeBurner(address)")), ROLE_DELAY);
        _setFunctionDelay(bytes4(keccak256("grantRole(bytes32,address)")), ROLE_DELAY);
        _setFunctionDelay(bytes4(keccak256("revokeRole(bytes32,address)")), ROLE_DELAY);
        _setFunctionDelay(bytes4(keccak256("addFeeCollector(address)")), ROLE_DELAY);
        _setFunctionDelay(bytes4(keccak256("removeFeeCollector(address)")), ROLE_DELAY);

        // Critical config updates
        _setFunctionDelay(bytes4(keccak256("setFees((uint256,uint256))")), CONFIG_DELAY); // since it's a struct we must consider this as a tuple
        _setFunctionDelay(bytes4(keccak256("setFees(uint256,uint256)")), CONFIG_DELAY);
        _setFunctionDelay(bytes4(keccak256("setLiquidityProvider(address)")), CONFIG_DELAY);
        _setFunctionDelay(bytes4(keccak256("setPythContract(address)")), CONFIG_DELAY);
        _setFunctionDelay(bytes4(keccak256("setUnderlyingAsset(address)")), CONFIG_DELAY);
        _setFunctionDelay(bytes4(keccak256("registerDepositPipe(address,address,address)")), CONFIG_DELAY);
        _setFunctionDelay(bytes4(keccak256("removeDepositPipe(address)")), CONFIG_DELAY);
        _setFunctionDelay(bytes4(keccak256("setRedemptionPipe(address)")), CONFIG_DELAY);
        _setFunctionDelay(bytes4(keccak256("setMaxDeposit(uint256)")), CONFIG_DELAY);
        _setFunctionDelay(bytes4(keccak256("setMaxSupply(uint256)")), CONFIG_DELAY);
        _setFunctionDelay(bytes4(keccak256("setMaxWithdraw(uint256)")), CONFIG_DELAY);
        _setFunctionDelay(bytes4(keccak256("setMaxPercentageIncrease(uint256)")), CONFIG_DELAY);

        // Oracle price feed configuration
        _setFunctionDelay(bytes4(keccak256("setMaxPriceAge(uint256)")), ORACLE_DELAY);
        _setFunctionDelay(bytes4(keccak256("setPriceId(address,bytes32,uint8)")), ORACLE_DELAY);
        _setFunctionDelay(bytes4(keccak256("setPriceIds(address[],bytes32[],uint8[])")), ORACLE_DELAY);

        // OVaultComposerMulti functions
        _setFunctionDelay(bytes4(keccak256("setOVaultComposerMulti(address,address)")), CONFIG_DELAY);
        _setFunctionDelay(bytes4(keccak256("setOFTApproval(address,bool)")), CONFIG_DELAY);
        _setFunctionDelay(bytes4(keccak256("setRemotePeer(address,uint32,bytes32)")), CONFIG_DELAY);
        _setFunctionDelay(bytes4(keccak256("setRemotePeer(address,uint32,address)")), CONFIG_DELAY);
        _setFunctionDelay(bytes4(keccak256("setTimelockController(address)")), MAX_DELAY);

        // Deposit forwarder
        _setFunctionDelay(bytes4(keccak256("addDepositPipe(address)")), CONFIG_DELAY);

        // Proxy upgrade functions
        // ProxyAdmin (TransparentUpgradeable)
        _setFunctionDelay(bytes4(keccak256("upgradeAndCall(address,address,bytes)")), CONFIG_DELAY);
        // UUPS
        _setFunctionDelay(bytes4(keccak256("upgradeToAndCall(address,bytes)")), CONFIG_DELAY);

        // Parameter changes
        _setFunctionDelay(bytes4(keccak256("setStrategist(address)")), PARAMETER_DELAY);
        _setFunctionDelay(bytes4(keccak256("setFeeReceiver(address)")), PARAMETER_DELAY);
        _setFunctionDelay(bytes4(keccak256("setDepositFee(uint256)")), PARAMETER_DELAY);
        _setFunctionDelay(bytes4(keccak256("setRecoveryDelay(uint256)")), PARAMETER_DELAY);
        _setFunctionDelay(bytes4(keccak256("setTreasury(address)")), PARAMETER_DELAY);

        // Token recovery
        _setFunctionDelay(bytes4(keccak256("recoverToken(address,address,uint256)")), RECOVERY_DELAY);

        // Timelock configuration functions - self-referential protection
        _setFunctionDelay(bytes4(keccak256("setFunctionDelay(bytes4,uint256)")), CONFIG_DELAY);
        _setFunctionDelay(bytes4(keccak256("setDefaultFunctionDelay(uint256)")), CONFIG_DELAY);
    }
    /**
     * @notice Get suggested delay for a function
     * @param data Function call data
     * @return Suggested delay in seconds
     */
    function _getDelay(bytes calldata data) internal view returns (uint256) {
        VaultTimelockStorage storage $ = _getVaultTimelockStorage();

        if (data.length < 4) return $.defaultFunctionDelay;

        bytes4 selector = bytes4(data[:4]);
        uint256 functionDelay = $.functionDelays[selector];

        // Return specific delay if explicitly configured, otherwise default delay
        return $.hasExplicitDelay[selector] ? functionDelay : $.defaultFunctionDelay;
    }

    /**
     * @notice Get suggested delay for a function (external version)
     * @param data Function call data
     * @return Suggested delay in seconds
     */
    function getDelay(bytes calldata data) external view returns (uint256) {
        return _getDelay(data);
    }

    /**
     * @notice Schedule operation with automatic delay detection
     * @param target Target contract
     * @param value ETH value
     * @param data Function call data
     * @param predecessor Predecessor operation ID
     * @param salt Random salt for uniqueness
     * @return Operation ID
     */
    function schedule(address target, uint256 value, bytes calldata data, bytes32 predecessor, bytes32 salt)
        external
        returns (bytes32)
    {
        require(hasRole(PROPOSER_ROLE, msg.sender), "VaultTimelock: not proposer");

        uint256 delay = _getDelay(data);

        // Calculate operation ID and schedule
        bytes32 id = hashOperation(target, value, data, predecessor, salt);
        super.schedule(target, value, data, predecessor, salt, delay);

        bytes4 selector = data.length >= 4 ? bytes4(data[:4]) : bytes4(0);
        emit OperationScheduledWithAutoDelay(id, target, selector, delay);

        return id;
    }

    /**
     * @notice Schedule multiple operations with automatic delay detection
     * @param targets Array of target contracts
     * @param values Array of ETH values
     * @param payloads Array of function call data
     * @param predecessor Predecessor operation ID
     * @param salt Random salt for uniqueness
     * @return Operation ID for the batch
     */
    function scheduleBatch(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata payloads,
        bytes32 predecessor,
        bytes32 salt
    ) external returns (bytes32) {
        require(hasRole(PROPOSER_ROLE, msg.sender), "VaultTimelock: not proposer");
        uint256 length = targets.length;
        require(length == values.length, "VaultTimelock: length mismatch");
        require(length == payloads.length, "VaultTimelock: length mismatch");
        require(length > 0, "VaultTimelock: empty batch");

        // Calculate the maximum delay required for all operations
        uint256 maxDelay = 0;
        for (uint256 i = 0; i < length; i++) {
            uint256 operationDelay = _getDelay(payloads[i]);
            if (operationDelay > maxDelay) {
                maxDelay = operationDelay;
            }
        }

        // Schedule the batch with the maximum delay
        bytes32 id = hashOperationBatch(targets, values, payloads, predecessor, salt);
        super.scheduleBatch(targets, values, payloads, predecessor, salt, maxDelay);

        // Emit events for each operation in the batch
        for (uint256 i = 0; i < length; i++) {
            bytes4 selector = payloads[i].length >= 4 ? bytes4(payloads[i][:4]) : bytes4(0);
            emit OperationScheduledWithAutoDelay(id, targets[i], selector, maxDelay);
        }

        return id;
    }

    /**
     * @notice Execute operation with automatic delay verification
     * @param target Target contract
     * @param value ETH value
     * @param data Function call data
     * @param predecessor Predecessor operation ID
     * @param salt Random salt for uniqueness
     */
    function execute(address target, uint256 value, bytes calldata data, bytes32 predecessor, bytes32 salt)
        public
        payable
        override
    {
        require(hasRole(EXECUTOR_ROLE, msg.sender), "VaultTimelock: not executor");

        bytes32 id = hashOperation(target, value, data, predecessor, salt);
        require(isOperationReady(id), "VaultTimelock: operation not ready");

        super.execute(target, value, data, predecessor, salt);

        bytes4 selector = data.length >= 4 ? bytes4(data[:4]) : bytes4(0);
        emit OperationExecuted(id, target, selector);
    }

    /**
     * @notice Execute multiple operations with automatic delay verification
     * @param targets Array of target contracts
     * @param values Array of ETH values
     * @param payloads Array of function call data
     * @param predecessor Predecessor operation ID
     * @param salt Random salt for uniqueness
     */
    function executeBatch(
        address[] calldata targets,
        uint256[] calldata values,
        bytes[] calldata payloads,
        bytes32 predecessor,
        bytes32 salt
    ) public payable override {
        require(hasRole(EXECUTOR_ROLE, msg.sender), "VaultTimelock: not executor");
        uint256 length = targets.length;
        require(length == values.length, "VaultTimelock: length mismatch");
        require(length == payloads.length, "VaultTimelock: length mismatch");
        require(length > 0, "VaultTimelock: empty batch");

        bytes32 id = hashOperationBatch(targets, values, payloads, predecessor, salt);
        require(isOperationReady(id), "VaultTimelock: operation not ready");

        super.executeBatch(targets, values, payloads, predecessor, salt);

        emit OperationBatchExecuted(id, length);
    }

    /**
     * @notice Set delay for a specific function
     * @dev Must be called through the timelock itself (via schedule/execute) to enforce the configured delay
     * @param selector Function selector
     * @param delay Delay in seconds
     */
    function setFunctionDelay(bytes4 selector, uint256 delay) external {
        require(msg.sender == address(this), "VaultTimelock: must call through timelock");
        require(delay >= MIN_FUNCTION_DELAY, "VaultTimelock: delay too short");
        require(delay <= MAX_DELAY, "VaultTimelock: delay too long");

        _updateFunctionDelay(selector, delay);
        emit FunctionDelaySet(selector, delay);
    }

    /**
     * @notice Update default delay for unconfigured functions
     * @dev Must be called through the timelock itself (via schedule/execute) to enforce the configured delay
     * @param newDefaultDelay New default delay in seconds
     */
    function setDefaultFunctionDelay(uint256 newDefaultDelay) external {
        require(msg.sender == address(this), "VaultTimelock: must call through timelock");
        require(newDefaultDelay >= MIN_DEFAULT_DELAY, "VaultTimelock: default delay too short");
        require(newDefaultDelay <= MAX_DELAY, "VaultTimelock: default delay too long");

        VaultTimelockStorage storage $ = _getVaultTimelockStorage();
        require(newDefaultDelay != $.defaultFunctionDelay, "VaultTimelock: same default delay");

        $.defaultFunctionDelay = newDefaultDelay;
        emit DefaultDelayUpdated(newDefaultDelay);
    }

    /**
     * @notice Internal helper to set function delay and mark as explicit
     * @dev Reverts if a delay is already explicitly set for the selector to prevent collisions
     * @param selector Function selector
     * @param delay Delay in seconds
     */
    function _setFunctionDelay(bytes4 selector, uint256 delay) internal {
        VaultTimelockStorage storage $ = _getVaultTimelockStorage();
        require(!$.hasExplicitDelay[selector], "VaultTimelock: Selector collision detected");
        $.functionDelays[selector] = delay;
        $.hasExplicitDelay[selector] = true;
    }

    /**
     * @notice Internal helper to update function delay (allows overwriting existing delay)
     * @param selector Function selector
     * @param delay Delay in seconds
     */
    function _updateFunctionDelay(bytes4 selector, uint256 delay) internal {
        VaultTimelockStorage storage $ = _getVaultTimelockStorage();
        $.functionDelays[selector] = delay;
        $.hasExplicitDelay[selector] = true;
    }
}
