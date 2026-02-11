// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Flywheel} from "../Flywheel.sol";
import {CampaignHooks} from "../CampaignHooks.sol";

/// @title SimpleRewards
///
/// @notice Campaign Hooks for simple rewards controlled by a campaign manager
contract SimpleRewards is CampaignHooks {
    /// @notice Owners of the campaigns
    mapping(address campaign => address owner) public owners;

    /// @notice Managers of the campaigns
    mapping(address campaign => address manager) public managers;

    /// @notice Mapping of campaign addresses to their URI
    mapping(address campaign => string uri) public override campaignURI;

    /// @notice Emitted when a campaign is created
    ///
    /// @param campaign Address of the campaign
    /// @param owner Address of the owner of the campaign
    /// @param manager Address of the manager of the campaign
    /// @param uri URI of the campaign
    event CampaignCreated(address indexed campaign, address owner, address manager, string uri);

    /// @notice Thrown when the sender is not the manager of the campaign
    error Unauthorized();

    /// @notice Modifier to check if the sender is the manager of the campaign
    ///
    /// @param sender Address of the sender
    /// @param campaign Address of the campaign
    ///
    /// @dev Reverts if the sender is not the manager of the campaign
    modifier onlyManager(address sender, address campaign) {
        if (sender != managers[campaign]) revert Unauthorized();
        _;
    }

    /// @notice Hooks constructor
    ///
    /// @param flywheel_ Address of the flywheel contract
    constructor(address flywheel_) CampaignHooks(flywheel_) {}

    /// @inheritdoc CampaignHooks
    function _onCreateCampaign(address campaign, uint256 nonce, bytes calldata hookData) internal virtual override {
        (address owner, address manager, string memory uri) = abi.decode(hookData, (address, address, string));
        owners[campaign] = owner;
        managers[campaign] = manager;
        campaignURI[campaign] = uri;
        emit CampaignCreated(campaign, owner, manager, uri);
    }

    /// @inheritdoc CampaignHooks
    function _onSend(address sender, address campaign, address token, bytes calldata hookData)
        internal
        virtual
        override
        onlyManager(sender, campaign)
        returns (
            Flywheel.Payout[] memory payouts,
            Flywheel.Payout[] memory immediateFees,
            Flywheel.Allocation[] memory delayedFees
        )
    {
        payouts = abi.decode(hookData, (Flywheel.Payout[]));
    }

    /// @inheritdoc CampaignHooks
    function _onAllocate(address sender, address campaign, address token, bytes calldata hookData)
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
                key: bytes32(bytes20(payouts[i].recipient)),
                amount: payouts[i].amount,
                extraData: payouts[i].extraData
            });
        }
    }

    /// @inheritdoc CampaignHooks
    function _onDeallocate(address sender, address campaign, address token, bytes calldata hookData)
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
                key: bytes32(bytes20(payouts[i].recipient)),
                amount: payouts[i].amount,
                extraData: payouts[i].extraData
            });
        }
    }

    /// @inheritdoc CampaignHooks
    function _onDistribute(address sender, address campaign, address token, bytes calldata hookData)
        internal
        virtual
        override
        onlyManager(sender, campaign)
        returns (
            Flywheel.Distribution[] memory distributions,
            Flywheel.Payout[] memory immediateFees,
            Flywheel.Allocation[] memory delayedFees
        )
    {
        Flywheel.Payout[] memory payouts = abi.decode(hookData, (Flywheel.Payout[]));
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
    function _onWithdrawFunds(address sender, address campaign, address token, bytes calldata hookData)
        internal
        virtual
        override
        returns (Flywheel.Payout memory payout)
    {
        if (sender != owners[campaign]) revert Unauthorized();
        return (abi.decode(hookData, (Flywheel.Payout)));
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
