// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.25;

library VaultLib {
    struct Config {
        // Required fields
        address asset;
        uint8 decimals;
        address operator;
        string name;
        string symbol;
        bytes extraData;
    }
}

library WithdrawLib {
    struct QueuedWithdrawal {
        address staker;
        uint96 start;
        uint256 shares;
        address beneficiary;
    }
}

error MinWithdrawDelayNotPassed();

interface IKarakBaseVault {
    /* ========== MUTATIVE FUNCTIONS ========== */
    function initialize(
        address _owner,
        address _operator,
        address _depositToken,
        string memory _name,
        string memory _symbol,
        bytes memory _extraData
    ) external;

    function slashAssets(
        uint256 slashPercentageWad,
        address slashingHandler
    ) external returns (uint256 transferAmount);

    function pause(uint256 map) external;

    function unpause(uint256 map) external;
    /* ======================================== */

    /* ============ VIEW FUNCTIONS ============ */
    function totalAssets() external view returns (uint256);

    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function decimals() external view returns (uint8);

    function vaultConfig() external pure returns (VaultLib.Config memory);

    function asset() external view returns (address);

    function pausedMap() external view returns (uint256);
    /* ======================================== */
}

interface IVault is IKarakBaseVault {
    /* ========== MUTATIVE FUNCTIONS ========== */
    function deposit(
        uint256 assets,
        address to
    ) external returns (uint256 shares);
    function deposit(
        uint256 assets,
        address to,
        uint256 minSharesOut
    ) external returns (uint256 shares);
    function mint(uint256 shares, address to) external returns (uint256 assets);
    function startRedeem(
        uint256 shares,
        address withdrawer
    ) external returns (bytes32 withdrawalKey);
    function finishRedeem(bytes32 withdrawalKey) external;
    /* ======================================== */

    /* ============ VIEW FUNCTIONS ============ */
    function owner() external view returns (address);
    function getNextWithdrawNonce(
        address staker
    ) external view returns (uint256);
    function isWithdrawalPending(
        address staker,
        uint256 _withdrawNonce
    ) external view returns (bool);
    function getQueuedWithdrawal(
        address staker,
        uint256 _withdrawNonce
    ) external view returns (WithdrawLib.QueuedWithdrawal memory);
    function extSloads(
        bytes32[] calldata slots
    ) external view returns (bytes32[] memory res);
    /* ======================================== */
}

interface ICore {
    /* ========== MUTATIVE FUNCTIONS ========== */
    function initialize(
        address _vaultImpl,
        address _manager,
        address _vetoCommittee,
        uint32 _hookCallGasLimit,
        uint32 _supportsInterfaceGasLimit,
        uint32 _hookGasBuffer
    ) external;
    function deployVaults(
        VaultLib.Config[] calldata vaultConfigs,
        address implementation
    ) external returns (IKarakBaseVault[] memory vaults);
    function allowlistAssets(
        address[] calldata assets,
        address[] calldata slashingHandlers
    ) external;

    function MIN_WITHDRAWAL_DELAY() external view returns (uint96);
}

library Constants {
    address public constant DEFAULT_VAULT_IMPLEMENTATION_FLAG = address(1);

    // Bit from solady/src/auth/OwnableRoles.sol
    uint256 public constant MANAGER_ROLE = 1 << 0;
    uint256 public constant VETO_COMMITTEE_ROLE = 1 << 1;

    uint256 public constant SNAPSHOT_EXPIRY = 7 days;
    uint256 public constant SLASHING_WINDOW = 7 days;
    uint256 public constant SLASHING_VETO_WINDOW = 2 days;
    uint256 public constant MIN_STAKE_UPDATE_DELAY =
        SLASHING_WINDOW + SLASHING_VETO_WINDOW;
    uint256 public constant MIN_WITHDRAWAL_DELAY =
        SLASHING_WINDOW + SLASHING_VETO_WINDOW;

    uint256 public constant ONE_WAD = 1e18;

    uint256 public constant HUNDRED_PERCENT_WAD = 100e18;
    uint256 public constant MAX_SLASHING_PERCENT_WAD = HUNDRED_PERCENT_WAD;

    uint256 public constant MAX_VAULTS_PER_OPERATOR = 32;
    uint256 public constant MAX_SLASHABLE_VAULTS_PER_REQUEST =
        MAX_VAULTS_PER_OPERATOR;
    uint256 public constant MAX_DSS_PER_OPERATOR = 32;

    uint256 public constant SLASHING_COOLDOWN = 2 days;
}
