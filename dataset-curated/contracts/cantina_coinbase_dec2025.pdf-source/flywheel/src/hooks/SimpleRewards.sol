// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {LibString} from "solady/utils/LibString.sol";

import {CampaignHooks} from "../CampaignHooks.sol";
import {Flywheel} from "../Flywheel.sol";

/// @title SimpleRewards
///
/// @notice Campaign Hooks for simple rewards controlled by a campaign manager
///
/// @author Coinbase (https://github.com/base/flywheel)
contract SimpleRewards is CampaignHooks {
    /// @notice Owners of the campaigns
    mapping(address campaign => address owner) public owners;

    /// @notice Managers of the campaigns
    mapping(address campaign => address manager) public managers;

    /// @notice URI prefixes for campaign metadata
    mapping(address campaign => string uriPrefix) internal _uriPrefix;

    /// @notice Emitted when a campaign is created
    ///
    /// @param campaign Address of the campaign
    /// @param owner Address of the owner of the campaign
    /// @param manager Address of the manager of the campaign
    event CampaignCreated(address indexed campaign, address owner, address manager);

    /// @notice Thrown when the sender is not the manager of the campaign
    error Unauthorized();

    /// @notice Modifier to check if the sender is the manager of the campaign
    ///
    /// @dev Reverts if the sender is not the manager of the campaign
    ///
    /// @param sender Address of the sender
    /// @param campaign Address of the campaign
    modifier onlyManager(address sender, address campaign) {
        if (sender != managers[campaign]) revert Unauthorized();
        _;
    }

    /// @notice Hooks constructor
    /// @param flywheel_ Address of the flywheel contract
    constructor(address flywheel_) CampaignHooks(flywheel_) {}

    /// @inheritdoc CampaignHooks
    function campaignURI(address campaign) external view override returns (string memory uri) {
        string memory uriPrefix = _uriPrefix[campaign];
        return bytes(uriPrefix).length > 0 ? string.concat(uriPrefix, LibString.toHexStringChecksummed(campaign)) : "";
    }

    /// @inheritdoc CampaignHooks
    function _onCreateCampaign(address campaign, uint256 nonce, bytes calldata hookData) internal virtual override {
        (address owner, address manager, string memory uriPrefix) = abi.decode(hookData, (address, address, string));
        owners[campaign] = owner;
        managers[campaign] = manager;
        _uriPrefix[campaign] = uriPrefix;
        emit CampaignCreated(campaign, owner, manager);
    }

    /// @inheritdoc CampaignHooks
    function _onSend(address sender, address campaign, address token, bytes calldata hookData)
        internal
        virtual
        override
        onlyManager(sender, campaign)
        returns (Flywheel.Payout[] memory payouts, Flywheel.Distribution[] memory fees, bool sendFeesNow)
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
        uint256 count = payouts.length;
        allocations = new Flywheel.Allocation[](count);
        for (uint256 i = 0; i < count; i++) {
            allocations[i] = Flywheel.Allocation({
                key: bytes32(bytes20(payouts[i].recipient)), amount: payouts[i].amount, extraData: payouts[i].extraData
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
        uint256 count = payouts.length;
        allocations = new Flywheel.Allocation[](count);
        for (uint256 i = 0; i < count; i++) {
            allocations[i] = Flywheel.Allocation({
                key: bytes32(bytes20(payouts[i].recipient)), amount: payouts[i].amount, extraData: payouts[i].extraData
            });
        }
    }

    /// @inheritdoc CampaignHooks
    function _onDistribute(address sender, address campaign, address token, bytes calldata hookData)
        internal
        virtual
        override
        onlyManager(sender, campaign)
        returns (Flywheel.Distribution[] memory distributions, Flywheel.Distribution[] memory fees, bool sendFeesNow)
    {
        Flywheel.Payout[] memory payouts = abi.decode(hookData, (Flywheel.Payout[]));
        uint256 count = payouts.length;
        distributions = new Flywheel.Distribution[](count);
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
        if (hookData.length > 0) _uriPrefix[campaign] = string(hookData);
    }
}
