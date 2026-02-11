// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import "@openzeppelin/contracts/access/Ownable.sol";

import "./interfaces/IStakingPool.sol";
import "./interfaces/IPriorityPool.sol";
import "./interfaces/IStrategy.sol";
import "./interfaces/ISecurityPool.sol";

/**
 * @title Rebase Controller
 * @notice Updates strategy rewards in the Staking Pool and and performs emergency pausing/reopening of the pool
 */
contract RebaseController is Ownable {
    // address of staking pool
    IStakingPool public stakingPool;
    // address of priority pool
    IPriorityPool public priorityPool;
    // address of security pool
    ISecurityPool public securityPool;

    // address authorized to pause pool in case of emergency
    address public emergencyPauser;
    // address authorized to update rewards
    address public rewardsUpdater;

    error PoolClosed();
    error PoolOpen();
    error SenderNotAuthorized();
    error NoLossDetected();

    /**
     * @notice Initializes contract
     * @param _stakingPool address of staking pool
     * @param _priorityPool address of priority pool
     * @param _securityPool address of security pool
     * @param _emergencyPauser address authorized to pause pool in case of emergency
     * @param _rewardsUpdater address authorized to update rewards
     */
    constructor(
        address _stakingPool,
        address _priorityPool,
        address _securityPool,
        address _emergencyPauser,
        address _rewardsUpdater
    ) {
        stakingPool = IStakingPool(_stakingPool);
        priorityPool = IPriorityPool(_priorityPool);
        securityPool = ISecurityPool(_securityPool);
        emergencyPauser = _emergencyPauser;
        rewardsUpdater = _rewardsUpdater;
    }

    /**
     * @notice Reverts if sender is not emergency pauser
     */
    modifier onlyEmergencyPauser() {
        if (msg.sender != emergencyPauser) revert SenderNotAuthorized();
        _;
    }

    /**
     * @notice Reverts if sender is not rewards updater
     */
    modifier onlyRewardsUpdater() {
        if (msg.sender != rewardsUpdater) revert SenderNotAuthorized();
        _;
    }

    /**
     * @notice Updates strategy rewards in the staking pool
     * @param _data encoded data to pass to strategies
     **/
    function updateRewards(bytes calldata _data) external onlyRewardsUpdater {
        if (priorityPool.poolStatus() == IPriorityPool.PoolStatus.CLOSED) revert PoolClosed();
        _updateRewards(_data);
    }

    /**
     * @notice Returns whether a loss has been detected in a strategy
     * @return upkeepNeeded whether or not loss has been detected
     * @return performData abi encoded index of strategy with a loss
     **/
    function checkUpkeep(bytes calldata) external view returns (bool, bytes memory) {
        if (priorityPool.poolStatus() == IPriorityPool.PoolStatus.CLOSED) return (false, "");

        address[] memory strategies = stakingPool.getStrategies();

        for (uint256 i = 0; i < strategies.length; ++i) {
            int256 depositChange = IStrategy(strategies[i]).getDepositChange();
            if (depositChange < 0) {
                return (true, abi.encode(i));
            }
        }

        return (false, "");
    }

    /**
     * @notice Pauses the priority pool if a loss has been detected
     * @param _performData abi encoded index of strategy with a loss
     */
    function performUpkeep(bytes calldata _performData) external {
        if (priorityPool.poolStatus() == IPriorityPool.PoolStatus.CLOSED) revert PoolClosed();

        uint256 strategyIdxWithLoss = abi.decode(_performData, (uint256));
        address[] memory strategies = stakingPool.getStrategies();

        if (IStrategy(strategies[strategyIdxWithLoss]).getDepositChange() >= 0)
            revert NoLossDetected();

        priorityPool.setPoolStatus(IPriorityPool.PoolStatus.CLOSED);
        if (address(securityPool) != address(0)) securityPool.initiateClaim();
    }

    /**
     * @notice Pauses the priority pool in the case of an emergency
     */
    function pausePool() external onlyEmergencyPauser {
        if (priorityPool.poolStatus() == IPriorityPool.PoolStatus.CLOSED) revert PoolClosed();

        priorityPool.setPoolStatus(IPriorityPool.PoolStatus.CLOSED);
        if (address(securityPool) != address(0)) securityPool.initiateClaim();
    }

    /**
     * @notice Reopens the priority pool and security pool after they were paused as a result
     * of a loss and updates strategy rewards in the staking pool
     * @param _data encoded data to pass to strategies
     */
    function reopenPool(bytes calldata _data) external onlyOwner {
        if (priorityPool.poolStatus() == IPriorityPool.PoolStatus.OPEN) revert PoolOpen();

        priorityPool.setPoolStatus(IPriorityPool.PoolStatus.OPEN);
        if (address(securityPool) != address(0) && securityPool.claimInProgress()) {
            securityPool.resolveClaim();
        }
        _updateRewards(_data);
    }

    /**
     * @notice Sets the address authorized to pause the pool in the case of emergency
     * @param _emergencyPauser address of emergency pauser
     */
    function setEmergencyPauser(address _emergencyPauser) external onlyOwner {
        emergencyPauser = _emergencyPauser;
    }

    /**
     * @notice Sets the address authorized to update rewards
     * @param _rewardsUpdater address of rewards updater
     */
    function setRewardsUpdater(address _rewardsUpdater) external onlyOwner {
        rewardsUpdater = _rewardsUpdater;
    }

    /**
     * @notice Updates strategy rewards in the staking pool
     * @param _data encoded data to pass to strategies
     **/
    function _updateRewards(bytes memory _data) private {
        address[] memory strategies = stakingPool.getStrategies();
        uint256[] memory strategyIdxs = new uint256[](strategies.length);

        for (uint256 i = 0; i < strategies.length; ++i) {
            strategyIdxs[i] = i;
        }

        stakingPool.updateStrategyRewards(strategyIdxs, _data);
    }
}
