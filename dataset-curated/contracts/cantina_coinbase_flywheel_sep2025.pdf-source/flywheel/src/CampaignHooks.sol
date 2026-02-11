// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Flywheel} from "./Flywheel.sol";

/// @title CampaignHooks
///
/// @notice Abstract contract for campaign hooks that process campaign attributions
abstract contract CampaignHooks {
    /// @notice Address of the flywheel contract
    Flywheel public immutable flywheel;

    /// @notice Thrown when a function is not supported
    error Unsupported();

    /// @notice Modifier to restrict function access to flywheel only
    modifier onlyFlywheel() {
        require(msg.sender == address(flywheel));
        _;
    }

    /// @notice Constructor for CampaignHooks
    ///
    /// @param flywheel_ Address of the flywheel contract
    constructor(address flywheel_) {
        flywheel = Flywheel(flywheel_);
    }

    /// @notice Creates a campaign in the hook
    ///
    /// @param campaign Address of the campaign
    /// @param nonce Nonce used to create the campaign
    /// @param hookData Data for the campaign hook
    ///
    /// @dev Only callable by the flywheel contract
    function onCreateCampaign(address campaign, uint256 nonce, bytes calldata hookData) external onlyFlywheel {
        _onCreateCampaign(campaign, nonce, hookData);
    }

    /// @notice Processes immediate payouts for a campaign
    ///
    /// @param sender Address of the sender
    /// @param campaign Address of the campaign
    /// @param token Address of the token to be sent
    /// @param hookData Data for the campaign hook
    ///
    /// @return payouts Array of payouts to be sent
    /// @return immediateFees Array of fees to be send immediately
    /// @return delayedFees Array of fees to be allocated
    ///
    /// @dev Only callable by the flywheel contract
    function onSend(address sender, address campaign, address token, bytes calldata hookData)
        external
        onlyFlywheel
        returns (
            Flywheel.Payout[] memory payouts,
            Flywheel.Payout[] memory immediateFees,
            Flywheel.Allocation[] memory delayedFees
        )
    {
        return _onSend(sender, campaign, token, hookData);
    }

    /// @notice Processes attribution for a campaign
    ///
    /// @param sender Address of the sender
    /// @param campaign Address of the campaign
    /// @param token Address of the token to be distributed
    /// @param hookData Data for the campaign hook
    ///
    /// @return allocations Array of allocations to be distributed
    ///
    /// @dev Only callable by the flywheel contract
    function onAllocate(address sender, address campaign, address token, bytes calldata hookData)
        external
        onlyFlywheel
        returns (Flywheel.Allocation[] memory allocations)
    {
        return _onAllocate(sender, campaign, token, hookData);
    }

    /// @notice Deallocates allocated rewards from a key for a campaign
    ///
    /// @param sender Address of the sender
    /// @param campaign Address of the campaign
    /// @param token Address of the token to deallocate from the key
    /// @param hookData Data for the campaign hook
    ///
    /// @return allocations Array of allocations to be deallocated
    ///
    /// @dev Only callable by the flywheel contract
    function onDeallocate(address sender, address campaign, address token, bytes calldata hookData)
        external
        onlyFlywheel
        returns (Flywheel.Allocation[] memory allocations)
    {
        return _onDeallocate(sender, campaign, token, hookData);
    }

    /// @notice Distributes payouts for a campaign
    ///
    /// @param sender Address of the sender
    /// @param campaign Address of the campaign
    /// @param token Address of the token to be distributed
    /// @param hookData Data for the campaign hook
    ///
    /// @return distributions Array of distributions to be distributed
    /// @return immediateFees Array of fees to be sent immediately
    /// @return delayedFees Array of fees to be allocated
    ///
    /// @dev Only callable by the flywheel contract
    function onDistribute(address sender, address campaign, address token, bytes calldata hookData)
        external
        onlyFlywheel
        returns (
            Flywheel.Distribution[] memory distributions,
            Flywheel.Payout[] memory immediateFees,
            Flywheel.Allocation[] memory delayedFees
        )
    {
        return _onDistribute(sender, campaign, token, hookData);
    }

    /// @notice Distribute fees earned from a campaign
    ///
    /// @param sender Address of the sender
    /// @param campaign Address of the campaign
    /// @param token Address of the token to collect fees from
    /// @param hookData Data for the campaign hook
    ///
    /// @return distributions Array of distributions for the fees
    ///
    /// @dev Only callable by the flywheel contract
    function onDistributeFees(address sender, address campaign, address token, bytes calldata hookData)
        external
        onlyFlywheel
        returns (Flywheel.Distribution[] memory distributions)
    {
        return _onDistributeFees(sender, campaign, token, hookData);
    }

    /// @notice Allows sponsor to withdraw remaining tokens from a finalized campaign
    ///
    /// @param sender Address of the sender
    /// @param campaign Address of the campaign
    /// @param token Address of the token to withdraw
    /// @param hookData Data for the campaign hook
    ///
    /// @return payout The payout to be withdrawn
    ///
    /// @dev Only callable by the flywheel contract
    function onWithdrawFunds(address sender, address campaign, address token, bytes calldata hookData)
        external
        onlyFlywheel
        returns (Flywheel.Payout memory payout)
    {
        return _onWithdrawFunds(sender, campaign, token, hookData);
    }

    /// @notice Updates the campaign status
    ///
    /// @param campaign Address of the campaign
    /// @param oldStatus Old status of the campaign
    /// @param newStatus New status of the campaign
    /// @param hookData Data for the campaign hook
    ///
    /// @dev Only callable by the flywheel contract
    function onUpdateStatus(
        address sender,
        address campaign,
        Flywheel.CampaignStatus oldStatus,
        Flywheel.CampaignStatus newStatus,
        bytes calldata hookData
    ) external onlyFlywheel {
        _onUpdateStatus(sender, campaign, oldStatus, newStatus, hookData);
    }

    /// @notice Updates the metadata for a campaign
    ///
    /// @param sender Address of the sender
    /// @param campaign Address of the campaign
    /// @param hookData Data for the campaign hook
    ///
    /// @dev Only callable by the flywheel contract
    function onUpdateMetadata(address sender, address campaign, bytes calldata hookData) external onlyFlywheel {
        _onUpdateMetadata(sender, campaign, hookData);
    }

    /// @notice Returns the URI for a campaign
    ///
    /// @param campaign Address of the campaign
    /// @return uri The URI for the campaign
    function campaignURI(address campaign) external view virtual returns (string memory uri);

    /// @notice Creates a campaign in the hook
    ///
    /// @param campaign Address of the campaign
    /// @param nonce Nonce used to create the campaign
    /// @param hookData Data for the campaign hook
    function _onCreateCampaign(address campaign, uint256 nonce, bytes calldata hookData) internal virtual;

    /// @notice Processes immediate payouts for a campaign
    ///
    /// @param sender Address of the sender
    /// @param campaign Address of the campaign
    /// @param token Address of the token to be sent
    /// @param hookData Data for the campaign hook
    ///
    /// @return payouts Array of payouts to be sent
    /// @return immediateFees Array of fees to be send immediately
    /// @return delayedFees Array of fees to be allocated and distributed later
    function _onSend(address sender, address campaign, address token, bytes calldata hookData)
        internal
        virtual
        returns (
            Flywheel.Payout[] memory payouts,
            Flywheel.Payout[] memory immediateFees,
            Flywheel.Allocation[] memory delayedFees
        )
    {
        revert Unsupported();
    }

    /// @notice Processes attribution for a campaign
    ///
    /// @param sender Address of the sender
    /// @param campaign Address of the campaign
    /// @param token Address of the token to be distributed
    /// @param hookData Data for the campaign hook
    ///
    /// @return allocations Array of allocations to be distributed
    function _onAllocate(address sender, address campaign, address token, bytes calldata hookData)
        internal
        virtual
        returns (Flywheel.Allocation[] memory allocations)
    {
        revert Unsupported();
    }

    /// @notice Deallocates allocated rewards from a key for a campaign
    ///
    /// @param sender Address of the sender
    /// @param campaign Address of the campaign
    /// @param token Address of the token to deallocate from the key
    /// @param hookData Data for the campaign hook
    ///
    /// @return allocations Array of allocations to be deallocated
    function _onDeallocate(address sender, address campaign, address token, bytes calldata hookData)
        internal
        virtual
        returns (Flywheel.Allocation[] memory allocations)
    {
        revert Unsupported();
    }

    /// @notice Distributes payouts for a campaign
    ///
    /// @param sender Address of the sender
    /// @param campaign Address of the campaign
    /// @param token Address of the token to be distributed
    /// @param hookData Data for the campaign hook
    ///
    /// @return distributions Array of distributions to be distributed
    /// @return immediateFees Array of fees to be sent immediately
    /// @return delayedFees Array of fees to be allocated and distributed later
    function _onDistribute(address sender, address campaign, address token, bytes calldata hookData)
        internal
        virtual
        returns (
            Flywheel.Distribution[] memory distributions,
            Flywheel.Payout[] memory immediateFees,
            Flywheel.Allocation[] memory delayedFees
        )
    {
        revert Unsupported();
    }

    /// @notice Distribute fees earned from a campaign
    ///
    /// @param sender Address of the sender
    /// @param campaign Address of the campaign
    /// @param token Address of the token to collect fees from
    /// @param hookData Data for the campaign hook
    ///
    /// @return distributions Array of distributions for the fees
    function _onDistributeFees(address sender, address campaign, address token, bytes calldata hookData)
        internal
        virtual
        returns (Flywheel.Distribution[] memory distributions)
    {
        revert Unsupported();
    }

    /// @notice Allows sponsor to withdraw remaining tokens from a finalized campaign
    ///
    /// @param sender Address of the sender
    /// @param campaign Address of the campaign
    /// @param token Address of the token to withdraw
    /// @param hookData Data for the campaign hook
    ///
    /// @return payout The payout to be withdrawn
    function _onWithdrawFunds(address sender, address campaign, address token, bytes calldata hookData)
        internal
        virtual
        returns (Flywheel.Payout memory payout);

    /// @notice Updates the campaign status
    ///
    /// @param campaign Address of the campaign
    /// @param oldStatus Old status of the campaign
    /// @param newStatus New status of the campaign
    /// @param hookData Data for the campaign hook
    function _onUpdateStatus(
        address sender,
        address campaign,
        Flywheel.CampaignStatus oldStatus,
        Flywheel.CampaignStatus newStatus,
        bytes calldata hookData
    ) internal virtual;

    /// @notice Updates the metadata for a campaign
    ///
    /// @param sender Address of the sender
    /// @param campaign Address of the campaign
    /// @param hookData Data for the campaign hook
    function _onUpdateMetadata(address sender, address campaign, bytes calldata hookData) internal virtual;
}
