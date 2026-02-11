// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {BuilderCodes} from "builder-codes/BuilderCodes.sol";
import {LibString} from "solady/utils/LibString.sol";

import {CampaignHooks} from "../CampaignHooks.sol";
import {Constants} from "../Constants.sol";
import {Flywheel} from "../Flywheel.sol";

/// @title BridgeReferralFees
///
/// @notice This contract is used to configure bridge referral fees with Base builder codes. It is expected to be used in
///         conjunction with the BuilderCodes contract that manages codes registration. Once registered, this contract
///         allows the builder to start receiving referral fees for each usage of the code during a bridge operation that
///         involves a transfer of tokens.
contract BridgeReferralFees is CampaignHooks {
    /// @notice Address of the BuilderCodes contract
    BuilderCodes public immutable BUILDER_CODES;

    /// @notice Maximum fee basis points, capped at ~2.5% by uint8 size
    uint8 public immutable MAX_FEE_BASIS_POINTS;

    /// @notice Address of the metadata manager
    address public immutable METADATA_MANAGER;

    /// @notice URI prefix for the campaign
    string public uriPrefix;

    /// @notice Error thrown to enforce only one campaign can be initialized
    error InvalidCampaignInitialization();

    /// @notice Error thrown when the caller is not authorized
    error Unauthorized();

    /// @notice BridgeReferralFees constructor
    ///
    /// @param flywheel Address of the flywheel contract
    /// @param builderCodes Address of the BuilderCodes contract
    /// @param maxFeeBasisPoints Maximum fee basis points
    /// @param metadataManager Address of the metadata manager
    /// @param uriPrefix_ URI prefix for the campaign
    constructor(
        address flywheel,
        address builderCodes,
        uint8 maxFeeBasisPoints,
        address metadataManager,
        string memory uriPrefix_
    ) CampaignHooks(flywheel) {
        BUILDER_CODES = BuilderCodes(builderCodes);
        MAX_FEE_BASIS_POINTS = maxFeeBasisPoints;
        METADATA_MANAGER = metadataManager;
        uriPrefix = uriPrefix_;
    }

    /// @inheritdoc CampaignHooks
    function campaignURI(address campaign) external view override returns (string memory uri) {
        return bytes(uriPrefix).length > 0 ? string.concat(uriPrefix, LibString.toHexStringChecksummed(campaign)) : "";
    }

    /// @inheritdoc CampaignHooks
    function _onCreateCampaign(address campaign, uint256 nonce, bytes calldata hookData) internal pure override {
        if (nonce != 0 || hookData.length > 0) revert InvalidCampaignInitialization();
    }

    /// @inheritdoc CampaignHooks
    /// @dev User can receive new funds sent into the campaign minus an optional fee for the referring builder code
    function _onSend(address sender, address campaign, address token, bytes calldata hookData)
        internal
        view
        override
        returns (Flywheel.Payout[] memory payouts, Flywheel.Distribution[] memory fees, bool sendFeesNow)
    {
        (address user, string memory code, uint8 feeBps) = abi.decode(hookData, (address, string, uint8));

        // Calculate bridged amount as current balance minus total fees allocated and not yet sent
        uint256 bridgedAmount = token == Constants.NATIVE_TOKEN ? campaign.balance : IERC20(token).balanceOf(campaign);
        bridgedAmount -= FLYWHEEL.totalAllocatedFees(campaign, token);

        // Set feeBps to MAX_FEE_BASIS_POINTS if feeBps exceeds MAX_FEE_BASIS_POINTS
        feeBps = feeBps > MAX_FEE_BASIS_POINTS ? MAX_FEE_BASIS_POINTS : feeBps;

        // Determine fallback key and payout address for builder code, zero-ing fees if failed to process
        (bool success, bytes32 fallbackKey, address payoutAddress) = _processBuilderCode(code);
        if (!success) feeBps = 0;

        // Prepare payout
        uint256 feeAmount = _safePercent(bridgedAmount, feeBps);
        payouts = new Flywheel.Payout[](1);
        payouts[0] = Flywheel.Payout({
            recipient: user,
            amount: bridgedAmount - feeAmount,
            extraData: abi.encode(code, feeAmount)
        });

        // Prepare fee if applicable
        if (feeAmount > 0) {
            sendFeesNow = true;
            fees = new Flywheel.Distribution[](1);
            fees[0] = Flywheel.Distribution({
                key: fallbackKey, // allow fee send to fallback to builder code
                recipient: payoutAddress, // if payoutAddress misconfigured, builder loses their fee
                amount: feeAmount,
                extraData: ""
            });
        }
    }

    /// @inheritdoc CampaignHooks
    ///
    /// @dev Will only need to use this function if the initial fee send fails
    function _onDistributeFees(address sender, address campaign, address token, bytes calldata hookData)
        internal
        view
        override
        returns (Flywheel.Distribution[] memory distributions)
    {
        // Determine key and payout address for builder code, zero-ing fees if failed to process
        (bool success, bytes32 fallbackKey, address payoutAddress) = _processBuilderCode(string(hookData));
        if (!success) return distributions;

        distributions = new Flywheel.Distribution[](1);
        distributions[0] = Flywheel.Distribution({
            key: fallbackKey,
            recipient: payoutAddress,
            amount: FLYWHEEL.allocatedFee(campaign, token, fallbackKey),
            extraData: ""
        });
    }

    /// @inheritdoc CampaignHooks
    function _onWithdrawFunds(address sender, address campaign, address token, bytes calldata hookData)
        internal
        pure
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
    ) internal pure override {
        // This is a perpetual campaign, so it should always be active
        // Campaigns are created as INACTIVE, so still need to let someone turn it on
        if (newStatus != Flywheel.CampaignStatus.ACTIVE) revert Flywheel.InvalidCampaignStatus();
    }

    /// @inheritdoc CampaignHooks
    function _onUpdateMetadata(address sender, address, bytes calldata hookData) internal override {
        if (sender != METADATA_MANAGER) revert Unauthorized();
        if (hookData.length > 0) uriPrefix = string(hookData);
    }

    /// @notice Processes a builder code and returns the key and payout address
    ///
    /// @param code Builder code
    ///
    /// @dev Wraps all calls to BuilderCodes in a try/catch to handle errors gracefully.
    /// @dev Expected errors are if the code is not valid or registered.
    ///
    /// @return success True if the code is valid and registered
    /// @return fallbackKey The fallback key to allocate fees to if fee distribution fails
    /// @return payoutAddress The payout address for the builder code
    function _processBuilderCode(string memory code)
        internal
        view
        returns (bool success, bytes32 fallbackKey, address payoutAddress)
    {
        // Convert code to token ID for constant-size fallback key
        try BUILDER_CODES.toTokenId(code) returns (uint256 tokenId) {
            // Fetch payout address for token ID
            try BUILDER_CODES.payoutAddress(tokenId) returns (address addr) {
                return (true, bytes32(tokenId), addr);
            } catch {
                return (false, bytes32(0), address(0));
            }
        } catch {
            return (false, bytes32(0), address(0));
        }
    }

    /// @notice Calculates a percentage of an amount safely, avoiding overflow
    ///
    /// @param amount The amount to calculate the percentage of
    /// @param basisPoints The basis points to calculate the percentage of
    ///
    /// @return value The percentage of the amount
    function _safePercent(uint256 amount, uint8 basisPoints) internal pure returns (uint256 value) {
        return (amount / 1e4) * basisPoints + ((amount % 1e4) * basisPoints) / 1e4;
    }
}
