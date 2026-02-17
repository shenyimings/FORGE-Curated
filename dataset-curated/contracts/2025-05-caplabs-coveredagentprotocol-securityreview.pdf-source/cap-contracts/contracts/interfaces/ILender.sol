// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

/// @title ILender
/// @author kexley, @capLabs
/// @notice Interface for the Lender contract
interface ILender {
    /// @dev Storage struct for the Lender contract
    /// @param delegation Address of the delegation contract that manages agent permissions
    /// @param oracle Address of the oracle contract used for price feeds
    /// @param reservesData Mapping of asset address to reserve data
    /// @param reservesList Mapping of reserve ID to asset address
    /// @param reservesCount Total number of reserves
    /// @param agentConfig Mapping of agent address to configuration
    /// @param liquidationStart Mapping of agent address to liquidation start time
    /// @param targetHealth Target health ratio for liquidations (scaled by 1e27)
    /// @param grace Grace period in seconds before an agent becomes liquidatable
    /// @param expiry Period in seconds after which liquidation rights expire
    /// @param bonusCap Maximum bonus percentage for liquidators (scaled by 1e27)
    /// @param emergencyLiquidationThreshold Health threshold below which grace periods are ignored
    struct LenderStorage {
        // Addresses
        address delegation;
        address oracle;
        // Reserve configuration
        mapping(address => ReserveData) reservesData;
        mapping(uint256 => address) reservesList;
        uint16 reservesCount;
        // Agent configuration
        mapping(address => AgentConfigurationMap) agentConfig;
        mapping(address => uint256) liquidationStart;
        // Liquidation parameters
        uint256 targetHealth;
        uint256 grace;
        uint256 expiry;
        uint256 bonusCap;
        uint256 emergencyLiquidationThreshold;
    }

    /// @dev Reserve data
    /// @param id Id of the reserve
    /// @param vault Address of the vault
    /// @param principalDebtToken Address of the principal debt token
    /// @param restakerDebtToken Address of the restaker debt token
    /// @param interestDebtToken Address of the interest debt token
    /// @param interestReceiver Address of the interest receiver
    struct ReserveData {
        uint256 id;
        address vault;
        address principalDebtToken;
        address restakerDebtToken;
        address interestDebtToken;
        address interestReceiver;
        address restakerInterestReceiver;
        uint8 decimals;
        bool paused;
        uint256 realizedInterest;
    }

    /// @dev Agent configuration map
    /// @param data Data of the agent configuration
    struct AgentConfigurationMap {
        uint256 data;
    }

    /// @dev Borrow parameters
    /// @param agent Address of the agent
    /// @param asset Asset to borrow
    /// @param amount Amount to borrow
    /// @param receiver Receiver of the borrowed asset
    struct BorrowParams {
        address agent;
        address asset;
        uint256 amount;
        address receiver;
    }

    /// @dev Repay parameters
    /// @param agent Address of the agent
    /// @param asset Asset to repay
    /// @param amount Amount to repay
    /// @param caller Caller of the repay function
    struct RepayParams {
        address agent;
        address asset;
        uint256 amount;
        address caller;
    }

    /// @dev Realize interest parameters
    /// @param asset Asset to realize interest for
    /// @param amount Amount of interest to realize
    struct RealizeInterestParams {
        address asset;
        uint256 amount;
    }

    /// @dev Add asset parameters
    /// @param asset Asset to add
    /// @param vault Address of the vault
    /// @param principalDebtToken Address of the principal debt token
    /// @param restakerDebtToken Address of the restaker debt token
    /// @param interestDebtToken Address of the interest debt token
    /// @param interestReceiver Address of the interest receiver
    struct AddAssetParams {
        address asset;
        address vault;
        address principalDebtToken;
        address restakerDebtToken;
        address interestDebtToken;
        address interestReceiver;
        address restakerInterestReceiver;
        uint256 bonusCap;
    }

    /// @notice Initialize the lender
    /// @param _accessControl Access control address
    /// @param _delegation Delegation address
    /// @param _oracle Oracle address
    /// @param _targetHealth Target health after liquidations
    /// @param _grace Grace period before an agent becomes liquidatable
    /// @param _expiry Expiry period after which an agent cannot be liquidated until called again
    /// @param _bonusCap Bonus cap for liquidations
    /// @param _emergencyLiquidationThreshold Liquidation threshold below which grace periods are voided
    function initialize(
        address _accessControl,
        address _delegation,
        address _oracle,
        uint256 _targetHealth,
        uint256 _grace,
        uint256 _expiry,
        uint256 _bonusCap,
        uint256 _emergencyLiquidationThreshold
    ) external;

    /// @notice Borrow an asset
    /// @param _asset Asset to borrow
    /// @param _amount Amount to borrow
    /// @param _receiver Receiver of the borrowed asset
    function borrow(address _asset, uint256 _amount, address _receiver) external;

    /// @notice Repay an asset
    /// @param _asset Asset to repay
    /// @param _amount Amount to repay
    /// @param _agent Repay on behalf of another borrower
    /// @return repaid Actual amount repaid
    function repay(address _asset, uint256 _amount, address _agent) external returns (uint256 repaid);

    /// @notice Realize interest for an asset
    /// @param _asset Asset to realize interest for
    /// @param _amount Amount of interest to realize (type(uint).max for all available interest)
    /// @return actualRealized Actual amount realized
    function realizeInterest(address _asset, uint256 _amount) external returns (uint256 actualRealized);

    /// @notice Initiate liquidation of an agent when the health is below 1
    /// @param _agent Agent address
    function initiateLiquidation(address _agent) external;

    /// @notice Cancel liquidation of an agent when the health is above 1
    /// @param _agent Agent address
    function cancelLiquidation(address _agent) external;

    /// @notice Liquidate an agent when the health is below 1
    /// @param _agent Agent address
    /// @param _asset Asset to repay
    /// @param _amount Amount of asset to repay on behalf of the agent
    /// @param liquidatedValue Value of the liquidation returned to the liquidator
    function liquidate(address _agent, address _asset, uint256 _amount) external returns (uint256 liquidatedValue);

    /// @notice Calculate the agent data
    /// @param _agent Address of agent
    /// @return totalDelegation Total delegation of an agent in USD, encoded with 8 decimals
    /// @return totalDebt Total debt of an agent in USD, encoded with 8 decimals
    /// @return ltv Loan to value ratio, encoded in ray (1e27)
    /// @return liquidationThreshold Liquidation ratio of an agent, encoded in ray (1e27)
    /// @return health Health status of an agent, encoded in ray (1e27)
    function agent(address _agent)
        external
        view
        returns (uint256 totalDelegation, uint256 totalDebt, uint256 ltv, uint256 liquidationThreshold, uint256 health);

    /// @notice Calculate the maximum amount that can be borrowed for a given asset
    /// @param _agent Agent address
    /// @param _asset Asset to borrow
    /// @return maxBorrowableAmount Maximum amount that can be borrowed in asset decimals
    function maxBorrowable(address _agent, address _asset) external view returns (uint256 maxBorrowableAmount);

    /// @notice Get the current debt balances for an agent for a specific asset
    /// @param _agent Agent address to check debt for
    /// @param _asset Asset to check debt for
    /// @return principalDebt Principal debt amount in asset decimals
    /// @return interestDebt Interest debt amount in asset decimals
    /// @return restakerDebt Restaker debt amount in asset decimals
    function debt(address _agent, address _asset)
        external
        view
        returns (uint256 principalDebt, uint256 interestDebt, uint256 restakerDebt);

    /// @notice Add an asset to the Lender
    /// @param _params Parameters to add an asset
    function addAsset(AddAssetParams calldata _params) external;

    /// @notice Remove asset from lending when there is no borrows
    /// @param _asset Asset address
    function removeAsset(address _asset) external;

    /// @notice Pause an asset from being borrowed
    /// @param _asset Asset address
    /// @param _pause True if pausing or false if unpausing
    function pauseAsset(address _asset, bool _pause) external;

    /// @notice Get the target health ratio
    function targetHealth() external view returns (uint256 targetHealth);

    /// @notice Get the grace period
    function grace() external view returns (uint256 grace);

    /// @notice Get the expiry period
    function expiry() external view returns (uint256 expiry);

    /// @notice Get the bonus cap
    function bonusCap() external view returns (uint256 bonusCap);

    /// @notice Get the emergency liquidation threshold
    function emergencyLiquidationThreshold() external view returns (uint256 emergencyLiquidationThreshold);

    /// @notice The liquidation start time for an agent
    /// @param _agent Address of the agent
    /// @return startTime Timestamp when liquidation was initiated
    function liquidationStart(address _agent) external view returns (uint256 startTime);

    /// @notice The reserve data for an asset
    /// @param _asset Address of the asset
    /// @return id Id of the reserve
    /// @return vault Address of the vault
    /// @return principalDebtToken Address of the principal debt token
    /// @return restakerDebtToken Address of the restaker debt token
    /// @return interestDebtToken Address of the interest debt token
    /// @return interestReceiver Address of the interest receiver
    /// @return decimals Decimals of the asset
    /// @return paused True if the asset is paused, false otherwise
    /// @return realizedInterest Realized interest of the asset
    function reservesData(address _asset)
        external
        view
        returns (
            uint256 id,
            address vault,
            address principalDebtToken,
            address restakerDebtToken,
            address interestDebtToken,
            address interestReceiver,
            uint8 decimals,
            bool paused,
            uint256 realizedInterest
        );

    /// @notice Zero address not valid
    error ZeroAddressNotValid();
}
