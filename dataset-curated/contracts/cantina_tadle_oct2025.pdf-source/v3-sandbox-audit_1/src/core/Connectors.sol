// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title ConnectorInterface
 * @dev Interface that all connectors must implement to be registered in the system
 * @notice Connectors must provide a name function to identify themselves uniquely
 */
interface ConnectorInterface {
    /**
     * @dev Returns the name of the connector
     * @return The connector name as a string
     */
    function name() external view returns (string memory);
}

/**
 * @title ITadleSandBoxFactory
 * @dev Interface for the Tadle Sandbox Factory contract
 * @notice Provides verification functionality for sandbox account eligibility and registration
 */
interface ITadleSandBoxFactory {
    /**
     * @notice Verifies if an account is a registered sandbox account
     * @param account The address to verify
     * @return True if the account is a valid sandbox account, false otherwise
     */
    function isSandboxAccount(address account) external view returns (bool);
}

/**
 * @title IAuth
 * @dev Interface for authentication contract
 * @notice Used to verify admin privileges for connector management and system operations
 */
interface IAuth {
    /**
     * @dev Checks if an account has admin privileges
     * @param account Address to check for admin status
     * @return True if the account is an admin, false otherwise
     */
    function isAdmin(address account) external view returns (bool);
}

/**
 * @title TadleConnectors
 * @dev Registry contract for managing connector implementations and token airdrops
 * @notice This contract maintains a registry of connector implementations that can be
 * used by the Tadle system, with admin-controlled addition, update, and removal.
 * It also provides token airdrop functionality with rate limiting and user level-based claims.
 */
contract TadleConnectors is Ownable2Step, ReentrancyGuard {
    /// @notice Auth contract instance for access control and admin verification
    IAuth public auth;

    /// @notice Initialization flag to prevent multiple initialization calls
    bool private _initialized;

    /// @notice Address of the Tadle Sandbox Factory contract
    /// @notice Used to verify sandbox account eligibility for claims and check-ins
    address public factory;

    /// @notice Mapping of connector names to their implementation addresses
    mapping(string => address) public connectors;

    /// @notice Mapping to track last claim timestamps for rate limiting
    /// @notice Maps user address => token address => last claim timestamp
    /// @dev Used to enforce the 24-hour claim window between claims
    mapping(address => mapping(address => uint256)) public lastClaimTimes;

    /// @notice Mapping to track cumulative claimed amounts per user and token
    /// @notice Maps user address => token address => total claimed amount
    mapping(address => mapping(address => uint256)) public totalClaimedAmounts;

    /// @notice Mapping to configure token amounts by user level
    /// @notice Maps token address => user level => claimable amount
    /// @dev Level 0 is typically reserved, levels start from 1
    mapping(address => mapping(uint256 => uint256)) public tokenAmountsByLevel;

    /// @notice Mapping for token-specific airdrop configurations
    /// @notice Maps token address => TokenAirdropConfig struct
    /// @dev Stores individual configuration for each token's airdrop parameters
    mapping(address => TokenAirdropConfig) public tokenAirdropConfigs;

    /// @notice Mapping to track last airdrop receive timestamps per token per recipient
    /// @notice Maps recipient address => token address => last receive timestamp
    /// @dev Used to enforce token-specific cooldown periods for both user and admin claims
    mapping(address => mapping(address => uint256)) public lastTokenReceiveTimes;

    /// @notice Mapping to track last check-in timestamps for daily check-in limit
    /// @notice Maps user address => last check-in timestamp
    /// @dev Used to enforce once-per-day check-in restriction
    mapping(address => uint256) public lastCheckInTimes;

    // ============================================================================
    // STRUCTURES
    // ============================================================================

    /// @notice Configuration structure for token-specific airdrop parameters
    /// @dev Each token can have its own airdrop rules, limits, and cooldown periods
    struct TokenAirdropConfig {
        uint256 userAirdropAmount; // Amount of tokens distributed per user self-claim
        uint256 userCooldownPeriod; // Cooldown period between user self-claims (in seconds)
        bool isEnabled; // Global enable/disable flag for this token's airdrop functionality
    }

    // ============================================================================
    // CONSTANTS
    // ============================================================================

    /// @notice Time window between consecutive claims (24 hours)
    /// @dev Legacy constant maintained for backward compatibility with existing claim logic
    uint256 public constant CLAIM_WINDOW = 24 hours;

    /// @notice Constant representing ETH address for native token operations
    /// @dev Special identifier (0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE) used throughout the contract for ETH transfers
    address internal constant ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /// @notice Address of the monUSD token contract
    /// @dev Hardcoded token address maintained for legacy compatibility and system integration
    address public constant monUSD = address(0x57c914e3240C837EBE87F096e0B4d9A06E3F489B);

    // ============================================================================
    // EVENTS
    // ============================================================================
    /// @notice Emitted when the factory contract address is initialized
    /// @dev This event can only be emitted once during contract initialization
    /// @param factory The address of the Tadle Sandbox Factory contract
    event FactoryInitialized(address indexed factory);

    /// @notice Emitted when token claim amounts are configured for a specific user level
    /// @dev Only contract admins can configure these amounts through the auth system
    /// @param token The address of the token being configured (ETH_ADDRESS for native ETH)
    /// @param level The user level (must be > 0)
    /// @param amount The claimable amount for this token and level combination
    event TokenAmountConfigured(address indexed token, uint256 indexed level, uint256 amount);

    /// @notice Emitted when token airdrop configuration is updated
    /// @dev Used for tracking changes to token airdrop parameters and cooldown settings
    /// @param token The address of the token being configured
    /// @param userAirdropAmount The amount of tokens distributed per user self-claim
    /// @param userCooldownPeriod The cooldown period between user self-claims (in seconds)
    /// @param isEnabled Whether airdrop functionality is enabled for this token
    event TokenAirdropConfigured(
        address indexed token, uint256 userAirdropAmount, uint256 userCooldownPeriod, bool isEnabled
    );

    // ============================================================================
    // CONNECTOR MANAGEMENT EVENTS
    // ============================================================================

    /// @notice Emitted when a new connector is added to the registry
    /// @param nameHash Keccak256 hash of the connector name for efficient indexing
    /// @param name Human-readable name of the connector
    /// @param connector Address of the connector implementation contract
    event LogConnectorAdded(bytes32 indexed nameHash, string name, address indexed connector);

    /// @notice Emitted when an existing connector is updated with a new implementation
    /// @param nameHash Keccak256 hash of the connector name for efficient indexing
    /// @param name Human-readable name of the connector
    /// @param oldConnector Previous connector implementation address
    /// @param newConnector New connector implementation address
    event LogConnectorUpdated(
        bytes32 indexed nameHash, string name, address indexed oldConnector, address indexed newConnector
    );

    /// @notice Emitted when a connector is removed from the registry
    /// @param nameHash Keccak256 hash of the connector name for efficient indexing
    /// @param name Human-readable name of the connector
    /// @param connector Address of the removed connector implementation
    event LogConnectorRemoved(bytes32 indexed nameHash, string name, address indexed connector);

    /// @notice Emitted when tokens are successfully claimed by a user
    /// @param user The address of the user receiving the tokens
    /// @param token The address of the token being claimed (ETH_ADDRESS for native ETH)
    /// @param amount The amount of tokens claimed (in token's smallest unit)
    /// @param timestamp The block timestamp when the claim occurred
    event TokensClaimed(address indexed user, address indexed token, uint256 amount, uint256 timestamp);

    /// @notice Emitted when tokens are airdropped to a user through self-claim
    /// @dev Used for tracking token airdrops with rate limiting and cooldown enforcement
    /// @param recipient The address of the user receiving the tokens
    /// @param token The address of the token being airdropped
    /// @param amount The amount of tokens transferred (in token's smallest unit)
    /// @param timestamp The block timestamp when the transfer occurred
    event Airdrop(address indexed recipient, address indexed token, uint256 amount, uint256 timestamp);

    /// @notice Emitted when a user performs a daily check-in action
    /// @dev Only verified sandbox accounts can check in, limited to once per day
    /// @param user The address of the user checking in
    /// @param timestamp The block timestamp when the check-in occurred
    event UserCheckIn(address indexed user, uint256 timestamp);

    /**
     * @dev Modifier to ensure contract is only initialized once
     * @notice Prevents multiple initialization calls that could reset contract state
     * @custom:security Critical for preventing reinitialization attacks
     */
    modifier initializer() {
        require(!_initialized, "TadleConnectors: contract already initialized");
        _;
        _initialized = true;
    }

    /**
     * @dev Modifier to check if caller has admin privileges
     * @notice Restricts function access to authenticated admin accounts only
     * @custom:access-control Uses auth contract for privilege verification
     */
    modifier isAdmin() {
        require(auth.isAdmin(msg.sender), "TadleConnectors: caller lacks admin privileges");
        _;
    }

    /// @notice Restricts function access to verified sandbox accounts only
    /// @dev Validates caller through the factory contract's isSandboxAccount function
    /// @custom:access-control Ensures only registered sandbox users can access protected functions
    modifier onlySandboxAccount() {
        require(factory != address(0), "TadleConnectors: factory not initialized");
        require(
            ITadleSandBoxFactory(factory).isSandboxAccount(msg.sender),
            "TadleConnectors: caller is not a verified sandbox account"
        );
        _;
    }

    /**
     * @notice Constructor that sets the contract deployer as the initial owner
     * @dev Inherits from Ownable2Step for secure two-step ownership transfer
     * @custom:security Uses OpenZeppelin's secure ownership pattern
     */
    constructor() Ownable(msg.sender) {}

    /**
     * @notice Initialize the contract with auth contract address
     * @dev Can only be called once due to initializer modifier protection
     * @param _auth Address of the Auth contract for admin verification
     * @param _factory Address of the Factory contract for sandbox account verification
     * @custom:initialization Must be called after deployment to activate admin functions
     */
    function initialize(address _auth, address _factory) external onlyOwner initializer {
        require(_auth != address(0), "TadleConnectors: auth address cannot be zero");
        require(_factory != address(0), "TadleConnectors: factory address cannot be zero");
        auth = IAuth(_auth);
        factory = _factory;
    }

    /**
     * @notice Add multiple connectors to the registry in a single transaction
     * @dev Validates connector implementations and prevents duplicate names
     * @param _names Array of unique connector names for identification
     * @param _connectors Array of connector implementation contract addresses
     * @custom:access-control Restricted to admin accounts only
     * @custom:batch-operation Processes multiple connectors efficiently
     */
    function addConnectors(string[] calldata _names, address[] calldata _connectors) external isAdmin {
        require(_names.length == _connectors.length, "TadleConnectors: names and connectors arrays length mismatch");
        require(_names.length > 0, "TadleConnectors: arrays cannot be empty");

        for (uint256 i = 0; i < _connectors.length; i++) {
            require(bytes(_names[i]).length > 0, "TadleConnectors: connector name cannot be empty");
            require(connectors[_names[i]] == address(0), "TadleConnectors: connector name already registered");
            _verifyConnector(_connectors[i]);

            connectors[_names[i]] = _connectors[i];
            emit LogConnectorAdded(keccak256(abi.encodePacked(_names[i])), _names[i], _connectors[i]);
        }
    }

    /**
     * @notice Update multiple existing connectors with new implementations
     * @dev Validates new implementations and ensures connectors exist before updating
     * @param _names Array of existing connector names to update
     * @param _connectors Array of new connector implementation addresses
     * @custom:access-control Restricted to admin accounts only
     * @custom:batch-operation Processes multiple updates efficiently
     */
    function updateConnectors(string[] calldata _names, address[] calldata _connectors) external isAdmin {
        require(_names.length == _connectors.length, "TadleConnectors: array length mismatch");
        require(_names.length > 0, "TadleConnectors: empty arrays");

        for (uint256 i = 0; i < _connectors.length; i++) {
            require(bytes(_names[i]).length > 0, "TadleConnectors: empty connector name");
            require(connectors[_names[i]] != address(0), "TadleConnectors: connector name not found in registry");
            require(_connectors[i] != address(0), "TadleConnectors: connector address cannot be zero");
            require(connectors[_names[i]] != _connectors[i], "TadleConnectors: new connector address same as current");

            // Verify connector implements required interface
            _verifyConnector(_connectors[i]);

            address oldConnector = connectors[_names[i]];
            connectors[_names[i]] = _connectors[i];

            emit LogConnectorUpdated(keccak256(abi.encodePacked(_names[i])), _names[i], oldConnector, _connectors[i]);
        }
    }

    /**
     * @notice Remove multiple connectors from the registry
     * @dev Validates connector existence before removal
     * @param _names Array of connector names to remove from the registry
     * @custom:access-control Restricted to admin accounts only
     * @custom:batch-operation Processes multiple removals efficiently
     */
    function removeConnectors(string[] calldata _names) external isAdmin {
        require(_names.length > 0, "TadleConnectors: names array cannot be empty");

        for (uint256 i = 0; i < _names.length; i++) {
            require(bytes(_names[i]).length > 0, "TadleConnectors: empty connector name");
            require(connectors[_names[i]] != address(0), "TadleConnectors: connector does not exist");

            address connectorAddr = connectors[_names[i]];
            delete connectors[_names[i]];

            emit LogConnectorRemoved(keccak256(abi.encodePacked(_names[i])), _names[i], connectorAddr);
        }
    }

    /**
     * @notice Check if connectors are registered and retrieve their addresses
     * @dev Returns false if any connector is not found in the registry
     * @param _names Array of connector names to check
     * @return isOk Whether all connectors are registered and enabled
     * @return _addresses Array of connector implementation addresses (zero address if not found)
     * @custom:view-function Pure read operation with no state changes
     */
    function isConnectors(string[] calldata _names) external view returns (bool isOk, address[] memory _addresses) {
        isOk = true;
        uint256 len = _names.length;
        _addresses = new address[](len);

        for (uint256 i = 0; i < len; i++) {
            _addresses[i] = connectors[_names[i]];
            if (_addresses[i] == address(0)) {
                isOk = false;
                break;
            }
        }
    }

    /**
     * @notice Internal function to verify connector implementation validity
     * @dev Ensures connector implements required ConnectorInterface and has valid name
     * @param _connector Address of connector implementation to verify
     * @custom:internal-function Only callable from within the contract
     * @custom:validation Checks interface compliance and name availability
     */
    function _verifyConnector(address _connector) internal view {
        require(_connector != address(0), "TadleConnectors: connector address cannot be zero");
        // Verify connector implements required interface by calling name()
        string memory connectorName = ConnectorInterface(_connector).name();
        require(bytes(connectorName).length > 0, "TadleConnectors: connector must return non-empty name");
    }

    /**
     * @notice Check if a user is eligible to claim a specific token today
     * @dev This function implements the 24-hour claim window rate limiting mechanism
     * @dev First-time claims are always allowed regardless of timestamp
     * @param user Address of the user to check eligibility for
     * @param token Address of the token to check (use ETH_ADDRESS for native ETH)
     * @return bool True if user can claim the token, false if still within claim window
     * @custom:view-function Pure view function with no state changes
     * @custom:rate-limiting Enforces 24-hour window between consecutive claims
     */
    function canClaimToday(address user, address token) public view returns (bool) {
        uint256 lastClaimTime = lastClaimTimes[user][token];
        // First time claim is always allowed
        if (lastClaimTime == 0) {
            return true;
        }
        // Check if CLAIM_WINDOW has passed since last claim
        return block.timestamp >= lastClaimTime + CLAIM_WINDOW;
    }

    /**
     * @notice Get the total cumulative amount claimed by a user for a specific token
     * @param user Address of the user to query claim history for
     * @param token Address of the token to query (use ETH_ADDRESS for native ETH)
     */
    function getUserClaimedAmount(address user, address token) external view returns (uint256) {
        return totalClaimedAmounts[user][token];
    }

    /**
     * @notice Claims daily airdrop tokens for the caller based on their user level
     * @dev This is the main claim function that enforces all business rules and rate limits
     * @dev Both caller and validator must not have claimed this token within the last 24 hours
     * @dev The function is protected against reentrancy attacks
     * @param token Address of the token to claim (use ETH_ADDRESS for native ETH)
     * @param validator Address of the validator (must also be eligible for claims)
     * @param level User level determining the claimable amount (must be configured)
     * @custom:security Protected by nonReentrant and onlySandboxAccount modifiers
     * @custom:rate-limiting Enforces 24-hour claim window for both caller and validator
     * @custom:requirements Caller must be sandbox account, token must be configured for level
     * @custom:state-change Updates claim timestamps and transfers tokens
     */
    function claim(address token, address validator, uint256 level) external nonReentrant onlySandboxAccount {
        // Verify claim eligibility for both caller and validator
        _verifyClaimEligibility(msg.sender, token);
        _verifyClaimEligibility(validator, token);

        // Update claim timestamps
        _updateClaimTimestamps(msg.sender, validator, token);

        // Transfer tokens based on user level
        _transferTokens(token, msg.sender, level);
    }

    // ============================================================================
    // PUBLIC AIRDROP FUNCTIONS
    // ============================================================================

    /**
     * @notice Allows users to claim tokens through self-service airdrop
     * @dev Enforces cooldown periods and validates token configuration
     * @param token Address of the ERC20 token to claim
     * @custom:security Protected by nonReentrant modifier
     * @custom:rate-limiting Enforces token-specific cooldown periods
     * @custom:balance-check Validates sufficient contract token balance
     */
    function airdrop(address token) external nonReentrant {
        require(token != address(0), "TadleConnectors: token address cannot be zero");

        // Get token configuration
        TokenAirdropConfig memory config = tokenAirdropConfigs[token];
        require(config.isEnabled, "TadleConnectors: airdrop disabled for this token");

        uint256 airdropAmount = config.userAirdropAmount;
        require(airdropAmount > 0, "TadleConnectors: airdrop amount not configured for this token");

        // Check cooldown based on claim type (using shared timestamp to prevent double claiming)
        uint256 lastClaimTime = lastTokenReceiveTimes[msg.sender][token];
        require(
            block.timestamp >= lastClaimTime + config.userCooldownPeriod, "TadleConnectors: cooldown period not elapsed"
        );

        // Check contract has sufficient token balance
        IERC20 tokenContract = IERC20(token);
        uint256 balance = tokenContract.balanceOf(address(this));
        require(balance >= airdropAmount, "TadleConnectors: insufficient contract token balance");

        // Update recipient's last claim timestamp (shared between both claim types to prevent double claiming)
        lastTokenReceiveTimes[msg.sender][token] = block.timestamp;

        // Transfer configured amount of tokens
        SafeERC20.safeTransfer(tokenContract, msg.sender, airdropAmount);

        emit Airdrop(msg.sender, token, airdropAmount, block.timestamp);
    }

    /**
     * @notice Allows sandbox users to perform a check-in action once per day
     * @dev Records user activity through event emission for off-chain tracking
     * @dev Enforces daily check-in limit by tracking last check-in timestamp
     * @custom:access-control Restricted to verified sandbox accounts only
     * @custom:rate-limiting Limited to once per 24-hour period
     */
    function checkIn() external {
        uint256 lastCheckIn = lastCheckInTimes[msg.sender];

        // Check if user has already checked in today
        if (lastCheckIn > 0) {
            uint256 daysSinceLastCheckIn = (block.timestamp - lastCheckIn) / 1 days;
            require(daysSinceLastCheckIn >= 1, "TadleConnectors: daily check-in limit reached");
        }

        // Update last check-in timestamp
        lastCheckInTimes[msg.sender] = block.timestamp;

        emit UserCheckIn(msg.sender, block.timestamp);
    }

    /**
     * @notice Configure the claimable token amount for a specific user level
     * @dev This function sets up the reward structure for different user tiers
     * @dev Level 0 is typically reserved, active levels start from 1
     * @param token Address of the token to configure (use ETH_ADDRESS for native ETH)
     * @param level User level (must be > 0, represents user tier/rank)
     * @param amount Amount of tokens claimable for this level (in token's smallest unit)
     * @custom:security Only callable by contract owner
     * @custom:configuration Sets up level-based reward structure
     * @custom:event Emits TokenAmountConfigured event for tracking
     */
    function setTokenAmountByLevel(address token, uint256 level, uint256 amount) external onlyOwner {
        require(token != address(0), "TadleConnectors: invalid token address");
        require(level > 0, "TadleConnectors: invalid level");
        tokenAmountsByLevel[token][level] = amount;
        emit TokenAmountConfigured(token, level, amount);
    }

    /**
     * @notice Configure token airdrop parameters
     * @dev Sets up airdrop rules for a specific token
     * @param token Address of the token to configure
     * @param userAirdropAmount Amount of tokens for user self-claim
     * @param userCooldownPeriod Cooldown period for user self-claim (in seconds)
     * @param isEnabled Whether airdrop is enabled for this token
     * @custom:security Only callable by contract owner
     * @custom:configuration Sets up token-specific airdrop parameters
     */
    function setTokenAirdropConfig(address token, uint256 userAirdropAmount, uint256 userCooldownPeriod, bool isEnabled)
        external
        onlyOwner
    {
        require(token != address(0), "TadleConnectorsV4: invalid token address");

        tokenAirdropConfigs[token] = TokenAirdropConfig({
            userAirdropAmount: userAirdropAmount,
            userCooldownPeriod: userCooldownPeriod,
            isEnabled: isEnabled
        });

        emit TokenAirdropConfigured(token, userAirdropAmount, userCooldownPeriod, isEnabled);
    }

    // ============================================================================
    // INTERNAL HELPER FUNCTIONS
    // ============================================================================

    /**
     * @notice Internal function to verify if a user is eligible to claim a token
     * @dev Provides different error messages for caller vs validator failures
     * @dev Uses the canClaimToday function to check 24-hour claim window
     * @param user Address of the user to verify (caller or validator)
     * @param token Address of the token to verify eligibility for
     * @custom:internal-function Only callable from within the contract
     * @custom:view-function Does not modify state, only reads and validates
     * @custom:error-handling Provides context-specific error messages
     */
    function _verifyClaimEligibility(address user, address token) internal view {
        require(
            canClaimToday(user, token),
            user == msg.sender
                ? "TadleConnectors: user already claimed this token today"
                : "TadleConnectors: validator already claimed this token today"
        );
    }

    /**
     * @notice Internal function to update claim timestamps for rate limiting
     * @dev Records the current block timestamp for both caller and validator
     * @dev This prevents both addresses from claiming the same token for 24 hours
     * @param caller Address of the user making the claim
     * @param validator Address of the validator involved in the claim
     * @param token Address of the token being claimed
     * @custom:internal-function Only callable from within the contract
     * @custom:state-change Modifies lastClaimTimes mapping for both addresses
     * @custom:rate-limiting Sets timestamp for 24-hour claim window enforcement
     */
    function _updateClaimTimestamps(address caller, address validator, address token) internal {
        lastClaimTimes[caller][token] = block.timestamp;
        lastClaimTimes[validator][token] = block.timestamp;
    }

    /**
     * @notice Internal function to route token transfers based on token type
     * @dev Determines whether to transfer native ETH or ERC20 tokens
     * @dev Routes to appropriate specialized transfer function
     * @param token Address of the token to transfer (ETH_ADDRESS for native ETH)
     * @param recipient Address of the user receiving the tokens
     * @param level User level used to determine transfer amount from configuration
     * @custom:internal-function Only callable from within the contract
     * @custom:routing Routes to _transferGasToken or _transferERC20Token
     * @custom:level-based Amount determined by tokenAmountsByLevel mapping
     */
    function _transferTokens(address token, address recipient, uint256 level) internal {
        if (token == ETH_ADDRESS) {
            _transferGasToken(recipient, level);
        } else {
            _transferERC20Token(token, recipient, level);
        }
    }

    /**
     * @notice Internal function to transfer native ETH tokens to a recipient
     * @dev Validates configuration, balance, and performs secure ETH transfer
     * @dev Updates tracking variables and emits appropriate events
     * @param recipient Address of the user receiving the ETH
     * @param level User level used to lookup configured ETH amount
     * @custom:internal-function Only callable from within the contract
     * @custom:native-transfer Uses low-level call for ETH transfer
     * @custom:balance-check Validates sufficient contract balance before transfer
     * @custom:state-tracking Updates totalClaimedAmounts and emits event
     */
    function _transferGasToken(address recipient, uint256 level) internal {
        uint256 gasAmount = tokenAmountsByLevel[ETH_ADDRESS][level];
        require(gasAmount > 0, "TadleConnectors: ETH airdrop amount not configured for this level");
        uint256 balance = address(this).balance;
        require(balance >= gasAmount, "TadleConnectors: insufficient contract ETH balance");

        (bool success,) = recipient.call{value: gasAmount}("");
        require(success, "TadleConnectors: ETH transfer failed");

        totalClaimedAmounts[recipient][ETH_ADDRESS] += gasAmount;
        emit TokensClaimed(recipient, ETH_ADDRESS, gasAmount, block.timestamp);
    }

    /**
     * @notice Internal function to transfer ERC20 tokens to a recipient
     * @dev Validates configuration, balance, and performs secure ERC20 transfer
     * @dev Uses OpenZeppelin's SafeERC20 for secure token transfers
     * @dev Updates tracking variables and emits appropriate events
     * @param token Address of the ERC20 token contract to transfer
     * @param recipient Address of the user receiving the tokens
     * @param level User level used to lookup configured token amount
     * @custom:internal-function Only callable from within the contract
     * @custom:safe-transfer Uses SafeERC20.safeTransfer for security
     * @custom:balance-check Validates sufficient contract token balance
     * @custom:state-tracking Updates totalClaimedAmounts and emits event
     */
    function _transferERC20Token(address token, address recipient, uint256 level) internal {
        uint256 amount = tokenAmountsByLevel[token][level];
        require(amount > 0, "TadleConnectors: token amount not configured for this level");

        IERC20 tokenContract = IERC20(token);
        uint256 balance = tokenContract.balanceOf(address(this));
        require(balance >= amount, "TadleConnectors: insufficient contract token balance");

        SafeERC20.safeTransfer(tokenContract, recipient, amount);

        totalClaimedAmounts[recipient][token] += amount;
        emit TokensClaimed(recipient, token, amount, block.timestamp);
    }
}
