// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardTransient} from "solady/utils/ReentrancyGuardTransient.sol";

import {Campaign} from "./Campaign.sol";
import {CampaignHooks} from "./CampaignHooks.sol";
import {Constants} from "./Constants.sol";

/// @title Flywheel
///
/// @notice Protocol entrypoint for creating and managing campaigns for token payouts
///
/// @author Coinbase (https://github.com/base/flywheel)
contract Flywheel is ReentrancyGuardTransient {
    /// @notice Possible states a campaign can be in
    enum CampaignStatus {
        /// @dev Campaign is not yet live, default on creation
        INACTIVE,
        /// @dev Campaign is live and can process payouts
        ACTIVE,
        /// @dev Campaign is no longer live but can still process lagging payouts, can only update status to finalized
        FINALIZING,
        /// @dev Campaign is no longer live and no more payouts can be processed, cannot update status
        FINALIZED
    }

    /// @notice Stored campaign information
    struct CampaignInfo {
        /// @dev Current status of the campaign
        CampaignStatus status;
        /// @dev Address of the campaign hooks contract
        CampaignHooks hooks;
    }

    /// @notice Payout to send to a recipient
    struct Payout {
        /// @dev Address receiving the payout
        address recipient;
        /// @dev Amount of tokens to be paid out
        uint256 amount;
        /// @dev Extra data for the payout to attach in events
        bytes extraData;
    }

    /// @notice Allocation to commit to for future distribution
    struct Allocation {
        /// @dev Key for the allocation
        bytes32 key;
        /// @dev Amount of tokens to be paid out
        uint256 amount;
        /// @dev Extra data to attach in events
        bytes extraData;
    }

    /// @notice Distribution to send to a recipient from a previous allocation
    struct Distribution {
        /// @dev Address receiving the distribution
        address recipient;
        /// @dev Key for the allocation
        bytes32 key;
        /// @dev Amount of tokens to be distributed
        uint256 amount;
        /// @dev Extra data to attach in events
        bytes extraData;
    }

    /// @notice Implementation for Campaign contracts
    address public immutable CAMPAIGN_IMPLEMENTATION;

    ////////////////////////////////////////////////////////////////
    ///                         Storage                          ///
    ////////////////////////////////////////////////////////////////

    /// @notice Allocated payouts that are pending distribution
    mapping(address campaign => mapping(address token => mapping(bytes32 key => uint256 amount))) public
        allocatedPayout;

    /// @notice Allocated fees that are pending collection
    mapping(address campaign => mapping(address token => mapping(bytes32 key => uint256 amount))) public allocatedFee;

    /// @notice Total funds reserved for a campaign's payouts
    mapping(address campaign => mapping(address token => uint256 amount)) public totalAllocatedPayouts;

    /// @notice Total funds reserved for a campaign's fees
    mapping(address campaign => mapping(address token => uint256 amount)) public totalAllocatedFees;

    /// @notice Stored campaign information
    mapping(address campaign => CampaignInfo) internal _campaigns;

    ////////////////////////////////////////////////////////////////
    ///                          Events                          ///
    ////////////////////////////////////////////////////////////////

    /// @notice Emitted when a new campaign is created
    ///
    /// @param campaign Address of the created campaign
    /// @param hooks Address of the campaign hooks contract
    event CampaignCreated(address indexed campaign, address hooks);

    /// @notice Emitted when a payout is sent to a recipient
    ///
    /// @param campaign Address of the campaign
    /// @param token Address of the payout token
    /// @param recipient Address receiving the payout
    /// @param amount Amount of tokens sent
    /// @param extraData Extra data for the payout to attach in events
    event PayoutSent(address indexed campaign, address token, address recipient, uint256 amount, bytes extraData);

    /// @notice Emitted when a payout is allocated to a recipient
    ///
    /// @param campaign Address of the campaign
    /// @param token Address of the payout token
    /// @param key Key for the allocation
    /// @param amount Amount of tokens allocated
    /// @param extraData Extra data for the payout to attach in events
    event PayoutAllocated(address indexed campaign, address token, bytes32 key, uint256 amount, bytes extraData);

    /// @notice Emitted when allocated payouts are deallocated from a recipient
    ///
    /// @param campaign Address of the campaign
    /// @param token Address of the payout token
    /// @param key Key for the allocation
    /// @param amount Amount of tokens deallocated
    /// @param extraData Extra data for the payout to attach in events
    event PayoutDeallocated(address indexed campaign, address token, bytes32 key, uint256 amount, bytes extraData);

    /// @notice Emitted when allocated payouts are distributed to a recipient
    ///
    /// @param campaign Address of the campaign
    /// @param token Address of the payout token
    /// @param key Key for the allocation
    /// @param recipient Address receiving the distribution
    /// @param amount Amount of tokens distributed
    /// @param extraData Extra data for the payout to attach in events
    event PayoutDistributed(
        address indexed campaign, address token, bytes32 key, address recipient, uint256 amount, bytes extraData
    );

    /// @notice Emitted when a fee is sent to a recipient
    ///
    /// @param campaign Address of the campaign
    /// @param token Address of the payout token
    /// @param recipient Address receiving the fee
    /// @param amount Amount of tokens sent
    /// @param extraData Extra data for the fee to attach in events
    event FeeSent(address indexed campaign, address token, address recipient, uint256 amount, bytes extraData);

    /// @notice Emitted when a fee is allocated to a recipient
    ///
    /// @param campaign Address of the campaign
    /// @param token Address of the payout token
    /// @param key Key for the fees
    /// @param amount Amount of tokens allocated
    /// @param extraData Extra data for the payout to attach in events
    event FeeAllocated(address indexed campaign, address token, bytes32 key, uint256 amount, bytes extraData);

    /// @notice Emitted when accumulated fees are distributed
    ///
    /// @param campaign Address of the campaign
    /// @param token Address of the distributed token
    /// @param key Key for the fees
    /// @param recipient Address receiving the distributed fees
    /// @param amount Amount of tokens distributed
    /// @param extraData Extra data for the payout to attach in events
    event FeeDistributed(
        address indexed campaign, address token, bytes32 key, address recipient, uint256 amount, bytes extraData
    );

    /// @notice Emitted when a fee transfer fails
    ///
    /// @dev Applies to both attempted sends and distributions of fees
    ///
    /// @param campaign Address of the campaign
    /// @param token Address of the token that failed to transfer
    /// @param key Key for the fees
    /// @param recipient Address receiving the fees
    /// @param amount Amount of tokens that failed to transfer
    /// @param extraData Extra data for the payout to attach in events
    event FeeTransferFailed(
        address indexed campaign, address token, bytes32 key, address recipient, uint256 amount, bytes extraData
    );

    /// @notice Emitted when someone withdraws funding from a campaign
    ///
    /// @param campaign Address of the campaign
    /// @param token Address of the withdrawn token
    /// @param recipient Address that received the withdrawn tokens
    /// @param amount Amount of tokens withdrawn
    /// @param extraData Extra data for the payout to attach in events
    event FundsWithdrawn(address indexed campaign, address token, address recipient, uint256 amount, bytes extraData);

    /// @notice Emitted when a campaign's status is updated
    ///
    /// @param campaign Address of the campaign
    /// @param sender Address that triggered the status change
    /// @param oldStatus Previous status of the campaign
    /// @param newStatus New status of the campaign
    event CampaignStatusUpdated(
        address indexed campaign, address sender, CampaignStatus oldStatus, CampaignStatus newStatus
    );

    /// @notice Emitted when a campaign's metadata is updated
    ///
    /// @param campaign Address of the campaign
    /// @param uri The URI for the campaign
    event CampaignMetadataUpdated(address indexed campaign, string uri);

    ////////////////////////////////////////////////////////////////
    ///                          Errors                          ///
    ////////////////////////////////////////////////////////////////

    /// @notice Thrown when campaign does not exist
    error CampaignDoesNotExist();

    /// @notice Thrown when campaign is in invalid status for operation
    error InvalidCampaignStatus();

    /// @notice Thrown when address is zero
    error ZeroAddress();

    /// @notice Thrown when amount is zero
    error ZeroAmount();

    /// @notice Thrown when a token send fails without a fallback
    /// @dev Applies to both attempted payouts and funding withdrawals
    error SendFailed(address token, address recipient, uint256 amount);

    /// @notice Thrown when campaign does not have enough balance for an operation
    error InsufficientCampaignFunds();

    ////////////////////////////////////////////////////////////////
    ///                        Modifiers                         ///
    ////////////////////////////////////////////////////////////////

    /// @notice Check if a campaign exists
    /// @param campaign Address of the campaign
    modifier onlyExists(address campaign) {
        if (!campaignExists(campaign)) revert CampaignDoesNotExist();
        _;
    }

    /// @notice Check if a campaign's status allows payouts
    /// @param campaign Address of the campaign
    modifier acceptingPayouts(address campaign) {
        CampaignStatus status = _campaigns[campaign].status;
        if (status == CampaignStatus.INACTIVE || status == CampaignStatus.FINALIZED) revert InvalidCampaignStatus();
        _;
    }

    ////////////////////////////////////////////////////////////////
    ///                    External Functions                    ///
    ////////////////////////////////////////////////////////////////

    /// @notice Constructor for the Flywheel contract
    /// @dev Deploys the Campaign implementation for cloning
    constructor() {
        CAMPAIGN_IMPLEMENTATION = address(new Campaign());
    }

    /// @notice Creates a new campaign
    ///
    /// @dev Call `predictCampaignAddress` to know the address of the campaign without deploying it
    /// @dev Execution does not revert if the campaign is already created
    /// @dev Emits CampaignCreated before any events are emitted by the hooks contract
    ///
    /// @param hooks Address of the campaign hooks contract
    /// @param nonce Nonce used to create the campaign
    /// @param hookData Data for the campaign hook
    ///
    /// @return campaign Address of the newly created campaign
    function createCampaign(address hooks, uint256 nonce, bytes calldata hookData)
        external
        nonReentrant
        returns (address campaign)
    {
        if (hooks == address(0)) revert ZeroAddress();

        // Early return if campaign is already deployed
        campaign = predictCampaignAddress(hooks, nonce, hookData);
        if (campaign.code.length > 0) return campaign;

        campaign = Clones.cloneDeterministic(CAMPAIGN_IMPLEMENTATION, _campaignSalt(hooks, nonce, hookData));
        _campaigns[campaign] = CampaignInfo({status: CampaignStatus.INACTIVE, hooks: CampaignHooks(hooks)});
        emit CampaignCreated(campaign, hooks);
        CampaignHooks(hooks).onCreateCampaign(campaign, nonce, hookData);
    }

    /// @notice Sends immediate payouts to recipients for a campaign
    ///
    /// @dev All payouts must succeed or the entire transaction reverts
    /// @dev Transaction does not revert if a fee send fails, emitting an event instead
    ///
    /// @param campaign Address of the campaign
    /// @param token Address of the token to send
    /// @param hookData Data for the campaign hook
    function send(address campaign, address token, bytes calldata hookData)
        external
        nonReentrant
        onlyExists(campaign)
        acceptingPayouts(campaign)
        returns (Payout[] memory payouts, Distribution[] memory fees, bool sendFeesNow)
    {
        (payouts, fees, sendFeesNow) = _campaigns[campaign].hooks.onSend(msg.sender, campaign, token, hookData);
        _processFees(campaign, token, fees, sendFeesNow);

        uint256 count = payouts.length;
        for (uint256 i = 0; i < count; i++) {
            (address recipient, uint256 amount) = (payouts[i].recipient, payouts[i].amount);

            // Skip zero amounts
            if (amount == 0) continue;

            // Send the payout
            bool success = Campaign(payable(campaign)).sendTokens(token, recipient, amount);
            if (!success) revert SendFailed(token, recipient, amount);
            emit PayoutSent(campaign, token, recipient, amount, payouts[i].extraData);
        }

        _assertCampaignSolvency(campaign, token);
    }

    /// @notice Allocates payouts to a key for a campaign
    ///
    /// @dev Allocated payouts are transferred to recipients on `distribute`
    ///
    /// @param campaign Address of the campaign
    /// @param token Address of the token to be distributed
    /// @param hookData Data for the campaign hook
    function allocate(address campaign, address token, bytes calldata hookData)
        external
        nonReentrant
        onlyExists(campaign)
        acceptingPayouts(campaign)
        returns (Allocation[] memory allocations)
    {
        allocations = _campaigns[campaign].hooks.onAllocate(msg.sender, campaign, token, hookData);

        uint256 totalAmount;
        uint256 count = allocations.length;
        mapping(bytes32 key => uint256 amount) storage _allocatedPayout = allocatedPayout[campaign][token];
        for (uint256 i = 0; i < count; i++) {
            (bytes32 key, uint256 amount) = (allocations[i].key, allocations[i].amount);

            // Skip zero amounts
            if (amount == 0) continue;

            // Update the allocated payout amount
            totalAmount += amount;
            _allocatedPayout[key] += amount;
            emit PayoutAllocated(campaign, token, key, amount, allocations[i].extraData);
        }

        // Update the total allocated payouts
        totalAllocatedPayouts[campaign][token] += totalAmount;
        _assertCampaignSolvency(campaign, token);
    }

    /// @notice Deallocates allocated payouts from a key for a campaign
    ///
    /// @param campaign Address of the campaign
    /// @param token Address of the token to deallocate
    /// @param hookData Data for the campaign hook
    function deallocate(address campaign, address token, bytes calldata hookData)
        external
        nonReentrant
        onlyExists(campaign)
        acceptingPayouts(campaign)
        returns (Allocation[] memory allocations)
    {
        allocations = _campaigns[campaign].hooks.onDeallocate(msg.sender, campaign, token, hookData);

        uint256 totalAmount;
        uint256 count = allocations.length;
        mapping(bytes32 key => uint256 amount) storage _allocatedPayout = allocatedPayout[campaign][token];
        for (uint256 i = 0; i < count; i++) {
            (bytes32 key, uint256 amount) = (allocations[i].key, allocations[i].amount);

            // Skip zero amounts
            if (amount == 0) continue;

            // Update the allocated payout  amount
            totalAmount += amount;
            _allocatedPayout[key] -= amount;
            emit PayoutDeallocated(campaign, token, key, amount, allocations[i].extraData);
        }

        // Update the total allocated payouts
        totalAllocatedPayouts[campaign][token] -= totalAmount;
        _assertCampaignSolvency(campaign, token);
    }

    /// @notice Distributes allocated payouts to recipients for a campaign
    ///
    /// @dev Payouts must first be allocated to a recipient before they can be distributed
    /// @dev Use `reward` for immediate payouts
    /// @dev All payouts must succeed or the entire transaction reverts
    /// @dev Transaction does not revert if a fee send fails, emitting an event instead
    ///
    /// @param campaign Address of the campaign
    /// @param token Address of the token to distribute
    /// @param hookData Data for the campaign hook
    function distribute(address campaign, address token, bytes calldata hookData)
        external
        nonReentrant
        onlyExists(campaign)
        acceptingPayouts(campaign)
        returns (Distribution[] memory distributions, Distribution[] memory fees, bool sendFeesNow)
    {
        (distributions, fees, sendFeesNow) =
            _campaigns[campaign].hooks.onDistribute(msg.sender, campaign, token, hookData);
        _processFees(campaign, token, fees, sendFeesNow);

        uint256 totalAmount;
        uint256 count = distributions.length;
        mapping(bytes32 key => uint256 amount) storage _allocatedPayout = allocatedPayout[campaign][token];
        for (uint256 i = 0; i < count; i++) {
            (address recipient, bytes32 key, uint256 amount) =
                (distributions[i].recipient, distributions[i].key, distributions[i].amount);

            // Skip zero amounts
            if (amount == 0) continue;

            // Update the allocated payout amount
            totalAmount += amount;
            _allocatedPayout[key] -= amount;

            // Send the payout
            bool success = Campaign(payable(campaign)).sendTokens(token, recipient, amount);
            if (!success) revert SendFailed(token, recipient, amount);
            emit PayoutDistributed(campaign, token, key, recipient, amount, distributions[i].extraData);
        }

        // Update the total allocated payouts
        totalAllocatedPayouts[campaign][token] -= totalAmount;
        _assertCampaignSolvency(campaign, token);
    }

    /// @notice Collects fees from a campaign
    ///
    /// @dev Transaction does not revert if a fee send fails, emitting an event instead
    ///
    /// @param campaign Address of the campaign
    /// @param token Address of the token to collect fees from
    /// @param hookData Data for the campaign hook
    function distributeFees(address campaign, address token, bytes calldata hookData)
        external
        nonReentrant
        onlyExists(campaign)
        returns (Distribution[] memory distributions)
    {
        distributions = _campaigns[campaign].hooks.onDistributeFees(msg.sender, campaign, token, hookData);

        uint256 totalAmount;
        uint256 count = distributions.length;
        mapping(bytes32 key => uint256 amount) storage _allocatedFee = allocatedFee[campaign][token];
        for (uint256 i = 0; i < count; i++) {
            (address recipient, bytes32 key, uint256 amount) =
                (distributions[i].recipient, distributions[i].key, distributions[i].amount);

            // Skip zero amounts
            if (amount == 0) continue;

            // Send the fee
            bool success = Campaign(payable(campaign)).sendTokens(token, recipient, amount);
            if (success) {
                // Update the allocated fee amount
                totalAmount += amount;
                _allocatedFee[key] -= amount;
                emit FeeDistributed(campaign, token, key, recipient, amount, distributions[i].extraData);
            } else {
                emit FeeTransferFailed(
                    campaign, token, distributions[i].key, recipient, amount, distributions[i].extraData
                );
            }
        }

        // Update the total allocated fees
        totalAllocatedFees[campaign][token] -= totalAmount;
        _assertCampaignSolvency(campaign, token);
    }

    /// @notice Withdraw funding from a campaign
    ///
    /// @dev Allocated payouts are ignored for solvency requirements if the campaign is finalized
    ///
    /// @param campaign Address of the campaign
    /// @param token Address of the token to withdraw
    /// @param hookData Data for the campaign hook
    function withdrawFunds(address campaign, address token, bytes calldata hookData)
        external
        nonReentrant
        onlyExists(campaign)
    {
        Payout memory payout = _campaigns[campaign].hooks.onWithdrawFunds(msg.sender, campaign, token, hookData);
        (address recipient, uint256 amount) = (payout.recipient, payout.amount);

        // Skip zero amounts
        if (amount == 0) revert ZeroAmount();

        // Send the payout
        bool success = Campaign(payable(campaign)).sendTokens(token, recipient, amount);
        if (!success) revert SendFailed(token, recipient, amount);
        emit FundsWithdrawn(campaign, token, recipient, amount, payout.extraData);

        // Assert campaign solvency, but ignore payouts if campaign is finalized
        uint256 requiredSolvency = campaignStatus(campaign) == CampaignStatus.FINALIZED
            ? totalAllocatedFees[campaign][token]
            : totalAllocatedFees[campaign][token] + totalAllocatedPayouts[campaign][token];
        if (_campaignTokenBalance(campaign, token) < requiredSolvency) revert InsufficientCampaignFunds();
    }

    /// @notice Updates the status of a campaign
    ///
    /// @param campaign Address of the campaign
    /// @param newStatus New status of the campaign
    /// @param hookData Data for the campaign hook
    function updateStatus(address campaign, CampaignStatus newStatus, bytes calldata hookData)
        external
        nonReentrant
        onlyExists(campaign)
    {
        CampaignStatus oldStatus = _campaigns[campaign].status;
        if (
            newStatus == oldStatus // must update status
                || oldStatus == CampaignStatus.FINALIZED // cannot update from finalized
                || (oldStatus == CampaignStatus.FINALIZING && newStatus != CampaignStatus.FINALIZED) // finalizing can only update to finalized
        ) revert InvalidCampaignStatus();

        // Delegate more restrictions to the hooks contract
        _campaigns[campaign].hooks.onUpdateStatus(msg.sender, campaign, oldStatus, newStatus, hookData);

        // Update the status
        _campaigns[campaign].status = newStatus;
        emit CampaignStatusUpdated(campaign, msg.sender, oldStatus, newStatus);
    }

    /// @notice Updates the metadata for a campaign
    ///
    /// @dev Indexers should update their metadata cache for this campaign by fetching the campaignURI
    ///
    /// @param campaign Address of the campaign
    /// @param hookData Data for the campaign hook
    function updateMetadata(address campaign, bytes calldata hookData) external nonReentrant onlyExists(campaign) {
        // Delegate restrictions to the hooks contract
        _campaigns[campaign].hooks.onUpdateMetadata(msg.sender, campaign, hookData);

        // Emit the metadata updated events
        emit CampaignMetadataUpdated(campaign, campaignURI(campaign));
        Campaign(payable(campaign)).updateContractURI();
    }

    ////////////////////////////////////////////////////////////////
    ///                 External View Functions                  ///
    ////////////////////////////////////////////////////////////////

    /// @notice Returns the address of a campaign given its creation parameters
    ///
    /// @param hooks Address of the campaign hooks contract
    /// @param nonce Nonce used to create the campaign
    /// @param hookData Data for the campaign hook
    ///
    /// @return campaign Address of the campaign
    function predictCampaignAddress(address hooks, uint256 nonce, bytes calldata hookData)
        public
        view
        returns (address campaign)
    {
        return Clones.predictDeterministicAddress(CAMPAIGN_IMPLEMENTATION, _campaignSalt(hooks, nonce, hookData));
    }

    /// @notice Checks if a campaign exists
    ///
    /// @param campaign Address of the campaign
    ///
    /// @return exists True if the campaign exists, false otherwise
    function campaignExists(address campaign) public view returns (bool) {
        return address(_campaigns[campaign].hooks) != address(0);
    }

    /// @notice Returns the hooks of a campaign
    ///
    /// @param campaign Address of the campaign
    ///
    /// @return hooks Hooks contract for the campaign
    function campaignHooks(address campaign) public view onlyExists(campaign) returns (address hooks) {
        return address(_campaigns[campaign].hooks);
    }

    /// @notice Returns the status of a campaign
    ///
    /// @param campaign Address of the campaign
    ///
    /// @return status Current status of the campaign
    function campaignStatus(address campaign) public view onlyExists(campaign) returns (CampaignStatus status) {
        return _campaigns[campaign].status;
    }

    /// @notice Returns the URI for a campaign
    ///
    /// @param campaign Address of the campaign
    ///
    /// @return uri URI for campaign metadata
    function campaignURI(address campaign) public view onlyExists(campaign) returns (string memory uri) {
        return _campaigns[campaign].hooks.campaignURI(campaign);
    }

    ////////////////////////////////////////////////////////////////
    ///                    Internal Functions                    ///
    ////////////////////////////////////////////////////////////////

    /// @notice Processes fees, either sending or allocating them to a key
    ///
    /// @dev Failed fees emit events and are converted into allocations
    ///
    /// @param campaign Address of the campaign
    /// @param token Address of the token to allocate the fee from
    /// @param fees Allocation of the fees to be sent immediately
    /// @param sendFeesNow Whether to send fees now
    function _processFees(address campaign, address token, Distribution[] memory fees, bool sendFeesNow) internal {
        uint256 totalAllocated;
        uint256 count = fees.length;
        for (uint256 i = 0; i < count; i++) {
            // Skip zero amounts
            uint256 amount = fees[i].amount;
            if (amount == 0) continue;

            // Send fees now if applicable
            bool sendSucceess;
            if (sendFeesNow) {
                address recipient = fees[i].recipient;
                sendSucceess = Campaign(payable(campaign)).sendTokens(token, recipient, amount);
                if (sendSucceess) {
                    emit FeeSent(campaign, token, recipient, amount, fees[i].extraData);
                } else {
                    emit FeeTransferFailed(campaign, token, fees[i].key, recipient, amount, fees[i].extraData);
                }
            }

            // If not sending fees now or send failed, update allocated fee storage and emit event
            if (!sendFeesNow || !sendSucceess) {
                bytes32 key = fees[i].key;
                totalAllocated += amount;
                allocatedFee[campaign][token][key] += amount;
                emit FeeAllocated(campaign, token, key, amount, fees[i].extraData);
            }
        }

        // Update the total allocated fees
        totalAllocatedFees[campaign][token] += totalAllocated;
    }

    /// @notice Enforces that a campaign has enough reserved funds for an operation
    ///
    /// @param campaign Address of the campaign
    /// @param token Address of the token to check
    function _assertCampaignSolvency(address campaign, address token) internal view {
        uint256 totalAllocated = totalAllocatedPayouts[campaign][token] + totalAllocatedFees[campaign][token];
        if (_campaignTokenBalance(campaign, token) < totalAllocated) revert InsufficientCampaignFunds();
    }

    /// @notice Returns the campaign balance for a given token, supporting native token via ERC-7528 convention
    ///
    /// @param campaign Address of the campaign
    /// @param token Address of the token, or native token sentinel
    ///
    /// @param balance Balance of the campaign for the given token
    function _campaignTokenBalance(address campaign, address token) internal view returns (uint256 balance) {
        return token == Constants.NATIVE_TOKEN ? campaign.balance : IERC20(token).balanceOf(campaign);
    }

    /// @notice Returns the salt for a campaign
    ///
    /// @param hooks Address of the campaign hooks contract
    /// @param nonce Nonce used to create the campaign
    /// @param hookData Data for the campaign hook
    ///
    /// @return salt The salt for the campaign
    function _campaignSalt(address hooks, uint256 nonce, bytes calldata hookData) internal pure returns (bytes32 salt) {
        return keccak256(abi.encode(hooks, nonce, hookData));
    }

    /// @dev Override to use transient reentrancy guard on all chains
    function _useTransientReentrancyGuardOnlyOnMainnet() internal pure override returns (bool) {
        return false;
    }
}
