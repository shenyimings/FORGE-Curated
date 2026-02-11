// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Flywheel} from "./Flywheel.sol";

/// @title CampaignHooks
///
/// @notice Abstract contract for campaign hooks with sane defaults for core operations
///
/// @author Coinbase (https://github.com/base/flywheel)
abstract contract CampaignHooks {
    /// @notice Flywheel contract address
    Flywheel public immutable FLYWHEEL;

    /// @notice Thrown when a function is not supported
    error Unsupported();

    /// @notice Modifier to restrict function access to Flywheel only
    modifier onlyFlywheel() {
        require(msg.sender == address(FLYWHEEL));
        _;
    }

    /// @notice Constructor for CampaignHooks
    ///
    /// @param flywheel Address of the Flywheel contract
    constructor(address flywheel) {
        FLYWHEEL = Flywheel(flywheel);
    }

    /// @notice Create a campaign
    ///
    /// @dev Only callable by the Flywheel contract
    ///
    /// @param campaign Address of the campaign
    /// @param nonce Nonce used to create the campaign
    /// @param hookData Data for the campaign hook
    function onCreateCampaign(address campaign, uint256 nonce, bytes calldata hookData) external onlyFlywheel {
        _onCreateCampaign(campaign, nonce, hookData);
    }

    /// @notice Processes immediate payouts for a campaign
    ///
    /// @dev Only callable by the Flywheel contract
    ///
    /// @param sender Address of the sender
    /// @param campaign Address of the campaign
    /// @param token Address of the token to be sent
    /// @param hookData Data for the campaign hook
    ///
    /// @return payouts Array of payouts to send
    /// @return fees Array of fees to send or allocate
    /// @return sendFeesNow Flag to send fees now
    function onSend(address sender, address campaign, address token, bytes calldata hookData)
        external
        onlyFlywheel
        returns (Flywheel.Payout[] memory payouts, Flywheel.Distribution[] memory fees, bool sendFeesNow)
    {
        return _onSend(sender, campaign, token, hookData);
    }

    /// @notice Allocate payouts to a key for a campaign
    ///
    /// @dev Only callable by the Flywheel contract
    ///
    /// @param sender Address of the sender
    /// @param campaign Address of the campaign
    /// @param token Address of the token to allocate
    /// @param hookData Data for the campaign hook
    ///
    /// @return allocations Array of allocations to allocate
    function onAllocate(address sender, address campaign, address token, bytes calldata hookData)
        external
        onlyFlywheel
        returns (Flywheel.Allocation[] memory allocations)
    {
        return _onAllocate(sender, campaign, token, hookData);
    }

    /// @notice Deallocate payouts from a key for a campaign
    ///
    /// @dev Only callable by the Flywheel contract
    ///
    /// @param sender Address of the sender
    /// @param campaign Address of the campaign
    /// @param token Address of the token to deallocate from the key
    /// @param hookData Data for the campaign hook
    ///
    /// @return allocations Array of allocations to deallocate
    function onDeallocate(address sender, address campaign, address token, bytes calldata hookData)
        external
        onlyFlywheel
        returns (Flywheel.Allocation[] memory allocations)
    {
        return _onDeallocate(sender, campaign, token, hookData);
    }

    /// @notice Distribute payouts from a key for a campaign
    ///
    /// @dev Only callable by the Flywheel contract
    ///
    /// @param sender Address of the sender
    /// @param campaign Address of the campaign
    /// @param token Address of the token to distribute
    /// @param hookData Data for the campaign hook
    ///
    /// @return distributions Array of distributions
    /// @return fees Array of fees to send or allocate
    /// @return sendFeesNow Flag to send fees now
    function onDistribute(address sender, address campaign, address token, bytes calldata hookData)
        external
        onlyFlywheel
        returns (Flywheel.Distribution[] memory distributions, Flywheel.Distribution[] memory fees, bool sendFeesNow)
    {
        return _onDistribute(sender, campaign, token, hookData);
    }

    /// @notice Distribute fees for a campaign
    ///
    /// @dev Only callable by the Flywheel contract
    ///
    /// @param sender Address of the sender
    /// @param campaign Address of the campaign
    /// @param token Address of the token to distribute
    /// @param hookData Data for the campaign hook
    ///
    /// @return distributions Array of distributions
    function onDistributeFees(address sender, address campaign, address token, bytes calldata hookData)
        external
        onlyFlywheel
        returns (Flywheel.Distribution[] memory distributions)
    {
        return _onDistributeFees(sender, campaign, token, hookData);
    }

    /// @notice Withdraw funding from a campaign
    ///
    /// @dev Only callable by the Flywheel contract
    ///
    /// @param sender Address of the sender
    /// @param campaign Address of the campaign
    /// @param token Address of the token to withdraw
    /// @param hookData Data for the campaign hook
    ///
    /// @return payout The token amount and recipient to withdraw
    function onWithdrawFunds(address sender, address campaign, address token, bytes calldata hookData)
        external
        onlyFlywheel
        returns (Flywheel.Payout memory payout)
    {
        return _onWithdrawFunds(sender, campaign, token, hookData);
    }

    /// @notice Update the campaign status
    ///
    /// @dev Only callable by the Flywheel contract
    ///
    /// @param campaign Address of the campaign
    /// @param oldStatus Old status of the campaign
    /// @param newStatus New status of the campaign
    /// @param hookData Data for the campaign hook
    function onUpdateStatus(
        address sender,
        address campaign,
        Flywheel.CampaignStatus oldStatus,
        Flywheel.CampaignStatus newStatus,
        bytes calldata hookData
    ) external onlyFlywheel {
        _onUpdateStatus(sender, campaign, oldStatus, newStatus, hookData);
    }

    /// @notice Update the metadata for a campaign
    ///
    /// @dev Only callable by the Flywheel contract
    ///
    /// @param sender Address of the sender
    /// @param campaign Address of the campaign
    /// @param hookData Data for the campaign hook
    function onUpdateMetadata(address sender, address campaign, bytes calldata hookData) external onlyFlywheel {
        _onUpdateMetadata(sender, campaign, hookData);
    }

    /// @notice Returns the URI for a campaign
    ///
    /// @param campaign Address of the campaign
    /// @return uri The URI for the campaign
    function campaignURI(address campaign) external view virtual returns (string memory uri);

    /// @notice Create a campaign
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
    /// @return payouts Array of payouts to send
    /// @return fees Array of fees to send or allocate
    /// @return sendFeesNow Flag to send fees now
    function _onSend(address sender, address campaign, address token, bytes calldata hookData)
        internal
        virtual
        returns (Flywheel.Payout[] memory payouts, Flywheel.Distribution[] memory fees, bool sendFeesNow)
    {
        revert Unsupported();
    }

    /// @notice Allocate payouts to a key for a campaign
    ///
    /// @param sender Address of the sender
    /// @param campaign Address of the campaign
    /// @param token Address of the token to allocate
    /// @param hookData Data for the campaign hook
    ///
    /// @return allocations Array of allocations to allocate
    function _onAllocate(address sender, address campaign, address token, bytes calldata hookData)
        internal
        virtual
        returns (Flywheel.Allocation[] memory allocations)
    {
        revert Unsupported();
    }

    /// @notice Deallocate payouts from a key for a campaign
    ///
    /// @param sender Address of the sender
    /// @param campaign Address of the campaign
    /// @param token Address of the token to deallocate from the key
    /// @param hookData Data for the campaign hook
    ///
    /// @return allocations Array of allocations to deallocate
    function _onDeallocate(address sender, address campaign, address token, bytes calldata hookData)
        internal
        virtual
        returns (Flywheel.Allocation[] memory allocations)
    {
        revert Unsupported();
    }

    /// @notice Distribute payouts from a key for a campaign
    ///
    /// @param sender Address of the sender
    /// @param campaign Address of the campaign
    /// @param token Address of the token to distribute
    /// @param hookData Data for the campaign hook
    ///
    /// @return distributions Array of distributions
    /// @return fees Array of fees to send or allocate
    /// @return sendFeesNow Flag to send fees now
    function _onDistribute(address sender, address campaign, address token, bytes calldata hookData)
        internal
        virtual
        returns (Flywheel.Distribution[] memory distributions, Flywheel.Distribution[] memory fees, bool sendFeesNow)
    {
        revert Unsupported();
    }

    /// @notice Distribute fees for a campaign
    ///
    /// @param sender Address of the sender
    /// @param campaign Address of the campaign
    /// @param token Address of the token to distribute
    /// @param hookData Data for the campaign hook
    ///
    /// @return distributions Array of distributions
    function _onDistributeFees(address sender, address campaign, address token, bytes calldata hookData)
        internal
        virtual
        returns (Flywheel.Distribution[] memory distributions)
    {
        revert Unsupported();
    }

    /// @notice Withdraw funding from a campaign
    ///
    /// @dev Only callable by the Flywheel contract
    ///
    /// @param sender Address of the sender
    /// @param campaign Address of the campaign
    /// @param token Address of the token to withdraw
    /// @param hookData Data for the campaign hook
    ///
    /// @return payout The token amount and recipient to withdraw
    function _onWithdrawFunds(address sender, address campaign, address token, bytes calldata hookData)
        internal
        virtual
        returns (Flywheel.Payout memory payout);

    /// @notice Update the campaign status
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

    /// @notice Update the metadata for a campaign
    ///
    /// @param sender Address of the sender
    /// @param campaign Address of the campaign
    /// @param hookData Data for the campaign hook
    function _onUpdateMetadata(address sender, address campaign, bytes calldata hookData) internal virtual;
}
