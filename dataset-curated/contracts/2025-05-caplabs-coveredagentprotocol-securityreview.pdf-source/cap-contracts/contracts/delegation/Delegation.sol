// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { Access } from "../access/Access.sol";

import { IDelegation } from "../interfaces/IDelegation.sol";
import { INetworkMiddleware } from "../interfaces/INetworkMiddleware.sol";

import { DelegationStorageUtils } from "../storage/DelegationStorageUtils.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/// @title Cap Delegation Contract
/// @author Cap Labs
/// @notice This contract manages delegation and slashing.
contract Delegation is IDelegation, UUPSUpgradeable, Access, DelegationStorageUtils {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

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
        $.ltvBuffer = 0.05e27; // 5%
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

    /// @notice Get the ltv buffer
    /// @return buffer LTV buffer
    function ltvBuffer() external view returns (uint256 buffer) {
        buffer = getDelegationStorage().ltvBuffer;
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
        delegation = INetworkMiddleware($.agentData[_agent].network).coverage(_agent);
    }

    /// @notice How much slashable coverage an agent has available to back their borrows
    /// @param _agent The agent address
    /// @return _slashableCollateral Amount in USD (8 decimals) that a agent has provided as slashable collateral from the delegators
    function slashableCollateral(address _agent) public view returns (uint256 _slashableCollateral) {
        DelegationStorage storage $ = getDelegationStorage();
        uint48 _slashTimestamp = slashTimestamp(_agent);
        _slashableCollateral =
            INetworkMiddleware($.agentData[_agent].network).slashableCollateral(_agent, _slashTimestamp);
    }

    /// @notice Fetch active network address
    /// @param _agent Agent address
    /// @return networkAddress network address
    function networks(address _agent) external view returns (address networkAddress) {
        networkAddress = getDelegationStorage().agentData[_agent].network;
    }

    /// @notice Fetch active agent addresses
    /// @return agentAddresses Agent addresses
    function agents() external view returns (address[] memory agentAddresses) {
        agentAddresses = getDelegationStorage().agents.values();
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

        address network = $.agentData[_agent].network;
        uint256 networkSlashableCollateral = INetworkMiddleware(network).slashableCollateral(_agent, _slashTimestamp);
        if (networkSlashableCollateral == 0) revert NoSlashableCollateral();
        uint256 slashShare = _amount * 1e18 / networkSlashableCollateral;
        if (slashShare > 1e18) slashShare = 1e18;

        INetworkMiddleware(network).slash(_agent, _liquidator, slashShare, _slashTimestamp);
        emit SlashNetwork(network, _amount);
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

        address network = $.agentData[_agent].network;
        IERC20(_asset).safeTransfer(network, _amount);
        INetworkMiddleware(network).distributeRewards(_agent, _asset);

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
    /// @param _network Network address
    /// @param _ltv Loan to value ratio
    /// @param _liquidationThreshold Liquidation threshold
    function addAgent(address _agent, address _network, uint256 _ltv, uint256 _liquidationThreshold)
        external
        checkAccess(this.addAgent.selector)
    {
        DelegationStorage storage $ = getDelegationStorage();

        // if ltv is greater than 100% then agent could borrow more than they are collateralized for
        if (_liquidationThreshold > 1e27) revert InvalidLiquidationThreshold();
        if (_ltv != 0 && _liquidationThreshold < _ltv + $.ltvBuffer) revert LiquidationThresholdTooCloseToLtv();

        // If the agent already exists, we revert
        if ($.agents.contains(_agent)) revert DuplicateAgent();
        if (!$.networks.contains(_network)) revert NetworkDoesntExist();

        $.agents.add(_agent);
        $.agentData[_agent].network = _network;
        $.agentData[_agent].ltv = _ltv;
        $.agentData[_agent].liquidationThreshold = _liquidationThreshold;
        emit AddAgent(_agent, _network, _ltv, _liquidationThreshold);
    }

    /// @notice Modify an agents config only callable by the operator
    /// @param _agent the agent to modify
    /// @param _ltv Loan to value ratio
    /// @param _liquidationThreshold Liquidation threshold
    function modifyAgent(address _agent, uint256 _ltv, uint256 _liquidationThreshold)
        external
        checkAccess(this.modifyAgent.selector)
    {
        DelegationStorage storage $ = getDelegationStorage();

        // if ltv is greater than 100% then agent could borrow more than they are collateralized for
        if (_liquidationThreshold > 1e27) revert InvalidLiquidationThreshold();
        if (_ltv != 0 && _liquidationThreshold < _ltv + $.ltvBuffer) revert LiquidationThresholdTooCloseToLtv();

        // Check that the agent exists
        if (!$.agents.contains(_agent)) revert AgentDoesNotExist();

        $.agentData[_agent].ltv = _ltv;
        $.agentData[_agent].liquidationThreshold = _liquidationThreshold;
        emit ModifyAgent(_agent, _ltv, _liquidationThreshold);
    }

    /// @notice Register a new network
    /// @param _network Network address
    function registerNetwork(address _network) external checkAccess(this.registerNetwork.selector) {
        DelegationStorage storage $ = getDelegationStorage();
        if (_network == address(0)) revert InvalidNetwork();

        // Check for duplicates
        if ($.networks.contains(_network)) revert DuplicateNetwork();

        $.networks.add(_network);
        emit RegisterNetwork(_network);
    }

    /// @notice Check if a network is registered
    /// @param _network Network address
    /// @return _exists Whether the network is registered
    function networkExists(address _network) external view returns (bool) {
        return getDelegationStorage().networks.contains(_network);
    }

    /// @notice Set the ltv buffer
    /// @param _ltvBuffer LTV buffer
    function setLtvBuffer(uint256 _ltvBuffer) external checkAccess(this.setLtvBuffer.selector) {
        if (_ltvBuffer > 1e27) revert InvalidLtvBuffer();
        getDelegationStorage().ltvBuffer = _ltvBuffer;
        emit SetLtvBuffer(_ltvBuffer);
    }

    /// @dev Only admin can upgrade
    function _authorizeUpgrade(address) internal override checkAccess(bytes4(0)) { }
}
