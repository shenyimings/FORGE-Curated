// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IRestakerRewardReceiver } from "./IRestakerRewardReceiver.sol";

interface IDelegation is IRestakerRewardReceiver {
    /// @custom:storage-location erc7201:cap.storage.Delegation
    struct DelegationStorage {
        address[] agents;
        mapping(address => AgentData) agentData;
        mapping(address => address[]) networks;
        mapping(address => mapping(address => bool)) networkExistsForAgent;
        address oracle;
        uint256 epochDuration;
    }

    struct AgentData {
        uint256 ltv;
        uint256 liquidationThreshold;
        uint256 lastBorrow;
        bool exists;
    }

    /// @notice Slash a network
    /// @param network Network address
    /// @param slashShare Slash share
    event SlashNetwork(address network, uint256 slashShare);

    /// @notice Add an agent
    /// @param agent Agent address
    /// @param ltv LTV
    /// @param liquidationThreshold Liquidation threshold
    event AddAgent(address agent, uint256 ltv, uint256 liquidationThreshold);

    /// @notice Modify an agent
    /// @param agent Agent address
    /// @param ltv LTV
    /// @param liquidationThreshold Liquidation threshold
    event ModifyAgent(address agent, uint256 ltv, uint256 liquidationThreshold);

    /// @notice Register a network
    /// @param agent Agent address
    /// @param network Network address
    event RegisterNetwork(address agent, address network);

    /// @notice Distribute a reward
    /// @param agent Agent address
    /// @param asset Asset address
    /// @param amount Amount
    event DistributeReward(address agent, address asset, uint256 amount);

    /// @notice Network reward
    /// @param network Network address
    /// @param asset Asset address
    /// @param amount Amount
    event NetworkReward(address network, address asset, uint256 amount);

    /// @notice Agent does not exist
    error AgentDoesNotExist();

    /// @notice Duplicate agent
    error DuplicateAgent();

    /// @notice Duplicate network
    error DuplicateNetwork();

    /// @notice Invalid liquidation threshold
    error InvalidLiquidationThreshold();

    /// @notice Invalid ltv
    error InvalidLtv();

    /// @notice Initialize the contract
    /// @param _accessControl Access control address
    /// @param _oracle Oracle address
    /// @param _epochDuration Epoch duration in seconds
    function initialize(address _accessControl, address _oracle, uint256 _epochDuration) external;

    /// @notice How much global delegation we have in the system
    /// @return delegation Delegation in USD
    function globalDelegation() external view returns (uint256 delegation);

    /// @notice Get the epoch duration
    /// @return duration Epoch duration in seconds
    function epochDuration() external view returns (uint256 duration);

    /// @notice Get the current epoch
    /// @return currentEpoch Current epoch
    function epoch() external view returns (uint256 currentEpoch);

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

    /// @notice How much delegation and agent has available to back their borrows
    /// @param _agent The agent addres
    /// @param _network The network covering the agent
    /// @return delegation Amount in USD that a agent has as delegation from the networks, encoded with 8 decimals
    function coverageByNetwork(address _agent, address _network) external view returns (uint256 delegation);

    /// @notice Slashable collateral of an agent by a specific network
    /// @param _agent Agent address
    /// @param _network Network address
    /// @return _slashableCollateral Slashable collateral amount in USD (8 decimals)
    function slashableCollateralByNetwork(address _agent, address _network)
        external
        view
        returns (uint256 _slashableCollateral);

    /// @notice Fetch active network addresses
    /// @param _agent Agent address
    /// @return networkAddresses network addresses
    function networks(address _agent) external view returns (address[] memory networkAddresses);

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
    /// @param _ltv Loan to value ratio
    /// @param _liquidationThreshold Liquidation threshold
    function addAgent(address _agent, uint256 _ltv, uint256 _liquidationThreshold) external;

    /// @notice Modify an agents config only callable by the operator
    /// @param _agent the agent to modify
    /// @param _ltv Loan to value ratio
    /// @param _liquidationThreshold Liquidation threshold
    function modifyAgent(address _agent, uint256 _ltv, uint256 _liquidationThreshold) external;

    /// @notice Register a new network
    /// @param _agent Agent address
    /// @param _network Network address
    function registerNetwork(address _agent, address _network) external;
}
