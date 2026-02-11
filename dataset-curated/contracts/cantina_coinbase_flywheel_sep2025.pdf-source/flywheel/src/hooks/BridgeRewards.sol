// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {BuilderCodes} from "../BuilderCodes.sol";
import {CampaignHooks} from "../CampaignHooks.sol";
import {Flywheel} from "../Flywheel.sol";

/// @title BridgeRewards
///
/// @notice This contract is used to configure bridge rewards for Base builder codes. It is expected to be used in
///         conjunction with the BuilderCodes contract that manages codes registration. Once registered, this contract
///         allows the builder to start receiving rewards for each usage of the code during a bridge operation that
///         involves a transfer of tokens.
contract BridgeRewards is CampaignHooks {
    /// @notice ERC-7528 address for native token
    address public constant NATIVE_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /// @notice Maximum fee basis points (2.00%)
    uint256 public constant MAX_FEE_BASIS_POINTS = 2_00;

    /// @notice Address of the BuilderCodes contract
    BuilderCodes public immutable builderCodes;

    /// @notice Metadata URI for the campaign
    string public metadataURI;

    /// @notice Error thrown to enforce only one campaign can be initialized
    error InvalidCampaignInitialization();

    /// @notice Error thrown when the balance is zero
    error ZeroAmount();

    /// @notice Error thrown when the fee basis points is too high
    error FeeBasisPointsTooHigh();

    /// @notice Error thrown when the builder code is not registered
    error BuilderCodeNotRegistered();

    /// @notice Hooks constructor
    ///
    /// @param flywheel_ Address of the flywheel contract
    constructor(address flywheel_, address builderCodes_, string memory metadataURI_) CampaignHooks(flywheel_) {
        builderCodes = BuilderCodes(builderCodes_);
        metadataURI = metadataURI_;
    }

    /// @inheritdoc CampaignHooks
    function campaignURI(address campaign) external view override returns (string memory uri) {
        return metadataURI;
    }

    /// @inheritdoc CampaignHooks
    function _onCreateCampaign(address campaign, uint256 nonce, bytes calldata hookData) internal override {
        if (nonce != 0 || hookData.length > 0) revert InvalidCampaignInitialization();
    }

    /// @inheritdoc CampaignHooks
    function _onSend(address sender, address campaign, address token, bytes calldata hookData)
        internal
        override
        returns (
            Flywheel.Payout[] memory payouts,
            Flywheel.Payout[] memory immediateFees,
            Flywheel.Allocation[] memory /*delayedFees*/
        )
    {
        (address user, bytes32 code, uint16 feeBps) = abi.decode(hookData, (address, bytes32, uint16));

        // Check balance is nonzero
        uint256 balance = token == NATIVE_TOKEN ? campaign.balance : IERC20(token).balanceOf(campaign);
        require(balance > 0, ZeroAmount());

        // Check builder code is registered
        require(builderCodes.ownerOf(uint256(code)) != address(0), BuilderCodeNotRegistered());

        // Compute fee amount
        require(feeBps <= MAX_FEE_BASIS_POINTS, FeeBasisPointsTooHigh());
        uint256 feeAmount = (balance * feeBps) / 1e4;

        // Prepare payout
        payouts = new Flywheel.Payout[](1);
        payouts[0] =
            Flywheel.Payout({recipient: user, amount: balance - feeAmount, extraData: abi.encode(code, feeAmount)});

        // Prepare fee if applicable
        if (feeAmount > 0) {
            immediateFees = new Flywheel.Payout[](1);
            immediateFees[0] = Flywheel.Payout({
                recipient: builderCodes.payoutAddress(uint256(code)), // if payoutAddress misconfigured, builder loses their fee
                amount: feeAmount,
                extraData: ""
            });
        }
    }

    /// @inheritdoc CampaignHooks
    function _onWithdrawFunds(address sender, address campaign, address token, bytes calldata hookData)
        internal
        override
        returns (Flywheel.Payout memory payout)
    {
        // Intended use is for funds to be sent into the campaign and atomically sent out to recipients
        // If tokens are sent into the campaign outside of this scope on accident, anyone can take them (no access control for `onSend` hook)
        // To keep the event feed clean for payouts/fees, we leave open the ability to withdraw funds directly
        // Those wishing to take accidental tokens left in the campaign should find this function easier
        payout = abi.decode(hookData, (Flywheel.Payout));
    }

    /// @inheritdoc CampaignHooks
    function _onUpdateStatus(
        address sender,
        address campaign,
        Flywheel.CampaignStatus oldStatus,
        Flywheel.CampaignStatus newStatus,
        bytes calldata hookData
    ) internal override {
        // This is a perpetual campaign, so it should always be active
        // Campaigns are created as INACTIVE, so still need to let someone turn it on
        if (newStatus != Flywheel.CampaignStatus.ACTIVE) revert Flywheel.InvalidCampaignStatus();
    }

    /// @inheritdoc CampaignHooks
    function _onUpdateMetadata(address sender, address campaign, bytes calldata hookData) internal override {
        // Anyone can prompt metadata cache updates
        // Even though metadataURI is fixed, its returned data may change over time
    }
}
