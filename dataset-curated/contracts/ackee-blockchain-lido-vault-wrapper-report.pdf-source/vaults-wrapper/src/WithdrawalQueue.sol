// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IStvStETHPool} from "./interfaces/IStvStETHPool.sol";
import {IDashboard} from "./interfaces/core/IDashboard.sol";
import {ILazyOracle} from "./interfaces/core/ILazyOracle.sol";
import {IStETH} from "./interfaces/core/IStETH.sol";
import {IStakingVault} from "./interfaces/core/IStakingVault.sol";
import {IVaultHub} from "./interfaces/core/IVaultHub.sol";
import {FeaturePausable} from "./utils/FeaturePausable.sol";
import {
    AccessControlEnumerableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

/**
 * @title WithdrawalQueue
 * @notice Manages withdrawal requests from the STV Pool with queuing, finalization, and claiming
 * @dev Handles the complete lifecycle of withdrawal requests including optional stETH rebalancing,
 * and discount mechanisms
 */
contract WithdrawalQueue is AccessControlEnumerableUpgradeable, FeaturePausable {
    using SafeCast for uint256;
    using EnumerableSet for EnumerableSet.UintSet;

    /// @notice Min delay between withdrawal request and finalization
    /// @dev Contract enforces a minimum 1-hour delay to ensure the value is set within reasonable bounds
    uint256 public immutable MIN_WITHDRAWAL_DELAY_TIME_IN_SECONDS;

    // ACL
    bytes32 public constant WITHDRAWALS_FEATURE = keccak256("WITHDRAWALS_FEATURE");
    bytes32 public constant WITHDRAWALS_PAUSE_ROLE = keccak256("WITHDRAWALS_PAUSE_ROLE");
    bytes32 public constant WITHDRAWALS_RESUME_ROLE = keccak256("WITHDRAWALS_RESUME_ROLE");

    bytes32 public constant FINALIZE_FEATURE = keccak256("FINALIZE_FEATURE");
    bytes32 public constant FINALIZE_PAUSE_ROLE = keccak256("FINALIZE_PAUSE_ROLE");
    bytes32 public constant FINALIZE_RESUME_ROLE = keccak256("FINALIZE_RESUME_ROLE");
    bytes32 public constant FINALIZE_ROLE = keccak256("FINALIZE_ROLE");

    /// @notice Precision base for stv and steth share rates
    uint256 public constant E27_PRECISION_BASE = 1e27;
    uint256 public constant E36_PRECISION_BASE = 1e36;

    /// @notice Maximum gas cost coverage that can be applied for a single request
    /// @dev High enough to cover gas costs for finalization tx
    /// @dev Low enough to prevent abuse by excessive gas cost coverage
    ///
    /// Request finalization tx for 1 request consumes ~200k gas
    /// Request finalization tx for 10 requests (in batch) consumes ~300k gas
    /// Thus, setting max coverage to 0.0005 ether should be sufficient to cover finalization gas costs:
    /// - when gas price is up to 2.5 gwei for tx with a single request (0.0005 eth / 200k gas = 2.5 gwei per gas)
    /// - when gas price is up to 16.6 gwei for batched tx of 10 requests (10 * 0.0005 eth / 300k gas = 16.6 gwei per gas)
    uint256 public constant MAX_GAS_COST_COVERAGE = 0.0005 ether;

    /// @notice Minimal value (assets - stETH to rebalance) that is possible to request
    /// @dev Prevents placing many small requests
    uint256 public constant MIN_WITHDRAWAL_VALUE = 0.001 ether;

    /// @notice Maximum amount of assets that is possible to withdraw in a single request
    /// @dev Prevents accumulating too much funds per single request fulfillment in the future
    /// @dev To withdraw larger amounts, it's recommended to split it to several requests
    uint256 public constant MAX_WITHDRAWAL_ASSETS = 10_000 ether;

    /// @dev Return value for the `findCheckpointHint` method in case of no result
    uint256 internal constant NOT_FOUND = 0;

    /// @notice Flag indicating whether the pool supports rebalancing of steth shares
    bool public immutable IS_REBALANCING_SUPPORTED;

    IStvStETHPool public immutable POOL;
    IVaultHub public immutable VAULT_HUB;
    IDashboard public immutable DASHBOARD;
    IStETH public immutable STETH;
    ILazyOracle public immutable LAZY_ORACLE;
    IStakingVault public immutable VAULT;

    /// @notice Structure representing a request for withdrawal
    struct WithdrawalRequest {
        /// @notice Sum of all stv locked for withdrawal including this request
        uint256 cumulativeStv;
        /// @notice Sum of all steth shares to rebalance including this request
        uint128 cumulativeStethShares;
        /// @notice Sum of all assets submitted for withdrawals including this request
        uint128 cumulativeAssets;
        /// @notice Address that can claim this request
        address owner;
        /// @notice Timestamp of when the request was created, in seconds
        uint40 timestamp;
        /// @notice True, if request is claimed. Request is claimable if (isFinalized && !isClaimed)
        bool isClaimed;
    }

    /// @notice Structure to store stv rates for finalized requests
    struct Checkpoint {
        /// @notice First requestId that was finalized with these rates
        uint256 fromRequestId;
        /// @notice Stv rate at the moment of finalization (1e27 precision)
        uint256 stvRate;
        /// @notice Steth share rate at the moment of finalization (1e18 precision)
        uint128 stethShareRate;
        /// @notice Gas cost coverage for the requests in this checkpoint
        uint64 gasCostCoverage;
    }

    /// @notice Output format struct for view methods `getWithdrawalStatus()` and `getWithdrawalStatusBatch()`
    struct WithdrawalRequestStatus {
        /// @notice Amount of stv locked for this request
        uint256 amountOfStv;
        /// @notice Amount of steth shares to rebalance for this request
        uint256 amountOfStethShares;
        /// @notice Asset amount that was locked for this request
        uint256 amountOfAssets;
        /// @notice Address that can claim this request
        address owner;
        /// @notice Timestamp of when the request was created, in seconds
        uint256 timestamp;
        /// @notice True, if request is finalized
        bool isFinalized;
        /// @notice True, if request is claimed. Request is claimable if (isFinalized && !isClaimed)
        bool isClaimed;
    }

    /// @custom:storage-location erc7201:pool.storage.WithdrawalQueue
    struct WithdrawalQueueStorage {
        // ### 1st slot
        /// @dev queue for withdrawal requests, indexes (requestId) start from 1
        mapping(uint256 => WithdrawalRequest) requests;
        // ### 2nd slot
        /// @dev withdrawal requests mapped to the owners
        mapping(address => EnumerableSet.UintSet) requestsByOwner;
        // ### 3rd slot
        /// @dev finalization rate history, indexes start from 1
        mapping(uint256 => Checkpoint) checkpoints;
        // ### 4th slot
        /// @dev last index in request queue
        uint128 lastRequestId;
        /// @dev last index of finalized request in the queue
        uint128 lastFinalizedRequestId;
        // ### 5th slot
        /// @dev last index in checkpoints array
        uint96 lastCheckpointIndex;
        /// @dev amount of ETH locked on contract for further claiming
        uint96 totalLockedAssets;
        /// @dev request finalization gas cost coverage in wei
        uint64 gasCostCoverage;
    }

    // keccak256(abi.encode(uint256(keccak256("pool.storage.WithdrawalQueue")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant WITHDRAWAL_QUEUE_STORAGE_LOCATION =
        0x11fba3ff43ee43ae28e3c08029ee00ea5862db2aba88444d8c290c62bd802000;

    function _getWithdrawalQueueStorage() private pure returns (WithdrawalQueueStorage storage $) {
        assembly {
            $.slot := WITHDRAWAL_QUEUE_STORAGE_LOCATION
        }
    }

    event Initialized(address indexed admin, address indexed finalizer);
    event WithdrawalRequested(
        uint256 indexed requestId,
        address indexed owner,
        uint256 amountOfStv,
        uint256 amountOfStethShares,
        uint256 amountOfAssets
    );
    event WithdrawalsFinalized(
        uint256 indexed from,
        uint256 indexed to,
        uint256 ethLocked,
        uint256 ethForGasCoverage,
        uint256 stvBurned,
        uint256 stvRebalanced,
        uint256 stethSharesRebalanced,
        uint256 timestamp
    );
    event WithdrawalClaimed(
        uint256 indexed requestId, address indexed owner, address indexed recipient, uint256 amountOfETH
    );
    event GasCostCoverageSet(uint256 newCoverage);

    error ZeroAddress();
    error RequestValueTooSmall(uint256 amount);
    error RequestAssetsTooLarge(uint256 amount);
    error GasCostCoverageTooLarge(uint256 amount);
    error InvalidWithdrawalDelay();
    error InvalidRequestId(uint256 requestId);
    error InvalidRange(uint256 start, uint256 end);
    error RequestAlreadyClaimed(uint256 requestId);
    error RequestNotFoundOrNotFinalized(uint256 requestId);
    error RequestIdsNotSorted();
    error ArraysLengthMismatch(uint256 firstArrayLength, uint256 secondArrayLength);
    error VaultReportStale();
    error CantSendValueRecipientMayHaveReverted();
    error InvalidHint(uint256 hint);
    error NoRequestsToFinalize();
    error NotOwner(address _requestor, address _owner);
    error RebalancingIsNotSupported();

    constructor(
        address _pool,
        address _dashboard,
        address _vaultHub,
        address _steth,
        address _vault,
        address _lazyOracle,
        uint256 _minWithdrawalDelayTimeInSeconds,
        bool _isRebalancingSupported
    ) {
        if (_minWithdrawalDelayTimeInSeconds < 1 hours) revert InvalidWithdrawalDelay();

        MIN_WITHDRAWAL_DELAY_TIME_IN_SECONDS = _minWithdrawalDelayTimeInSeconds;
        IS_REBALANCING_SUPPORTED = _isRebalancingSupported;

        POOL = IStvStETHPool(payable(_pool));
        DASHBOARD = IDashboard(payable(_dashboard));
        VAULT_HUB = IVaultHub(_vaultHub);
        STETH = IStETH(_steth);
        LAZY_ORACLE = ILazyOracle(_lazyOracle);
        VAULT = IStakingVault(_vault);

        _disableInitializers();

        // Pause features in implementation
        _pauseFeature(WITHDRAWALS_FEATURE);
        _pauseFeature(FINALIZE_FEATURE);
    }

    /**
     * @notice Initialize the contract storage explicitly
     * @param _admin Admin address that can change every role
     * @param _finalizer Address that will be granted FINALIZE_ROLE
     * @param _withdrawalsPauser Address that will be granted WITHDRAWALS_PAUSE_ROLE (zero address for none)
     * @param _finalizePauser Address that will be granted FINALIZE_PAUSE_ROLE (zero address for none)
     * @dev Reverts if `_admin` or `_finalizer` equals to `address(0)`
     */
    function initialize(address _admin, address _finalizer, address _withdrawalsPauser, address _finalizePauser)
        external
        initializer
    {
        if (_admin == address(0)) revert ZeroAddress();
        if (_finalizer == address(0)) revert ZeroAddress();

        __AccessControlEnumerable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(FINALIZE_ROLE, _finalizer);
        if (_withdrawalsPauser != address(0)) {
            _grantRole(WITHDRAWALS_PAUSE_ROLE, _withdrawalsPauser);
        }
        if (_finalizePauser != address(0)) {
            _grantRole(FINALIZE_PAUSE_ROLE, _finalizePauser);
        }

        _getWithdrawalQueueStorage().requests[0] = WithdrawalRequest({
            cumulativeStv: 0,
            cumulativeStethShares: 0,
            cumulativeAssets: 0,
            owner: address(0),
            timestamp: uint40(block.timestamp),
            isClaimed: true
        });

        emit Initialized(_admin, _finalizer);
    }

    // =================================================================================
    // PAUSE / RESUME
    // =================================================================================

    /**
     * @notice Pause withdrawal requests submission
     * @dev Can only be called by accounts with the WITHDRAWALS_PAUSE_ROLE
     * @dev Does not affect claiming of already finalized requests
     */
    function pauseWithdrawals() external {
        _checkRole(WITHDRAWALS_PAUSE_ROLE, msg.sender);
        _pauseFeature(WITHDRAWALS_FEATURE);
    }

    /**
     * @notice Resume withdrawal requests submission
     * @dev Can only be called by accounts with the WITHDRAWALS_RESUME_ROLE
     */
    function resumeWithdrawals() external {
        _checkRole(WITHDRAWALS_RESUME_ROLE, msg.sender);
        _resumeFeature(WITHDRAWALS_FEATURE);
    }

    /**
     * @notice Pause withdrawals finalization
     * @dev Can only be called by accounts with the FINALIZE_PAUSE_ROLE
     * @dev Does not affect claiming of already finalized requests
     */
    function pauseFinalization() external {
        _checkRole(FINALIZE_PAUSE_ROLE, msg.sender);
        _pauseFeature(FINALIZE_FEATURE);
    }

    /**
     * @notice Resume withdrawals finalization
     * @dev Can only be called by accounts with the FINALIZE_RESUME_ROLE
     */
    function resumeFinalization() external {
        _checkRole(FINALIZE_RESUME_ROLE, msg.sender);
        _resumeFeature(FINALIZE_FEATURE);
    }

    // =================================================================================
    // REQUESTS
    // =================================================================================

    /**
     * @notice Request multiple withdrawals from the Pool
     * @param _owner Address that will be able to claim the created request
     * @param _stvToWithdraw Array of amounts of stv to withdraw
     * @param _stethSharesToRebalance Array of amounts of stETH shares to rebalance if supported by the pool, array of 0 otherwise
     * @return requestIds the created withdrawal request ids
     * @dev Transfers stv and liability shares from the requester to the withdrawal queue
     * @dev Requires fresh oracle report to price stv accurately
     */
    function requestWithdrawalBatch(
        address _owner,
        uint256[] calldata _stvToWithdraw,
        uint256[] calldata _stethSharesToRebalance
    ) external returns (uint256[] memory requestIds) {
        _checkFeatureNotPaused(WITHDRAWALS_FEATURE);
        _checkArrayLength(_stvToWithdraw.length, _stethSharesToRebalance.length);
        _checkFreshReport();

        requestIds = new uint256[](_stvToWithdraw.length);
        for (uint256 i = 0; i < _stvToWithdraw.length; ++i) {
            requestIds[i] = _requestWithdrawal(_owner, _stvToWithdraw[i], _stethSharesToRebalance[i]);
        }
    }

    /**
     * @notice Request a withdrawal from the Pool
     * @param _owner Address that will be able to claim the created request
     * @param _stvToWithdraw Amount of stv to withdraw
     * @param _stethSharesToRebalance Amount of steth shares to rebalance if supported by the pool, 0 otherwise
     * @return requestId The created withdrawal request id
     * @dev Transfers stv and liability shares from the requester to the withdrawal queue
     * @dev Requires fresh oracle report to price stv accurately
     */
    function requestWithdrawal(address _owner, uint256 _stvToWithdraw, uint256 _stethSharesToRebalance)
        external
        returns (uint256 requestId)
    {
        _checkFeatureNotPaused(WITHDRAWALS_FEATURE);
        _checkFreshReport();

        requestId = _requestWithdrawal(_owner, _stvToWithdraw, _stethSharesToRebalance);
    }

    function _requestWithdrawal(address _owner, uint256 _stvToWithdraw, uint256 _stethSharesToRebalance)
        internal
        returns (uint256 requestId)
    {
        if (_owner == address(0)) revert ZeroAddress();
        if (_stethSharesToRebalance > 0 && !IS_REBALANCING_SUPPORTED) revert RebalancingIsNotSupported();

        uint256 assets = POOL.previewRedeem(_stvToWithdraw);
        uint256 value = _stethSharesToRebalance > 0
            ? Math.saturatingSub(assets, _getPooledEthBySharesRoundUp(_stethSharesToRebalance))
            : assets;

        if (value < MIN_WITHDRAWAL_VALUE) revert RequestValueTooSmall(value);
        if (assets > MAX_WITHDRAWAL_ASSETS) revert RequestAssetsTooLarge(assets);

        WithdrawalQueueStorage storage $ = _getWithdrawalQueueStorage();

        uint256 lastRequestId = $.lastRequestId;
        WithdrawalRequest memory lastRequest = $.requests[lastRequestId];

        requestId = lastRequestId + 1;
        $.lastRequestId = requestId.toUint128();

        uint256 cumulativeStv = lastRequest.cumulativeStv + _stvToWithdraw;
        uint256 cumulativeStethShares = lastRequest.cumulativeStethShares + _stethSharesToRebalance;
        uint256 cumulativeAssets = lastRequest.cumulativeAssets + assets;

        $.requests[requestId] = WithdrawalRequest({
            cumulativeStv: cumulativeStv,
            cumulativeStethShares: cumulativeStethShares.toUint128(),
            cumulativeAssets: cumulativeAssets.toUint128(),
            owner: _owner,
            timestamp: uint40(block.timestamp),
            isClaimed: false
        });

        assert($.requestsByOwner[_owner].add(requestId));

        _transferForWithdrawalQueue(msg.sender, _stvToWithdraw, _stethSharesToRebalance);

        emit WithdrawalRequested(requestId, _owner, _stvToWithdraw, _stethSharesToRebalance, assets);
    }

    function _transferForWithdrawalQueue(address _from, uint256 _stv, uint256 _stethShares) internal {
        if (_stethShares == 0) {
            POOL.transferFromForWithdrawalQueue(_from, _stv);
        } else {
            POOL.transferFromWithLiabilityForWithdrawalQueue(_from, _stv, _stethShares);
        }
    }

    function _getPooledEthBySharesRoundUp(uint256 _stethShares) internal view returns (uint256 ethAmount) {
        ethAmount = STETH.getPooledEthBySharesRoundUp(_stethShares);
    }

    // =================================================================================
    // GAS COST COVERAGE
    // =================================================================================

    /**
     * @notice Set the gas cost coverage that applies to each request during finalization
     * @param _coverage The gas cost coverage per request in wei
     * @dev Reverts if `_coverage` is greater than `MAX_GAS_COST_COVERAGE`
     * @dev 0 by default. Increasing coverage discourages malicious actors from creating
     * excessive requests while compensating finalizers for gas expenses
     */
    function setFinalizationGasCostCoverage(uint256 _coverage) external {
        _checkRole(FINALIZE_ROLE, msg.sender);

        _setFinalizationGasCostCoverage(_coverage);
    }

    function _setFinalizationGasCostCoverage(uint256 _coverage) internal {
        if (_coverage > MAX_GAS_COST_COVERAGE) revert GasCostCoverageTooLarge(_coverage);

        _getWithdrawalQueueStorage().gasCostCoverage = _coverage.toUint64();
        emit GasCostCoverageSet(_coverage);
    }

    /**
     * @notice Get the current gas cost coverage that applies to each request during finalization
     * @return coverage The gas cost coverage per request in wei
     */
    function getFinalizationGasCostCoverage() external view returns (uint256 coverage) {
        coverage = _getWithdrawalQueueStorage().gasCostCoverage;
    }

    // =================================================================================
    // FINALIZATION
    // =================================================================================

    /**
     * @notice Receive ETH for claims
     */
    receive() external payable {}

    /**
     * @notice Finalize withdrawal requests
     * @param _maxRequests The maximum number of requests to finalize
     * @param _gasCostCoverageRecipient The address to receive gas cost coverage
     * @return finalizedRequests The number of requests that were finalized
     * @dev Reverts if there are no requests to finalize
     */
    function finalize(uint256 _maxRequests, address _gasCostCoverageRecipient)
        external
        returns (uint256 finalizedRequests)
    {
        _checkFeatureNotPaused(FINALIZE_FEATURE);
        _checkRole(FINALIZE_ROLE, msg.sender);
        _checkFreshReport();

        WithdrawalQueueStorage storage $ = _getWithdrawalQueueStorage();

        uint256 lastFinalizedRequestId = $.lastFinalizedRequestId;
        uint256 firstRequestIdToFinalize = lastFinalizedRequestId + 1;
        uint256 lastRequestIdToFinalize = Math.min(lastFinalizedRequestId + _maxRequests, $.lastRequestId);

        if (firstRequestIdToFinalize > lastRequestIdToFinalize) revert NoRequestsToFinalize();

        // Collect necessary data for finalization
        uint256 currentStvRate = calculateCurrentStvRate();
        uint256 currentStethShareRate = calculateCurrentStethShareRate();
        uint256 withdrawableValue = DASHBOARD.withdrawableValue();
        uint256 availableBalance = VAULT.availableBalance();
        uint256 exceedingSteth = _getExceedingMintedSteth();
        uint256 latestReportTimestamp = LAZY_ORACLE.latestReportTimestamp();

        uint256 totalStvToBurn;
        uint256 totalStethShares;
        uint256 totalEthToClaim;
        uint256 totalGasCoverage;
        uint256 maxStvToRebalance;

        Checkpoint memory checkpoint = Checkpoint({
            fromRequestId: firstRequestIdToFinalize,
            stvRate: currentStvRate,
            stethShareRate: currentStethShareRate.toUint128(),
            gasCostCoverage: $.gasCostCoverage
        });

        // Finalize requests one by one until conditions are met
        for (uint256 i = firstRequestIdToFinalize; i <= lastRequestIdToFinalize; ++i) {
            WithdrawalRequest memory currRequest = $.requests[i];
            WithdrawalRequest memory prevRequest = $.requests[i - 1];

            // Calculate amounts for the request
            // - stv: amount of stv requested to withdraw
            // - ethToClaim: amount of ETH that can be claimed for this request, excluding rebalancing and fees
            // - stethSharesToRebalance: amount of steth shares to rebalance for this request
            // - stethToRebalance: amount of steth corresponding to stethSharesToRebalance at the current rate
            // - gasCostCoverage: amount of ETH that should be subtracted as gas cost coverage for this request
            (
                uint256 stv,
                uint256 ethToClaim,
                uint256 stethSharesToRebalance,
                uint256 stethToRebalance,
                uint256 gasCostCoverage
            ) = _calcRequestAmounts(prevRequest, currRequest, checkpoint);

            // Handle rebalancing if applicable
            uint256 ethToRebalance;
            uint256 stvToRebalance;

            if (stethToRebalance > 0) {
                // Determine how much stv should be burned in exchange for the steth shares
                stvToRebalance = Math.mulDiv(stethToRebalance, E36_PRECISION_BASE, currentStvRate, Math.Rounding.Ceil);

                // Cap stvToRebalance to requested stv. The rest (if any) will be socialized to users
                // When creating a request, user transfers stv and liability to the withdrawal queue with the necessary reserve
                // However, while waiting for finalization in the withdrawal queue, the position may become undercollateralized
                // In this case, the loss is shared among all participants
                if (stvToRebalance > stv) stvToRebalance = stv;

                // Exceeding minted stETH (if any) is used to cover rebalancing need without withdrawing ETH from the vault
                // Thus, Exceeding minted stETH aims to be reduced to 0
                if (exceedingSteth > stethToRebalance) {
                    exceedingSteth -= stethToRebalance;
                } else {
                    ethToRebalance = stethToRebalance - exceedingSteth;
                    exceedingSteth = 0;
                }
            }

            if (
                // Stop if insufficient withdrawable ETH to cover claimable ETH for this request
                // Stop if insufficient available ETH to cover claimable and rebalancable ETH for this request
                // Stop if not enough time has passed since the request was created
                // Stop if the request was created after the latest report was published, at least one oracle report is required
                (ethToClaim + gasCostCoverage) > withdrawableValue
                    || (ethToClaim + ethToRebalance + gasCostCoverage) > availableBalance
                    || currRequest.timestamp + MIN_WITHDRAWAL_DELAY_TIME_IN_SECONDS > block.timestamp
                    || currRequest.timestamp > latestReportTimestamp
            ) {
                break;
            }

            withdrawableValue -= (ethToClaim + gasCostCoverage);
            availableBalance -= (ethToClaim + gasCostCoverage + ethToRebalance);
            totalEthToClaim += ethToClaim;
            totalGasCoverage += gasCostCoverage;
            totalStvToBurn += (stv - stvToRebalance);
            totalStethShares += stethSharesToRebalance;
            maxStvToRebalance += stvToRebalance;
            finalizedRequests++;
        }

        if (finalizedRequests == 0) revert NoRequestsToFinalize();

        // 1. Withdraw ETH from the vault to cover finalized requests and burn associated stv
        // Eth to claim or stv to burn could be 0 if all requests are going to be rebalanced
        // Rebalance cannot be done first because it will withdraw eth without unlocking it
        uint256 totalEthToWithdraw = totalEthToClaim + totalGasCoverage;
        if (totalEthToWithdraw > 0) {
            uint256 balanceBefore = address(this).balance;
            DASHBOARD.withdraw(address(this), totalEthToWithdraw);
            assert(address(this).balance - balanceBefore == totalEthToWithdraw);
        }
        if (totalStvToBurn > 0) POOL.burnStvForWithdrawalQueue(totalStvToBurn);

        // 2. Rebalance steth shares by burning corresponding amount stv. Or socialize the losses if not enough stv
        // At this point stv rate may change because of the operation above
        // So it may burn less stv than maxStvToRebalance because of new stv rate
        uint256 totalStvRebalanced;
        if (totalStethShares > 0) {
            assert(IS_REBALANCING_SUPPORTED);

            // Stv burning is limited at this point by maxStvToRebalance calculated above
            // to make sure that only stv of finalized requests is used for rebalancing
            totalStvRebalanced = POOL.rebalanceMintedStethSharesForWithdrawalQueue(totalStethShares, maxStvToRebalance);
        }

        // 3. Burn any remaining stv that was not used for rebalancing
        // The rebalancing may burn less stv than maxStvToRebalance because of:
        //   - the changed stv rate after the first step
        //   - accumulated rounding errors in maxStvToRebalance
        //
        // It's guaranteed by POOL.rebalanceMintedStethSharesForWithdrawalQueue() that maxStvToRebalance >= totalStvRebalanced
        uint256 remainingStvForRebalance = maxStvToRebalance - totalStvRebalanced;
        if (remainingStvForRebalance > 0) {
            POOL.burnStvForWithdrawalQueue(remainingStvForRebalance);
            totalStvToBurn += remainingStvForRebalance;
        }

        lastFinalizedRequestId = lastFinalizedRequestId + finalizedRequests;

        // Store checkpoint with current stvRate, stethShareRate and gasCostCoverage
        uint96 lastCheckpointIndex = $.lastCheckpointIndex + 1;
        $.checkpoints[lastCheckpointIndex] = checkpoint;
        $.lastCheckpointIndex = lastCheckpointIndex;

        $.lastFinalizedRequestId = lastFinalizedRequestId.toUint128();
        $.totalLockedAssets += totalEthToClaim.toUint96();

        // Send gas coverage to the caller
        if (totalGasCoverage > 0) {
            // Set gas cost coverage recipient to msg.sender if not specified
            if (_gasCostCoverageRecipient == address(0)) _gasCostCoverageRecipient = msg.sender;

            (bool success,) = _gasCostCoverageRecipient.call{value: totalGasCoverage}("");
            if (!success) revert CantSendValueRecipientMayHaveReverted();
        }

        emit WithdrawalsFinalized(
            firstRequestIdToFinalize,
            lastFinalizedRequestId,
            totalEthToClaim,
            totalGasCoverage,
            totalStvToBurn,
            totalStvRebalanced,
            totalStethShares,
            block.timestamp
        );
    }

    function _getExceedingMintedSteth() internal view returns (uint256 exceedingMintedSteth) {
        if (IS_REBALANCING_SUPPORTED) {
            exceedingMintedSteth = POOL.totalExceedingMintedSteth();
        } else {
            exceedingMintedSteth = 0;
        }
    }

    // =================================================================================
    // STV & STETH RATES
    // =================================================================================

    /**
     * @notice Calculate current stv rate of the vault
     * @return stvRate Current stv rate of the vault (1e27 precision)
     */
    function calculateCurrentStvRate() public view returns (uint256 stvRate) {
        uint256 totalStv = POOL.totalSupply(); // 1e27 precision
        uint256 totalAssets = POOL.totalAssets(); // 1e18 precision

        if (totalStv == 0) return E27_PRECISION_BASE;
        stvRate = (totalAssets * E36_PRECISION_BASE) / totalStv;
    }

    /**
     * @notice Calculate current stETH share rate
     * @return stethShareRate ETH amount (1e18 precision) per 1e27 stETH shares
     * @dev Returns the amount of ETH (in wei) that corresponds to 1e27 stETH shares at the current exchange rate
     */
    function calculateCurrentStethShareRate() public view returns (uint256 stethShareRate) {
        stethShareRate = _getPooledEthBySharesRoundUp(E27_PRECISION_BASE);
    }

    // =================================================================================
    // CLAIMING
    // =================================================================================

    /**
     * @notice Claim a batch of withdrawal requests once finalized sending locked ether to the recipient
     * @param _recipient Address where claimed ether will be sent to
     * @param _requestIds Array of request ids to claim
     * @param _hints Checkpoint hints. can be found with `findCheckpointHintBatch(_requestIds, 1, getLastCheckpointIndex())`
     * @return claimedAmounts Array of claimed amounts for each request
     */
    function claimWithdrawalBatch(address _recipient, uint256[] calldata _requestIds, uint256[] calldata _hints)
        external
        returns (uint256[] memory claimedAmounts)
    {
        _checkArrayLength(_requestIds.length, _hints.length);

        claimedAmounts = new uint256[](_requestIds.length);
        for (uint256 i = 0; i < _requestIds.length; ++i) {
            claimedAmounts[i] = _claim(msg.sender, _recipient, _requestIds[i], _hints[i]);
        }
    }

    /**
     * @notice Claim one `_requestId` request once finalized sending locked ether to the recipient
     * @param _recipient Address where claimed ether will be sent to
     * @param _requestId Request id to claim
     * @dev
     *  Reverts if requestId is not valid
     *  Reverts if request is not finalized or already claimed
     *  Reverts if msg sender is not an owner of request
     */
    function claimWithdrawal(address _recipient, uint256 _requestId) external returns (uint256 claimedEth) {
        uint256 checkpoint = findCheckpointHint(_requestId, 1, getLastCheckpointIndex());
        claimedEth = _claim(msg.sender, _recipient, _requestId, checkpoint);
    }

    function _claim(address _requestor, address _recipient, uint256 _requestId, uint256 _hint)
        internal
        returns (uint256 ethWithDiscount)
    {
        if (_recipient == address(0)) revert ZeroAddress();
        if (_requestId == 0) revert InvalidRequestId(_requestId);

        WithdrawalQueueStorage storage $ = _getWithdrawalQueueStorage();
        if (_requestId > $.lastFinalizedRequestId) revert RequestNotFoundOrNotFinalized(_requestId);

        WithdrawalRequest storage request = $.requests[_requestId];

        if (request.isClaimed) revert RequestAlreadyClaimed(_requestId);
        if (request.owner != _requestor) revert NotOwner(_requestor, request.owner);

        request.isClaimed = true;
        assert($.requestsByOwner[request.owner].remove(_requestId));

        ethWithDiscount = _calcClaimableEther(request, _requestId, _hint);
        // Because of the rounding issue some dust could be accumulated upon claiming on the contract
        $.totalLockedAssets -= ethWithDiscount.toUint96();

        (bool success,) = _recipient.call{value: ethWithDiscount}("");
        if (!success) revert CantSendValueRecipientMayHaveReverted();

        emit WithdrawalClaimed(_requestId, _requestor, _recipient, ethWithDiscount);
    }

    // =================================================================================
    // CHECKPOINTS
    // =================================================================================

    /**
     * @notice Finds the list of hints for the given `_requestIds` searching among the checkpoints with indices
     *  in the range  `[_firstIndex, _lastIndex]`.
     *  NB! Array of request ids should be sorted
     *  NB! `_firstIndex` should be greater than 0, because checkpoint list is 1-based array
     *  Usage: findCheckpointHintBatch(_requestIds, 1, getLastCheckpointIndex())
     * @param _requestIds Ids of the requests sorted in the ascending order to get hints for
     * @param _firstIndex Left boundary of the search range. Should be greater than 0
     * @param _lastIndex Right boundary of the search range. Should be less than or equal to getLastCheckpointIndex()
     * @return hintIds Array of hints used to find required checkpoint for the request
     */
    function findCheckpointHintBatch(uint256[] calldata _requestIds, uint256 _firstIndex, uint256 _lastIndex)
        external
        view
        returns (uint256[] memory hintIds)
    {
        hintIds = new uint256[](_requestIds.length);
        uint256 prevRequestId = 0;
        for (uint256 i = 0; i < _requestIds.length; ++i) {
            if (_requestIds[i] < prevRequestId) revert RequestIdsNotSorted();
            hintIds[i] = findCheckpointHint(_requestIds[i], _firstIndex, _lastIndex);
            if (hintIds[i] != NOT_FOUND) _firstIndex = hintIds[i];
            prevRequestId = _requestIds[i];
        }
    }

    /**
     * @notice View function to find a checkpoint hint to use in `claimWithdrawal()`, claimWithdrawalBatch()`, `getClaimableEther()`, and `getClaimableEtherBatch()`
     * Search will be performed in the range of `[_firstIndex, _lastIndex]`
     * @param _requestId Request id to search the checkpoint for
     * @param _start Index of the left boundary of the search range, should be greater than 0
     * @param _end Index of the right boundary of the search range, should be less than or equal to `getLastCheckpointIndex()`
     * @return hint for later use in other methods or 0 if hint not found in the range
     */
    function findCheckpointHint(uint256 _requestId, uint256 _start, uint256 _end) public view returns (uint256) {
        WithdrawalQueueStorage storage $ = _getWithdrawalQueueStorage();
        if (_requestId == 0 || _requestId > $.lastRequestId) revert InvalidRequestId(_requestId);

        uint256 lastCheckpointIndex_ = $.lastCheckpointIndex;
        if (_start == 0 || _end > lastCheckpointIndex_) revert InvalidRange(_start, _end);

        if (lastCheckpointIndex_ == 0 || _requestId > $.lastFinalizedRequestId || _start > _end) return NOT_FOUND;

        // Right boundary
        if (_requestId >= $.checkpoints[_end].fromRequestId) {
            // it's the last checkpoint, so it's valid
            if (_end == lastCheckpointIndex_) return _end;
            // it fits right before the next checkpoint
            if (_requestId < $.checkpoints[_end + 1].fromRequestId) return _end;

            return NOT_FOUND;
        }
        // Left boundary
        if (_requestId < $.checkpoints[_start].fromRequestId) {
            return NOT_FOUND;
        }

        // Binary search
        uint256 min = _start;
        uint256 max = _end - 1;

        while (max > min) {
            uint256 mid = (max + min + 1) / 2;
            if ($.checkpoints[mid].fromRequestId <= _requestId) {
                min = mid;
            } else {
                max = mid - 1;
            }
        }
        return min;
    }

    /**
     * @notice Returns the last checkpoint index
     * @return index Last checkpoint index
     */
    function getLastCheckpointIndex() public view returns (uint256 index) {
        index = _getWithdrawalQueueStorage().lastCheckpointIndex;
    }

    // =================================================================================
    // REQUESTS BY OWNER
    // =================================================================================

    /**
     * @notice Returns all withdrawal requests that belong to the `_owner` address
     * @param _owner Address to get requests for
     * @return requestIds Array of request ids
     *
     * WARNING: This operation will copy the entire storage to memory, which can be quite expensive. This is designed
     * to mostly be used by view accessors that are queried without any gas fees. Developers should keep in mind that
     * this function has an unbounded cost, and using it as part of a state-changing function may render the function
     * uncallable if the set grows to a point where copying to memory consumes too much gas to fit in a block.
     */
    function withdrawalRequestsOf(address _owner) external view returns (uint256[] memory requestIds) {
        requestIds = _getWithdrawalQueueStorage().requestsByOwner[_owner].values();
    }

    /**
     * @notice Returns withdrawal requests in range that belong to the `_owner` address
     * @param _owner Address to get requests for
     * @param _start Start index
     * @param _end End index
     * @return requestIds Array of request ids
     *
     * WARNING: This operation will copy the entire storage to memory, which can be quite expensive. This is designed
     * to mostly be used by view accessors that are queried without any gas fees. Developers should keep in mind that
     * this function has an unbounded cost, and using it as part of a state-changing function may render the function
     * uncallable if the set grows to a point where copying to memory consumes too much gas to fit in a block.
     */
    function withdrawalRequestsInRangeOf(address _owner, uint256 _start, uint256 _end)
        external
        view
        returns (uint256[] memory requestIds)
    {
        requestIds = _getWithdrawalQueueStorage().requestsByOwner[_owner].values(_start, _end);
    }

    /**
     * @notice Returns the length of the withdrawal requests that belong to the `_owner` address
     * @param _owner Address to get requests for
     * @return length Length of the requests array
     */
    function withdrawalRequestsLengthOf(address _owner) external view returns (uint256 length) {
        length = _getWithdrawalQueueStorage().requestsByOwner[_owner].length();
    }

    // =================================================================================
    // REQUEST STATUS
    // =================================================================================

    /**
     * @notice Returns status for requests with provided ids
     * @param _requestIds Array of withdrawal request ids
     * @return statuses Array of withdrawal request statuses
     */
    function getWithdrawalStatusBatch(uint256[] calldata _requestIds)
        external
        view
        returns (WithdrawalRequestStatus[] memory statuses)
    {
        statuses = new WithdrawalRequestStatus[](_requestIds.length);
        for (uint256 i = 0; i < _requestIds.length; ++i) {
            statuses[i] = _getStatus(_requestIds[i]);
        }
    }

    /**
     * @notice Returns status for a single request
     * @param _requestId Request id to get status for
     * @return status Withdrawal request status
     */
    function getWithdrawalStatus(uint256 _requestId) external view returns (WithdrawalRequestStatus memory status) {
        status = _getStatus(_requestId);
    }

    function _getStatus(uint256 _requestId) internal view returns (WithdrawalRequestStatus memory requestStatus) {
        WithdrawalQueueStorage storage $ = _getWithdrawalQueueStorage();
        if (_requestId == 0 || _requestId > $.lastRequestId) revert InvalidRequestId(_requestId);

        WithdrawalRequest storage request = $.requests[_requestId];
        WithdrawalRequest storage previousRequest = $.requests[_requestId - 1];

        requestStatus = WithdrawalRequestStatus({
            amountOfStv: request.cumulativeStv - previousRequest.cumulativeStv,
            amountOfStethShares: request.cumulativeStethShares - previousRequest.cumulativeStethShares,
            amountOfAssets: request.cumulativeAssets - previousRequest.cumulativeAssets,
            owner: request.owner,
            timestamp: request.timestamp,
            isFinalized: _requestId <= $.lastFinalizedRequestId,
            isClaimed: request.isClaimed
        });
    }

    // =================================================================================
    // CLAIMABLE ETHER
    // =================================================================================

    /**
     * @notice Returns amount of ether available for claim for each provided request id
     * @param _requestIds Array of request ids to get claimable ether for
     * @param _hints Checkpoint hints. Can be found with `findCheckpointHintBatch(_requestIds, 1, getLastCheckpointIndex())`
     * @return claimableEthValues Amount of claimable ether for each request, amount is equal to 0 if request
     * is not finalized or already claimed
     */
    function getClaimableEtherBatch(uint256[] calldata _requestIds, uint256[] calldata _hints)
        external
        view
        returns (uint256[] memory claimableEthValues)
    {
        _checkArrayLength(_requestIds.length, _hints.length);

        claimableEthValues = new uint256[](_requestIds.length);
        for (uint256 i = 0; i < _requestIds.length; ++i) {
            claimableEthValues[i] = _getClaimableEther(_requestIds[i], _hints[i]);
        }
    }

    /**
     * @notice Returns the claimable ether for a request
     * @param _requestId Request id to get claimable ether for
     * @return claimableEth Amount of claimable ether, amount is equal to 0 if request is not finalized or already claimed
     */
    function getClaimableEther(uint256 _requestId) external view returns (uint256 claimableEth) {
        uint256 checkpoint = findCheckpointHint(_requestId, 1, getLastCheckpointIndex());
        claimableEth = _getClaimableEther(_requestId, checkpoint);
    }

    function _getClaimableEther(uint256 _requestId, uint256 _hint) internal view returns (uint256 claimableEth) {
        WithdrawalQueueStorage storage $ = _getWithdrawalQueueStorage();
        if (_requestId == 0 || _requestId > $.lastRequestId) return 0;
        if (_requestId > $.lastFinalizedRequestId) return 0;

        WithdrawalRequest storage request = $.requests[_requestId];
        if (request.isClaimed) return 0;

        claimableEth = _calcClaimableEther(request, _requestId, _hint);
    }

    function _calcClaimableEther(WithdrawalRequest storage _request, uint256 _requestId, uint256 _hint)
        internal
        view
        returns (uint256 claimableEth)
    {
        if (_hint == 0) revert InvalidHint(_hint);

        WithdrawalQueueStorage storage $ = _getWithdrawalQueueStorage();

        uint256 lastCheckpointIndex_ = $.lastCheckpointIndex;
        if (_hint > lastCheckpointIndex_) revert InvalidHint(_hint);

        Checkpoint memory checkpoint = $.checkpoints[_hint];
        // Reverts if requestId is not in range [checkpoint[hint], checkpoint[hint+1])
        // ______(>______
        //    ^  hint
        if (_requestId < checkpoint.fromRequestId) revert InvalidHint(_hint);
        if (_hint < lastCheckpointIndex_) {
            // ______(>______(>________
            //       hint    hint+1  ^
            Checkpoint memory nextCheckpoint = $.checkpoints[_hint + 1];
            if (nextCheckpoint.fromRequestId <= _requestId) revert InvalidHint(_hint);
        }

        WithdrawalRequest memory prevRequest = $.requests[_requestId - 1];
        (, claimableEth,,,) = _calcRequestAmounts(prevRequest, _request, checkpoint);
    }

    function _calcRequestAmounts(
        WithdrawalRequest memory _prevRequest,
        WithdrawalRequest memory _request,
        Checkpoint memory _checkpoint
    )
        internal
        pure
        returns (
            uint256 stv,
            uint256 assetsToClaim,
            uint256 stethSharesToRebalance,
            uint256 assetsToRebalance,
            uint256 gasCostCoverage
        )
    {
        stv = _request.cumulativeStv - _prevRequest.cumulativeStv;
        stethSharesToRebalance = _request.cumulativeStethShares - _prevRequest.cumulativeStethShares;
        assetsToClaim = _request.cumulativeAssets - _prevRequest.cumulativeAssets;

        // Calculate stv rate at the time of request creation
        uint256 requestStvRate = (assetsToClaim * E36_PRECISION_BASE) / stv;

        // Apply discount if the request stv rate is above the finalization stv rate
        if (requestStvRate > _checkpoint.stvRate) {
            assetsToClaim = Math.mulDiv(stv, _checkpoint.stvRate, E36_PRECISION_BASE, Math.Rounding.Floor);
        }

        if (stethSharesToRebalance > 0) {
            assetsToRebalance =
                Math.mulDiv(stethSharesToRebalance, _checkpoint.stethShareRate, E27_PRECISION_BASE, Math.Rounding.Ceil);

            // Decrease assets to claim by the amount of assets to rebalance
            assetsToClaim = Math.saturatingSub(assetsToClaim, assetsToRebalance);
        }

        // Apply request finalization gas cost coverage
        if (_checkpoint.gasCostCoverage > 0) {
            gasCostCoverage = Math.min(assetsToClaim, _checkpoint.gasCostCoverage);
            assetsToClaim -= gasCostCoverage;
        }
    }

    // =================================================================================
    // UNFINALIZED
    // =================================================================================

    /**
     * @notice Return the number of unfinalized requests in the queue
     * @return requestsNumber Number of unfinalized requests
     */
    function unfinalizedRequestsNumber() external view returns (uint256 requestsNumber) {
        WithdrawalQueueStorage storage $ = _getWithdrawalQueueStorage();
        requestsNumber = $.lastRequestId - $.lastFinalizedRequestId;
    }

    /**
     * @notice Returns the amount of stv in the queue yet to be finalized
     * @return stv Amount of stv yet to be finalized
     */
    function unfinalizedStv() external view returns (uint256 stv) {
        WithdrawalQueueStorage storage $ = _getWithdrawalQueueStorage();
        stv = $.requests[$.lastRequestId].cumulativeStv - $.requests[$.lastFinalizedRequestId].cumulativeStv;
    }

    /**
     * @notice Returns the amount of stethShares in the queue yet to be rebalanced
     * @return stethShares Amount of stethShares yet to be rebalanced
     */
    function unfinalizedStethShares() external view returns (uint256 stethShares) {
        WithdrawalQueueStorage storage $ = _getWithdrawalQueueStorage();
        stethShares = $.requests[$.lastRequestId].cumulativeStethShares
            - $.requests[$.lastFinalizedRequestId].cumulativeStethShares;
    }

    /**
     * @notice Returns the amount of assets in the queue yet to be finalized
     * @dev NOTE: This returns the nominal amount. Actual ETH needed may be less due to discounts
     * @return assets Amount of assets yet to be finalized
     */
    function unfinalizedAssets() external view returns (uint256 assets) {
        WithdrawalQueueStorage storage $ = _getWithdrawalQueueStorage();
        assets = $.requests[$.lastRequestId].cumulativeAssets - $.requests[$.lastFinalizedRequestId].cumulativeAssets;
    }

    // =================================================================================
    // REQUEST IDS
    // =================================================================================

    /**
     * @notice Returns the last request id
     * @return requestId Last request id
     */
    function getLastRequestId() external view returns (uint256 requestId) {
        requestId = _getWithdrawalQueueStorage().lastRequestId;
    }

    /**
     * @notice Returns the last finalized request id
     * @return requestId Last finalized request id
     */
    function getLastFinalizedRequestId() external view returns (uint256 requestId) {
        requestId = _getWithdrawalQueueStorage().lastFinalizedRequestId;
    }

    // =================================================================================
    // CHECKS
    // =================================================================================

    function _checkArrayLength(uint256 _firstArrayLength, uint256 _secondArrayLength) internal pure {
        if (_firstArrayLength != _secondArrayLength) {
            revert ArraysLengthMismatch(_firstArrayLength, _secondArrayLength);
        }
    }

    function _checkFreshReport() internal view {
        if (!VAULT_HUB.isReportFresh(address(VAULT))) revert VaultReportStale();
    }
}
