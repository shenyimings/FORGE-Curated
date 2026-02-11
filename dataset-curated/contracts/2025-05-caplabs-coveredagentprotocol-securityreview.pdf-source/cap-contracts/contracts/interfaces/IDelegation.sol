// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IRestakerRewardReceiver } from "./IRestakerRewardReceiver.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

interface IDelegation is IRestakerRewardReceiver {
    /// @custom:storage-location erc7201:cap.storage.Delegation
    struct DelegationStorage {
        EnumerableSet.AddressSet agents;
        mapping(address => AgentData) agentData;
        EnumerableSet.AddressSet networks;
        address oracle;
        uint256 epochDuration;
        uint256 ltvBuffer;
    }

    struct AgentData {
        address network;
        uint256 ltv;
        uint256 liquidationThreshold;
        uint256 lastBorrow;
    }

    /// @notice Slash a network
    /// @param network Network address
    /// @param slashShare Slash share
    event SlashNetwork(address network, uint256 slashShare);

    /// @notice Add an agent
    /// @param agent Agent address
    /// @param ltv LTV
    /// @param liquidationThreshold Liquidation threshold
    event AddAgent(address agent, address network, uint256 ltv, uint256 liquidationThreshold);

    /// @notice Modify an agent
    /// @param agent Agent address
    /// @param ltv LTV
    /// @param liquidationThreshold Liquidation threshold
    event ModifyAgent(address agent, uint256 ltv, uint256 liquidationThreshold);

    /// @notice Register a network
    /// @param network Network address
    event RegisterNetwork(address network);

    /// @notice Distribute a reward
    /// @param agent Agent address
    /// @param asset Asset address
    /// @param amount Amount
    event DistributeReward(address agent, address asset, uint256 amount);

    /// @notice Set the ltv buffer
    /// @param ltvBuffer LTV buffer
    event SetLtvBuffer(uint256 ltvBuffer);

    /// @notice Agent does not exist
    error AgentDoesNotExist();

    /// @notice Duplicate agent
    error DuplicateAgent();

    /// @notice Duplicate network
    error DuplicateNetwork();

    /// @notice Network already registered
    error NetworkAlreadyRegistered();

    /// @notice Network does not exist
    error NetworkDoesntExist();

    /// @notice Invalid liquidation threshold
    error InvalidLiquidationThreshold();

    /// @notice Liquidation threshold too close to ltv
    error LiquidationThresholdTooCloseToLtv();

    /// @notice Invalid ltv buffer
    error InvalidLtvBuffer();

    /// @notice Invalid network
    error InvalidNetwork();

    /// @notice No slashable collateral
    error NoSlashableCollateral();

    /// @notice Initialize the contract
    /// @param _accessControl Access control address
    /// @param _oracle Oracle address
    /// @param _epochDuration Epoch duration in seconds
    function initialize(address _accessControl, address _oracle, uint256 _epochDuration) external;

    /// @notice Get the epoch duration
    /// @return duration Epoch duration in seconds
    function epochDuration() external view returns (uint256 duration);

    /// @notice Get the current epoch
    /// @return currentEpoch Current epoch
    function epoch() external view returns (uint256 currentEpoch);

    /// @notice Get the ltv buffer
    /// @return buffer LTV buffer
    function ltvBuffer() external view returns (uint256 buffer);

    /// @notice Get the timestamp that is most recent between the last borrow and the epoch -1
    /// @param _agent The agent address
    /// @return _slashTimestamp Timestamp that is most recent between the last borrow and the epoch -1
    function slashTimestamp(address _agent) external view returns (uint48 _slashTimestamp);

    /// @notice How much delegation and agent has available to back their borrows
    /// @param _agent The agent address
    /// @return delegation Amount in USD (8 decimals) that a agent has provided as delegation from the delegators
    function coverage(address _agent) external view returns (uint256 delegation);

    /// @notice How much slashable coverage an agent has available to back their borrows
    /// @param _agent The agent address
    /// @return _slashableCollateral Amount in USD (8 decimals) that a agent has provided as slashable collateral from the delegators
    function slashableCollateral(address _agent) external view returns (uint256 _slashableCollateral);

    /// @notice Fetch active network address
    /// @param _agent Agent address
    /// @return networkAddress network address
    function networks(address _agent) external view returns (address networkAddress);

    /// @notice Fetch active agent addresses
    /// @return agentAddresses Agent addresses
    function agents() external view returns (address[] memory agentAddresses);

    /// @notice The LTV of a specific agent
    /// @param _agent Agent who we are querying
    /// @return currentLtv Loan to value ratio of the agent
    function ltv(address _agent) external view returns (uint256 currentLtv);

    /// @notice Liquidation threshold of the agent
    /// @param _agent Agent who we are querying
    /// @return lt Liquidation threshold of the agent
    function liquidationThreshold(address _agent) external view returns (uint256 lt);

    /// @notice The slash function. Calls the underlying networks to slash the delegated capital
    /// @dev Called only by the lender during liquidation
    /// @param _agent The agent who is unhealthy
    /// @param _liquidator The liquidator who receives the funds
    /// @param _amount The USD value of the delegation needed to cover the debt
    function slash(address _agent, address _liquidator, uint256 _amount) external;

    /// @notice Distribute rewards to networks covering an agent proportionally to their coverage
    /// @param _agent The agent address
    /// @param _asset The reward token address
    function distributeRewards(address _agent, address _asset) external;

    /// @notice Set the last borrow timestamp for an agent
    /// @param _agent Agent address
    function setLastBorrow(address _agent) external;

    /// @notice Add agent to be delegated to
    /// @param _agent Agent address
    /// @param _network Network address
    /// @param _ltv Loan to value ratio
    /// @param _liquidationThreshold Liquidation threshold
    function addAgent(address _agent, address _network, uint256 _ltv, uint256 _liquidationThreshold) external;

    /// @notice Modify an agents config only callable by the operator
    /// @param _agent the agent to modify
    /// @param _ltv Loan to value ratio
    /// @param _liquidationThreshold Liquidation threshold
    function modifyAgent(address _agent, uint256 _ltv, uint256 _liquidationThreshold) external;

    /// @notice Register a new network
    /// @param _network Network address
    function registerNetwork(address _network) external;

    /// @notice Set the ltv buffer
    /// @param _ltvBuffer LTV buffer
    function setLtvBuffer(uint256 _ltvBuffer) external;
}
