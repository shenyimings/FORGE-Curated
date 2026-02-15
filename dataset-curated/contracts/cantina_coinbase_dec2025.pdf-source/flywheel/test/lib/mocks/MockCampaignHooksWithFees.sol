// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {CampaignHooks} from "../../../src/CampaignHooks.sol";
import {Flywheel} from "../../../src/Flywheel.sol";

/// @title MockCampaignHooksWithFees
/// @notice A minimal hook modeled after SimpleRewards that also supports fee passthrough
/// @dev This mock decodes payouts and fee distributions directly from hookData for send/distribute paths
contract MockCampaignHooksWithFees is CampaignHooks {
    /// @notice Owners of the campaigns
    mapping(address campaign => address owner) public owners;

    /// @notice Managers of the campaigns
    mapping(address campaign => address manager) public managers;

    /// @notice Mapping of campaign addresses to their URI
    mapping(address campaign => string uri) public override campaignURI;

    /// @notice Emitted when a campaign is created
    /// @param campaign Address of the campaign
    /// @param owner Address of the owner of the campaign
    /// @param manager Address of the manager of the campaign
    /// @param uri URI of the campaign
    event CampaignCreated(address indexed campaign, address owner, address manager, string uri);

    /// @notice Thrown when the sender is not the manager of the campaign
    error Unauthorized();

    /// @dev Restricts caller to the configured manager for the campaign
    modifier onlyManager(address sender, address campaign) {
        if (sender != managers[campaign]) revert Unauthorized();
        _;
    }

    /// @notice Hooks constructor
    /// @param flywheel_ Address of the flywheel contract
    constructor(address flywheel_) CampaignHooks(flywheel_) {}

    /// @inheritdoc CampaignHooks
    function _onCreateCampaign(address campaign, uint256, bytes calldata hookData) internal virtual override {
        (address owner_, address manager_, string memory uri_) = abi.decode(hookData, (address, address, string));
        owners[campaign] = owner_;
        managers[campaign] = manager_;
        campaignURI[campaign] = uri_;
        emit CampaignCreated(campaign, owner_, manager_, uri_);
    }

    /// @inheritdoc CampaignHooks
    /// @dev hookData encoding: (Flywheel.Payout[] payouts, Flywheel.Distribution[] fees, bool sendFeesNow)
    function _onSend(address sender, address campaign, address, bytes calldata hookData)
        internal
        virtual
        override
        onlyManager(sender, campaign)
        returns (Flywheel.Payout[] memory payouts, Flywheel.Distribution[] memory fees, bool sendFeesNow)
    {
        (payouts, fees, sendFeesNow) = abi.decode(hookData, (Flywheel.Payout[], Flywheel.Distribution[], bool));
    }

    /// @inheritdoc CampaignHooks
    /// @dev hookData encoding: Flywheel.Payout[] payouts
    function _onAllocate(address sender, address campaign, address, bytes calldata hookData)
        internal
        virtual
        override
        onlyManager(sender, campaign)
        returns (Flywheel.Allocation[] memory allocations)
    {
        Flywheel.Payout[] memory payouts = abi.decode(hookData, (Flywheel.Payout[]));
        allocations = new Flywheel.Allocation[](payouts.length);
        uint256 count = payouts.length;
        for (uint256 i = 0; i < count; i++) {
            allocations[i] = Flywheel.Allocation({
                key: bytes32(bytes20(payouts[i].recipient)), amount: payouts[i].amount, extraData: payouts[i].extraData
            });
        }
    }

    /// @inheritdoc CampaignHooks
    /// @dev hookData encoding: Flywheel.Payout[] payouts
    function _onDeallocate(address sender, address campaign, address, bytes calldata hookData)
        internal
        virtual
        override
        onlyManager(sender, campaign)
        returns (Flywheel.Allocation[] memory allocations)
    {
        Flywheel.Payout[] memory payouts = abi.decode(hookData, (Flywheel.Payout[]));
        allocations = new Flywheel.Allocation[](payouts.length);
        uint256 count = payouts.length;
        for (uint256 i = 0; i < count; i++) {
            allocations[i] = Flywheel.Allocation({
                key: bytes32(bytes20(payouts[i].recipient)), amount: payouts[i].amount, extraData: payouts[i].extraData
            });
        }
    }

    /// @inheritdoc CampaignHooks
    /// @dev hookData encoding: (Flywheel.Payout[] payouts, Flywheel.Distribution[] fees, bool sendFeesNow)
    function _onDistribute(address sender, address campaign, address, bytes calldata hookData)
        internal
        virtual
        override
        onlyManager(sender, campaign)
        returns (Flywheel.Distribution[] memory distributions, Flywheel.Distribution[] memory fees, bool sendFeesNow)
    {
        Flywheel.Payout[] memory payouts;
        (payouts, fees, sendFeesNow) = abi.decode(hookData, (Flywheel.Payout[], Flywheel.Distribution[], bool));

        distributions = new Flywheel.Distribution[](payouts.length);
        uint256 count = payouts.length;
        for (uint256 i = 0; i < count; i++) {
            distributions[i] = Flywheel.Distribution({
                recipient: payouts[i].recipient,
                key: bytes32(bytes20(payouts[i].recipient)),
                amount: payouts[i].amount,
                extraData: payouts[i].extraData
            });
        }
    }

    /// @inheritdoc CampaignHooks
    /// @dev hookData encoding: Flywheel.Distribution[] distributions
    function _onDistributeFees(address sender, address campaign, address, bytes calldata hookData)
        internal
        virtual
        override
        returns (Flywheel.Distribution[] memory distributions)
    {
        // No access restriction, anyone can disburse fees to recipients
        distributions = abi.decode(hookData, (Flywheel.Distribution[]));
    }

    /// @inheritdoc CampaignHooks
    function _onWithdrawFunds(address sender, address campaign, address, bytes calldata hookData)
        internal
        virtual
        override
        returns (Flywheel.Payout memory payout)
    {
        if (sender != owners[campaign]) revert Unauthorized();
        return abi.decode(hookData, (Flywheel.Payout));
    }

    /// @inheritdoc CampaignHooks
    function _onUpdateStatus(
        address sender,
        address campaign,
        Flywheel.CampaignStatus oldStatus,
        Flywheel.CampaignStatus newStatus,
        bytes calldata hookData
    ) internal virtual override onlyManager(sender, campaign) {}

    /// @inheritdoc CampaignHooks
    function _onUpdateMetadata(address sender, address campaign, bytes calldata hookData)
        internal
        virtual
        override
        onlyManager(sender, campaign)
    {
        if (hookData.length > 0) campaignURI[campaign] = string(hookData);
    }
}
