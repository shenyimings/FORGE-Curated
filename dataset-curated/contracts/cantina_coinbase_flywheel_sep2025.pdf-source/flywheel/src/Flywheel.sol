// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuardTransient} from "solady/utils/ReentrancyGuardTransient.sol";

import {Campaign} from "./Campaign.sol";
import {CampaignHooks} from "./CampaignHooks.sol";

/// @title Flywheel
///
/// @notice Main contract for managing advertising campaigns and attribution
///
/// @dev Structures campaign metadata, lifecycle, payouts, and fees
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

    /// @notice Campaign information structure
    struct CampaignInfo {
        /// @dev status Current status of the campaign
        CampaignStatus status;
        /// @dev hooks Address of the campaign hooks contract
        CampaignHooks hooks;
    }

    /// @notice Payout for a recipient
    struct Payout {
        /// @dev recipient Address receiving the payout
        address recipient;
        /// @dev amount Amount of tokens to be paid out
        uint256 amount;
        /// @dev extraData Extra data for the payout to attach in events
        bytes extraData;
    }

    /// @notice Allocation for a key
    struct Allocation {
        /// @dev key Key for the allocation
        bytes32 key;
        /// @dev amount Amount of tokens to be paid out
        uint256 amount;
        /// @dev extraData Extra data to attach in events
        bytes extraData;
    }

    /// @notice Distribution for a key to a recipient
    struct Distribution {
        /// @dev recipient Address receiving the distribution
        address recipient;
        /// @dev key Key for the allocation
        bytes32 key;
        /// @dev amount Amount of tokens to be paid out
        uint256 amount;
        /// @dev extraData Extra data to attach in events
        bytes extraData;
    }

    /// @notice Implementation for Campaign contracts
    address public immutable campaignImplementation;

    /// @notice Allocated rewards that are pending distribution
    mapping(address campaign => mapping(address token => mapping(bytes32 key => uint256 amount))) public allocatedPayout;

    /// @notice Fees that are pending collection
    mapping(address campaign => mapping(address token => mapping(bytes32 key => uint256 amount))) public allocatedFee;

    /// @notice Total funds reserved for a campaign's allocations
    mapping(address campaign => mapping(address token => uint256 amount)) public totalAllocatedPayouts;

    /// @notice Total funds reserved for a campaign's fees
    mapping(address campaign => mapping(address token => uint256 amount)) public totalAllocatedFees;

    /// @notice Campaign state
    mapping(address campaign => CampaignInfo) internal _campaigns;

    /// @notice Emitted when a new campaign is created
    ///
    /// @param campaign Address of the created campaign
    /// @param hooks Address of the campaign hooks contract
    event CampaignCreated(address indexed campaign, address hooks);

    /// @notice Emitted when a campaign is updated
    ///
    /// @param campaign Address of the campaign
    /// @param uri The URI for the campaign
    event CampaignMetadataUpdated(address indexed campaign, string uri);

    /// @notice Emitted when a campaign status is updated
    ///
    /// @param campaign Address of the campaign
    /// @param sender Address that triggered the status change
    /// @param oldStatus Previous status of the campaign
    /// @param newStatus New status of the campaign
    event CampaignStatusUpdated(
        address indexed campaign, address sender, CampaignStatus oldStatus, CampaignStatus newStatus
    );

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

    /// @notice Emitted when allocated payouts are distributed to a recipient
    ///
    /// @param campaign Address of the campaign
    /// @param token Address of the payout token
    /// @param key Key for the allocation
    /// @param recipient Address receiving the distribution
    /// @param amount Amount of tokens distributed
    /// @param extraData Extra data for the payout to attach in events
    event PayoutsDistributed(
        address indexed campaign, address token, bytes32 key, address recipient, uint256 amount, bytes extraData
    );

    /// @notice Emitted when allocated payouts are deallocated from a recipient
    ///
    /// @param campaign Address of the campaign
    /// @param token Address of the payout token
    /// @param key Key for the allocation
    /// @param amount Amount of tokens deallocated
    /// @param extraData Extra data for the payout to attach in events
    event PayoutsDeallocated(address indexed campaign, address token, bytes32 key, uint256 amount, bytes extraData);

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

    /// @notice Emitted when accumulated fees are collected
    ///
    /// @param campaign Address of the campaign
    /// @param token Address of the collected token
    /// @param key Key for the fees
    /// @param recipient Address receiving the collected fees
    /// @param amount Amount of tokens collected
    /// @param extraData Extra data for the payout to attach in events
    event FeesDistributed(
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

    /// @notice Thrown when campaign does not exist
    error CampaignDoesNotExist();

    /// @notice Thrown when campaign is in invalid status for operation
    error InvalidCampaignStatus();

    /// @notice Thrown when address is zero
    error ZeroAddress();

    /// @notice Thrown when amount is zero
    error ZeroAmount();

    /// @notice Thrown when campaign does not have enough balance for an operation
    error InsufficientCampaignFunds();

    /// @notice Check if a campaign exists
    ///
    /// @param campaign Address of the campaign
    modifier onlyExists(address campaign) {
        if (!campaignExists(campaign)) revert CampaignDoesNotExist();
        _;
    }

    /// @notice Check if a campaign's status allows payouts
    ///
    /// @param campaign Address of the campaign
    modifier acceptingPayouts(address campaign) {
        CampaignStatus status = _campaigns[campaign].status;
        if (status == CampaignStatus.INACTIVE || status == CampaignStatus.FINALIZED) revert InvalidCampaignStatus();
        _;
    }

    /// @notice Constructor for the Flywheel contract
    ///
    /// @dev Deploys a new Campaign implementation for cloning
    constructor() {
        campaignImplementation = address(new Campaign());
    }

    /// @notice Creates a new campaign
    ///
    /// @param hooks Address of the campaign hooks contract
    /// @param nonce Nonce used to create the campaign
    /// @param hookData Data for the campaign hook
    ///
    /// @return campaign Address of the newly created campaign
    ///
    /// @dev Call `predictCampaignAddress` to know the address of the campaign without deploying it
    function createCampaign(address hooks, uint256 nonce, bytes calldata hookData)
        external
        nonReentrant
        returns (address campaign)
    {
        if (hooks == address(0)) revert ZeroAddress();
        campaign = Clones.cloneDeterministic(campaignImplementation, keccak256(abi.encode(hooks, nonce, hookData)));
        _campaigns[campaign] = CampaignInfo({status: CampaignStatus.INACTIVE, hooks: CampaignHooks(hooks)});
        emit CampaignCreated(campaign, hooks);
        CampaignHooks(hooks).onCreateCampaign(campaign, nonce, hookData);
    }

    /// @notice Sends immediate payouts to recipients for a campaign
    ///
    /// @param campaign Address of the campaign
    /// @param token Address of the token to send
    /// @param hookData Data for the campaign hook
    function send(address campaign, address token, bytes calldata hookData)
        external
        nonReentrant
        onlyExists(campaign)
        acceptingPayouts(campaign)
        returns (Payout[] memory payouts, Payout[] memory immediateFees, Allocation[] memory delayedFees)
    {
        (payouts, immediateFees, delayedFees) = _campaigns[campaign].hooks.onSend(msg.sender, campaign, token, hookData);
        _processFees(campaign, token, immediateFees, delayedFees);

        uint256 count = payouts.length;
        for (uint256 i = 0; i < count; i++) {
            (address recipient, uint256 amount) = (payouts[i].recipient, payouts[i].amount);
            if (amount == 0) continue;
            Campaign(payable(campaign)).sendTokens(token, recipient, amount);
            emit PayoutSent(campaign, token, recipient, amount, payouts[i].extraData);
        }

        _assertCampaignSolvency(campaign, token);
    }

    /// @notice Allocates payouts to a key for a campaign
    ///
    /// @param campaign Address of the campaign
    /// @param token Address of the token to be distributed
    /// @param hookData Data for the campaign hook
    ///
    /// @dev Allocated payouts are transferred to recipients on `distribute`
    function allocate(address campaign, address token, bytes calldata hookData)
        external
        nonReentrant
        onlyExists(campaign)
        acceptingPayouts(campaign)
        returns (Allocation[] memory allocations)
    {
        allocations = _campaigns[campaign].hooks.onAllocate(msg.sender, campaign, token, hookData);

        (uint256 totalAmount, uint256 count) = (0, allocations.length);
        mapping(bytes32 key => uint256 amount) storage _allocatedPayout = allocatedPayout[campaign][token];
        for (uint256 i = 0; i < count; i++) {
            (bytes32 key, uint256 amount) = (allocations[i].key, allocations[i].amount);
            if (amount == 0) continue;
            totalAmount += amount;
            _allocatedPayout[key] += amount;
            emit PayoutAllocated(campaign, token, key, amount, allocations[i].extraData);
        }

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

        (uint256 totalAmount, uint256 count) = (0, allocations.length);
        mapping(bytes32 key => uint256 amount) storage _allocatedPayout = allocatedPayout[campaign][token];
        for (uint256 i = 0; i < count; i++) {
            (bytes32 key, uint256 amount) = (allocations[i].key, allocations[i].amount);
            if (amount == 0) continue;
            totalAmount += amount;
            _allocatedPayout[key] -= amount;
            emit PayoutsDeallocated(campaign, token, key, amount, allocations[i].extraData);
        }

        totalAllocatedPayouts[campaign][token] -= totalAmount;
        _assertCampaignSolvency(campaign, token);
    }

    /// @notice Distributes allocated payouts to recipients for a campaign
    ///
    /// @param campaign Address of the campaign
    /// @param token Address of the token to distribute
    /// @param hookData Data for the campaign hook
    ///
    /// @dev Payouts must first be allocated to a recipient before they can be distributed
    /// @dev Use `reward` for immediate payouts
    function distribute(address campaign, address token, bytes calldata hookData)
        external
        nonReentrant
        onlyExists(campaign)
        acceptingPayouts(campaign)
        returns (Distribution[] memory distributions, Payout[] memory immediateFees, Allocation[] memory delayedFees)
    {
        (distributions, immediateFees, delayedFees) =
            _campaigns[campaign].hooks.onDistribute(msg.sender, campaign, token, hookData);
        _processFees(campaign, token, immediateFees, delayedFees);

        (uint256 totalAmount, uint256 count) = (0, distributions.length);
        mapping(bytes32 key => uint256 amount) storage _allocatedPayout = allocatedPayout[campaign][token];
        for (uint256 i = 0; i < count; i++) {
            (address recipient, bytes32 key, uint256 amount) =
                (distributions[i].recipient, distributions[i].key, distributions[i].amount);
            if (amount == 0) continue;
            totalAmount += amount;
            _allocatedPayout[key] -= amount;
            Campaign(payable(campaign)).sendTokens(token, recipient, amount);
            emit PayoutsDistributed(campaign, token, key, recipient, amount, distributions[i].extraData);
        }

        totalAllocatedPayouts[campaign][token] -= totalAmount;
        _assertCampaignSolvency(campaign, token);
    }

    /// @notice Collects fees from a campaign
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

        (uint256 totalAmount, uint256 count) = (0, distributions.length);
        mapping(bytes32 key => uint256 amount) storage _allocatedFee = allocatedFee[campaign][token];
        for (uint256 i = 0; i < count; i++) {
            (address recipient, bytes32 key, uint256 amount) =
                (distributions[i].recipient, distributions[i].key, distributions[i].amount);
            if (amount == 0) continue;
            totalAmount += amount;
            _allocatedFee[key] -= amount;
            Campaign(payable(campaign)).sendTokens(token, recipient, amount);
            emit FeesDistributed(campaign, token, key, recipient, amount, distributions[i].extraData);
        }

        totalAllocatedFees[campaign][token] -= totalAmount;
        _assertCampaignSolvency(campaign, token);
    }

    /// @notice Withdraw tokens from a campaign
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
        if (amount == 0) revert ZeroAmount();
        Campaign(payable(campaign)).sendTokens(token, recipient, amount);
        emit FundsWithdrawn(campaign, token, recipient, amount, payout.extraData);

        // Assert campaign solvency, but ignore payouts if campaign is finalized
        uint256 requiredSolvency = campaignStatus(campaign) == CampaignStatus.FINALIZED
            ? totalAllocatedFees[campaign][token]
            : totalAllocatedFees[campaign][token] + totalAllocatedPayouts[campaign][token];
        if (IERC20(token).balanceOf(campaign) < requiredSolvency) revert InsufficientCampaignFunds();
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

        _campaigns[campaign].hooks.onUpdateStatus(msg.sender, campaign, oldStatus, newStatus, hookData);
        _campaigns[campaign].status = newStatus;
        emit CampaignStatusUpdated(campaign, msg.sender, oldStatus, newStatus);
    }

    /// @notice Updates the metadata for a campaign
    ///
    /// @param campaign Address of the campaign
    /// @param hookData Data for the campaign hook
    ///
    /// @dev Indexers should update their metadata cache for this campaign by fetching the campaignURI
    function updateMetadata(address campaign, bytes calldata hookData) external nonReentrant onlyExists(campaign) {
        if (_campaigns[campaign].status == CampaignStatus.FINALIZED) revert InvalidCampaignStatus();
        _campaigns[campaign].hooks.onUpdateMetadata(msg.sender, campaign, hookData);
        emit CampaignMetadataUpdated(campaign, campaignURI(campaign));
        Campaign(payable(campaign)).updateContractURI();
    }

    /// @notice Returns the address of a campaign given its creation parameters
    ///
    /// @param hooks Address of the campaign hooks contract
    /// @param nonce Nonce used to create the campaign
    /// @param hookData Data for the campaign hook
    ///
    /// @return campaign Address of the campaign
    function predictCampaignAddress(address hooks, uint256 nonce, bytes calldata hookData)
        external
        view
        returns (address campaign)
    {
        return Clones.predictDeterministicAddress(campaignImplementation, keccak256(abi.encode(hooks, nonce, hookData)));
    }

    /// @notice Checks if a campaign exists
    ///
    /// @param campaign Address of the campaign
    ///
    /// @return true if the campaign exists, false otherwise
    function campaignExists(address campaign) public view returns (bool) {
        return address(_campaigns[campaign].hooks) != address(0);
    }

    /// @notice Returns the hooks of a campaign
    ///
    /// @param campaign Address of the campaign
    ///
    /// @return hooks of the campaign
    function campaignHooks(address campaign) public view onlyExists(campaign) returns (address hooks) {
        return address(_campaigns[campaign].hooks);
    }

    /// @notice Returns the status of a campaign
    ///
    /// @param campaign Address of the campaign
    ///
    /// @return status of the campaign
    function campaignStatus(address campaign) public view onlyExists(campaign) returns (CampaignStatus status) {
        return _campaigns[campaign].status;
    }

    /// @notice Returns the URI for a campaign
    ///
    /// @param campaign Address of the campaign
    ///
    /// @return uri The URI for the campaign
    function campaignURI(address campaign) public view onlyExists(campaign) returns (string memory uri) {
        return _campaigns[campaign].hooks.campaignURI(campaign);
    }

    /// @notice Allocates a fee to a key
    ///
    /// @param campaign Address of the campaign
    /// @param token Address of the token to allocate the fee from
    /// @param immediateFees Allocation of the fees to be sent immediately
    /// @param delayedFees Allocation of the fees to be allocated
    function _processFees(
        address campaign,
        address token,
        Payout[] memory immediateFees,
        Allocation[] memory delayedFees
    ) internal {
        uint256 count = immediateFees.length;
        for (uint256 i = 0; i < count; i++) {
            (address recipient, uint256 amount) = (immediateFees[i].recipient, immediateFees[i].amount);
            if (amount == 0) continue;
            Campaign(payable(campaign)).sendTokens(token, recipient, amount);
            emit FeeSent(campaign, token, recipient, amount, immediateFees[i].extraData);
        }

        count = delayedFees.length;
        uint256 totalFeeAmount = 0;
        mapping(bytes32 key => uint256 amount) storage _allocatedFee = allocatedFee[campaign][token];
        for (uint256 i = 0; i < count; i++) {
            (bytes32 key, uint256 amount) = (delayedFees[i].key, delayedFees[i].amount);
            if (amount == 0) continue;
            totalFeeAmount += amount;
            _allocatedFee[key] += amount;
            emit FeeAllocated(campaign, token, key, amount, delayedFees[i].extraData);
        }
        totalAllocatedFees[campaign][token] += totalFeeAmount;
    }

    /// @notice Enforces that a campaign has enough reserved funds for an operation
    ///
    /// @param campaign Address of the campaign
    /// @param token Address of the token to check
    function _assertCampaignSolvency(address campaign, address token) internal {
        uint256 totalAllocated = totalAllocatedPayouts[campaign][token] + totalAllocatedFees[campaign][token];
        if (IERC20(token).balanceOf(campaign) < totalAllocated) revert InsufficientCampaignFunds();
    }

    /// @dev Override to use transient reentrancy guard on all chains
    function _useTransientReentrancyGuardOnlyOnMainnet() internal pure override returns (bool) {
        return false;
    }
}
