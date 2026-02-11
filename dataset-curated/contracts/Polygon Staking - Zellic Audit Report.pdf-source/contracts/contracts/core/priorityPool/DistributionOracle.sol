// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import "@chainlink/contracts/src/v0.8/ChainlinkClient.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "../interfaces/IPriorityPool.sol";
import "../interfaces/IStakingPool.sol";

contract DistributionOracle is ChainlinkClient, Ownable {
    using Chainlink for Chainlink.Request;

    enum UpkeepType {
        PAUSE,
        REQUEST
    }

    struct UpdateStatus {
        uint64 timeOfLastUpdate;
        uint64 pausedAtBlockNumber;
        uint128 requestInProgress;
    }

    struct UpdateData {
        bytes32 merkleRoot;
        bytes32 ipfsHash;
        uint256 amountDistributed;
        uint256 sharesAmountDistributed;
    }

    IPriorityPool public immutable priorityPool;

    bytes32 public jobId;
    uint256 public fee;

    uint64 public minTimeBetweenUpdates;
    uint64 public minBlockConfirmations;
    uint128 public minDepositsSinceLastUpdate;

    UpdateStatus public updateStatus;

    uint128 public manualVerificationRequired;
    uint128 public awaitingManualVerification;
    UpdateData public updateData;

    event SetUpdateParams(
        uint64 minTimeBetweenUpdates,
        uint128 minDepositsSinceLastUpdate,
        uint64 minBlockConfirmations
    );
    event SetChainlinkParams(bytes32 jobId, uint256 fee);
    event ToggleManualVerification(uint128 manualVerificationRequired);

    error NotPaused();
    error InsufficientBlockConfirmations();
    error InsufficientBalance();
    error UpdateConditionsNotMet();
    error InvalidUpkeepType();
    error RequestInProgress();
    error NoVerificationPending();
    error AwaitingManualVerification();

    /**
     * @notice Initialize the contract
     * @param _chainlinkToken address of LINK token
     * @param _chainlinkOracle address of operator contract
     * @param _jobId id of job
     * @param _fee fee charged for each request paid in LINK
     * @param _minTimeBetweenUpdates min amount of seconds between updates
     * @param _minDepositsSinceLastUpdate min amount of deposits from the priority pool to the
     *         staking pool needed to request update
     * @param _minBlockConfirmations min # of blocks to wait to request update after pausing priority pool
     * @param _priorityPool address of priority pool
     */
    constructor(
        address _chainlinkToken,
        address _chainlinkOracle,
        bytes32 _jobId,
        uint256 _fee,
        uint64 _minTimeBetweenUpdates,
        uint128 _minDepositsSinceLastUpdate,
        uint64 _minBlockConfirmations,
        address _priorityPool
    ) {
        setChainlinkToken(_chainlinkToken);
        setChainlinkOracle(_chainlinkOracle);
        jobId = _jobId;
        fee = _fee;
        minTimeBetweenUpdates = _minTimeBetweenUpdates;
        minDepositsSinceLastUpdate = _minDepositsSinceLastUpdate;
        minBlockConfirmations = _minBlockConfirmations;
        priorityPool = IPriorityPool(_priorityPool);
        manualVerificationRequired = 1;
    }

    /**
     * @notice returns whether a call should be made to performUpkeep to pause or request an update
     * @dev used by chainlink keepers
     * @return upkeepNeeded whether or not to pause or request update
     * @return performData abi encoded upkeep type to perform
     */
    function checkUpkeep(bytes calldata) external view returns (bool, bytes memory) {
        bool shouldPauseForUpdate = !priorityPool.paused() &&
            awaitingManualVerification == 0 &&
            (block.timestamp >= updateStatus.timeOfLastUpdate + minTimeBetweenUpdates) &&
            priorityPool.depositsSinceLastUpdate() >= minDepositsSinceLastUpdate;

        if (shouldPauseForUpdate) {
            return (true, abi.encode(UpkeepType.PAUSE));
        }

        bool shouldRequestUpdate = priorityPool.paused() &&
            awaitingManualVerification == 0 &&
            updateStatus.requestInProgress == 0 &&
            (block.number >= updateStatus.pausedAtBlockNumber + minBlockConfirmations);

        if (shouldRequestUpdate) {
            return (true, abi.encode(UpkeepType.REQUEST));
        }

        return (false, bytes(""));
    }

    /**
     * @notice deposits queued tokens into the staking pool
     * @dev used by chainlink keepers
     * @param _performData abi encoded upkeep type to perform
     */
    function performUpkeep(bytes calldata _performData) external {
        UpkeepType upkeepType = abi.decode(_performData, (UpkeepType));

        if (upkeepType == UpkeepType.PAUSE) {
            if (priorityPool.depositsSinceLastUpdate() < minDepositsSinceLastUpdate)
                revert UpdateConditionsNotMet();
            _pauseForUpdate();
        } else if (upkeepType == UpkeepType.REQUEST) {
            _requestUpdate();
        } else {
            revert InvalidUpkeepType();
        }
    }

    /**
     * @notice Pauses the priority pool so a new merkle tree can be calculated
     * @dev must always be called before requestUpdate()
     */
    function pauseForUpdate() external onlyOwner {
        _pauseForUpdate();
    }

    /**
     * @notice Requests a new update which will calculate a new merkle tree, post the data to IPFS, and update
     * the priority pool
     * @dev pauseForUpdate() must be called before calling this function
     */
    function requestUpdate() external onlyOwner {
        _requestUpdate();
    }

    /**
     * @notice Fulfills an update request
     * @param _requestId id of the request to fulfill
     * @param _merkleRoot new merkle root for the distribution tree
     * @param _ipfsHash new ipfs hash for the distribution tree (CIDv0, no prefix - only hash)
     * @param _amountDistributed amount of LSD tokens distributed in this distribution
     * @param _sharesAmountDistributed amount of LSD shares distributed in this distribution
     */
    function fulfillRequest(
        bytes32 _requestId,
        bytes32 _merkleRoot,
        bytes32 _ipfsHash,
        uint256 _amountDistributed,
        uint256 _sharesAmountDistributed
    ) public recordChainlinkFulfillment(_requestId) {
        if (manualVerificationRequired == 1) {
            updateData = UpdateData(
                _merkleRoot,
                _ipfsHash,
                _amountDistributed,
                _sharesAmountDistributed
            );
            awaitingManualVerification = 1;
        } else {
            priorityPool.updateDistribution(
                _merkleRoot,
                _ipfsHash,
                _amountDistributed,
                _sharesAmountDistributed
            );
        }
        updateStatus.requestInProgress = 0;
    }

    /**
     * @notice Executes a manual verification update request
     * */
    function executeManualVerification() external onlyOwner {
        if (awaitingManualVerification == 0) revert NoVerificationPending();
        awaitingManualVerification = 0;

        priorityPool.updateDistribution(
            updateData.merkleRoot,
            updateData.ipfsHash,
            updateData.amountDistributed,
            updateData.sharesAmountDistributed
        );
    }

    /**
     * @notice Rejects a manual verification update request and requests a new update
     * */
    function rejectManualVerificationAndRetry() external onlyOwner {
        if (awaitingManualVerification == 0) revert NoVerificationPending();
        awaitingManualVerification = 0;
        _requestUpdate();
    }

    /**
     * @notice Cancels a request if it has not been fulfilled
     * @param _requestId request ID
     * @param _expiration time of the expiration for the request
     */
    function cancelRequest(bytes32 _requestId, uint256 _expiration) external onlyOwner {
        cancelChainlinkRequest(_requestId, fee, this.fulfillRequest.selector, _expiration);
        updateStatus.requestInProgress = 0;
    }

    /**
     * @notice Withdraws LINK tokens
     * @param _amount amount to withdraw
     */
    function withdrawLink(uint256 _amount) external onlyOwner {
        LinkTokenInterface link = LinkTokenInterface(chainlinkTokenAddress());
        if (link.transfer(msg.sender, _amount) != true) revert InsufficientBalance();
    }

    /**
     * @notice Sets the params used to determine update frequency
     * @param _minTimeBetweenUpdates min amount of seconds between updates
     * @param _minDepositsSinceLastUpdate min amount of deposits from the priority pool to the
     *         staking pool needed to request update
     * @param _minBlockConfirmations min # of blocks to wait to request update after pausing priority pool
     * */
    function setUpdateParams(
        uint64 _minTimeBetweenUpdates,
        uint128 _minDepositsSinceLastUpdate,
        uint64 _minBlockConfirmations
    ) external onlyOwner {
        minTimeBetweenUpdates = _minTimeBetweenUpdates;
        minDepositsSinceLastUpdate = _minDepositsSinceLastUpdate;
        minBlockConfirmations = _minBlockConfirmations;
        emit SetUpdateParams(
            _minTimeBetweenUpdates,
            _minDepositsSinceLastUpdate,
            _minBlockConfirmations
        );
    }

    /**
     * @notice Toggles whether manual verification is required for updates
     * */
    function toggleManualVerification() external onlyOwner {
        manualVerificationRequired = manualVerificationRequired == 1 ? 0 : 1;
        emit ToggleManualVerification(manualVerificationRequired);
    }

    /**
     * @notice Sets the params related to Chainlink requests
     * @param _jobId id of job
     * @param _fee fee charged for each request paid in LINK
     * */
    function setChainlinkParams(bytes32 _jobId, uint256 _fee) external onlyOwner {
        jobId = _jobId;
        fee = _fee;
        emit SetChainlinkParams(_jobId, _fee);
    }

    /**
     * @notice Pauses the priority pool so a new merkle tree can be calculated
     * @dev must always be called before requestUpdate()
     */
    function _pauseForUpdate() private {
        if (block.timestamp < updateStatus.timeOfLastUpdate + minTimeBetweenUpdates)
            revert UpdateConditionsNotMet();
        if (awaitingManualVerification == 1) revert AwaitingManualVerification();
        priorityPool.pauseForUpdate();
        updateStatus = UpdateStatus(uint64(block.timestamp), uint64(block.number), 0);
    }

    /**
     * @notice Requests a new update which will calculate a new merkle tree, post the data to IPFS, and update
     * the priority pool
     * @dev pauseForUpdate() must be called before calling this function
     */
    function _requestUpdate() private {
        UpdateStatus memory status = updateStatus;

        if (!priorityPool.paused()) revert NotPaused();
        if (block.number < status.pausedAtBlockNumber + minBlockConfirmations)
            revert InsufficientBlockConfirmations();
        if (status.requestInProgress == 1) revert RequestInProgress();
        if (awaitingManualVerification == 1) revert AwaitingManualVerification();

        updateStatus.requestInProgress = 1;

        Chainlink.Request memory req = buildChainlinkRequest(
            jobId,
            address(this),
            this.fulfillRequest.selector
        );
        req.addUint("blockNumber", status.pausedAtBlockNumber);
        sendChainlinkRequest(req, fee);
    }
}
