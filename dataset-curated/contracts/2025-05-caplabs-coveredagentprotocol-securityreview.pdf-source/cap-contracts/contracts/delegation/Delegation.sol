// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { Access } from "../access/Access.sol";

import { IDelegation } from "../interfaces/IDelegation.sol";
import { INetworkMiddleware } from "../interfaces/INetworkMiddleware.sol";

import { IRestakerRewardReceiver } from "../interfaces/IRestakerRewardReceiver.sol";

import { DelegationStorageUtils } from "../storage/DelegationStorageUtils.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title Cap Delegation Contract
/// @author Cap Labs
/// @notice This contract manages delegation and slashing.
contract Delegation is IDelegation, UUPSUpgradeable, Access, DelegationStorageUtils {
    using SafeERC20 for IERC20;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialize the contract
    /// @param _accessControl Access control address
    /// @param _oracle Oracle address
    /// @param _epochDuration Epoch duration in seconds
    function initialize(address _accessControl, address _oracle, uint256 _epochDuration) external initializer {
        __Access_init(_accessControl);
        __UUPSUpgradeable_init();
        DelegationStorage storage $ = getDelegationStorage();
        $.oracle = _oracle;
        $.epochDuration = _epochDuration;
    }

    /// @notice How much global delegation we have in the system
    /// @return delegation Delegation in USD
    function globalDelegation() external view returns (uint256 delegation) {
        DelegationStorage storage $ = getDelegationStorage();
        for (uint i; i < $.agents.length; ++i) {
            delegation += coverage($.agents[i]);
        }
    }

    /// @notice Get the epoch duration
    /// @return duration Epoch duration in seconds
    function epochDuration() external view returns (uint256 duration) {
        DelegationStorage storage $ = getDelegationStorage();
        duration = $.epochDuration;
    }

    /// @notice Get the current epoch
    /// @return currentEpoch Current epoch
    function epoch() public view returns (uint256 currentEpoch) {
        DelegationStorage storage $ = getDelegationStorage();
        currentEpoch = block.timestamp / $.epochDuration;
    }

    /// @notice Get the timestamp that is most recent between the last borrow and the epoch -1
    /// @param _agent The agent address
    /// @return _slashTimestamp Timestamp that is most recent between the last borrow and the epoch -1
    function slashTimestamp(address _agent) public view returns (uint48 _slashTimestamp) {
        DelegationStorage storage $ = getDelegationStorage();
        _slashTimestamp = uint48(Math.max((epoch() - 1) * $.epochDuration, $.agentData[_agent].lastBorrow));
    }

    /// @notice How much delegation and agent has available to back their borrows
    /// @param _agent The agent address
    /// @return delegation Amount in USD (8 decimals) that a agent has provided as delegation from the delegators
    function coverage(address _agent) public view returns (uint256 delegation) {
        DelegationStorage storage $ = getDelegationStorage();
        for (uint i; i < $.networks[_agent].length; ++i) {
            delegation += coverageByNetwork(_agent, $.networks[_agent][i]);
        }
    }

    /// @notice How much slashable coverage an agent has available to back their borrows
    /// @param _agent The agent address
    /// @return _slashableCollateral Amount in USD (8 decimals) that a agent has provided as slashable collateral from the delegators
    function slashableCollateral(address _agent) public view returns (uint256 _slashableCollateral) {
        DelegationStorage storage $ = getDelegationStorage();
        uint48 _slashTimestamp = slashTimestamp(_agent);
        for (uint i; i < $.networks[_agent].length; ++i) {
            _slashableCollateral +=
                INetworkMiddleware($.networks[_agent][i]).slashableCollateral(_agent, _slashTimestamp);
        }
    }

    /// @notice How much delegation and agent has available to back their borrows
    /// @param _agent The agent addres
    /// @param _network The network covering the agent
    /// @return delegation Amount in USD that a agent has as delegation from the networks, encoded with 8 decimals
    function coverageByNetwork(address _agent, address _network) public view returns (uint256 delegation) {
        delegation = INetworkMiddleware(_network).coverage(_agent);
    }

    /// @notice Slashable collateral of an agent by a specific network
    /// @param _agent Agent address
    /// @param _network Network address
    /// @return _slashableCollateral Slashable collateral amount in USD (8 decimals)
    function slashableCollateralByNetwork(address _agent, address _network)
        public
        view
        returns (uint256 _slashableCollateral)
    {
        uint48 _slashTimestamp = slashTimestamp(_agent);
        _slashableCollateral = INetworkMiddleware(_network).slashableCollateral(_agent, _slashTimestamp);
    }

    /// @notice Fetch active network addresses
    /// @param _agent Agent address
    /// @return networkAddresses network addresses
    function networks(address _agent) external view returns (address[] memory networkAddresses) {
        networkAddresses = getDelegationStorage().networks[_agent];
    }

    /// @notice Fetch active agent addresses
    /// @return agentAddresses Agent addresses
    function agents() external view returns (address[] memory agentAddresses) {
        agentAddresses = getDelegationStorage().agents;
    }

    /// @notice The LTV of a specific agent
    /// @param _agent Agent who we are querying
    /// @return currentLtv Loan to value ratio of the agent
    function ltv(address _agent) external view returns (uint256 currentLtv) {
        currentLtv = getDelegationStorage().agentData[_agent].ltv;
    }

    /// @notice Liquidation threshold of the agent
    /// @param _agent Agent who we are querying
    /// @return lt Liquidation threshold of the agent
    function liquidationThreshold(address _agent) external view returns (uint256 lt) {
        lt = getDelegationStorage().agentData[_agent].liquidationThreshold;
    }

    /// @notice The slash function. Calls the underlying networks to slash the delegated capital
    /// @dev Called only by the lender during liquidation
    /// @param _agent The agent who is unhealthy
    /// @param _liquidator The liquidator who receives the funds
    /// @param _amount The USD value of the delegation needed to cover the debt
    function slash(address _agent, address _liquidator, uint256 _amount) external checkAccess(this.slash.selector) {
        DelegationStorage storage $ = getDelegationStorage();
        uint48 _slashTimestamp = slashTimestamp(_agent);

        // Calculate each network's proportion of total delegation
        for (uint i; i < $.networks[_agent].length; ++i) {
            address network = $.networks[_agent][i];
            uint256 networkSlashableCollateral =
                INetworkMiddleware(network).slashableCollateral(_agent, _slashTimestamp);
            if (networkSlashableCollateral == 0) continue;

            // Calculate this network's share of the total amount to slash
            uint256 networkSlash = _amount * 1e18 / networkSlashableCollateral;
            INetworkMiddleware(network).slash(_agent, _liquidator, networkSlash, _slashTimestamp);
            emit SlashNetwork(network, networkSlash);
        }
    }

    /// @notice Distribute rewards to networks covering an agent proportionally to their coverage
    /// @param _agent The agent address
    /// @param _asset The reward token address
    function distributeRewards(address _agent, address _asset) external {
        DelegationStorage storage $ = getDelegationStorage();
        uint256 _amount = IERC20(_asset).balanceOf(address(this));

        uint256 totalCoverage = coverage(_agent);
        // here we cannot revert because the agent might not have any coverage
        // in case we are liquidating the current agent due to 0 coverage
        if (totalCoverage == 0) return;

        // Distribute to each network based on their coverage proportion
        for (uint i; i < $.networks[_agent].length; ++i) {
            address network = $.networks[_agent][i];
            uint256 networkCoverage = coverageByNetwork(_agent, network);
            if (networkCoverage == 0) continue;

            uint256 networkReward = _amount * networkCoverage / totalCoverage;
            IERC20(_asset).safeTransfer(network, networkReward);
            INetworkMiddleware(network).distributeRewards(_agent, _asset);
            emit NetworkReward(network, _asset, networkReward);
        }

        emit DistributeReward(_agent, _asset, _amount);
    }

    /// @notice Set the last borrow timestamp for an agent
    /// @param _agent Agent address
    function setLastBorrow(address _agent) external checkAccess(this.setLastBorrow.selector) {
        DelegationStorage storage $ = getDelegationStorage();
        $.agentData[_agent].lastBorrow = block.timestamp;
    }

    /// @notice Add agent to be delegated to
    /// @param _agent Agent address
    /// @param _ltv Loan to value ratio
    /// @param _liquidationThreshold Liquidation threshold
    function addAgent(address _agent, uint256 _ltv, uint256 _liquidationThreshold)
        external
        checkAccess(this.addAgent.selector)
    {
        // if liquidation threshold or ltv is greater than 100%, agent
        // could borrow more than they are collateralized for
        if (_liquidationThreshold > 1e27) revert InvalidLiquidationThreshold();
        if (_ltv > 1e27) revert InvalidLtv();

        DelegationStorage storage $ = getDelegationStorage();

        // If the agent already exists, we revert
        if ($.agentData[_agent].exists) revert DuplicateAgent();

        $.agents.push(_agent);
        $.agentData[_agent].ltv = _ltv;
        $.agentData[_agent].liquidationThreshold = _liquidationThreshold;
        $.agentData[_agent].exists = true;
        emit AddAgent(_agent, _ltv, _liquidationThreshold);
    }

    /// @notice Modify an agents config only callable by the operator
    /// @param _agent the agent to modify
    /// @param _ltv Loan to value ratio
    /// @param _liquidationThreshold Liquidation threshold
    function modifyAgent(address _agent, uint256 _ltv, uint256 _liquidationThreshold)
        external
        checkAccess(this.modifyAgent.selector)
    {
        // if liquidation threshold or ltv is greater than 100%, agent
        // could borrow more than they are collateralized for
        if (_liquidationThreshold > 1e27) revert InvalidLiquidationThreshold();
        if (_ltv > 1e27) revert InvalidLtv();

        DelegationStorage storage $ = getDelegationStorage();

        // Check that the agent exists
        if (!$.agentData[_agent].exists) revert AgentDoesNotExist();

        $.agentData[_agent].ltv = _ltv;
        $.agentData[_agent].liquidationThreshold = _liquidationThreshold;
        emit ModifyAgent(_agent, _ltv, _liquidationThreshold);
    }

    /// @notice Register a new network
    /// @param _agent Agent address
    /// @param _network Network address
    function registerNetwork(address _agent, address _network) external checkAccess(this.registerNetwork.selector) {
        DelegationStorage storage $ = getDelegationStorage();

        // Check for duplicates
        if ($.networkExistsForAgent[_agent][_network]) revert DuplicateNetwork();

        $.networks[_agent].push(_network);
        $.networkExistsForAgent[_agent][_network] = true;
        emit RegisterNetwork(_agent, _network);
    }

    /// @dev Only admin can upgrade
    function _authorizeUpgrade(address) internal override checkAccess(bytes4(0)) { }
}
