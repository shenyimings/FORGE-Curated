// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {CampaignHooks} from "../CampaignHooks.sol";
import {Flywheel} from "../Flywheel.sol";
import {BuilderCodes} from "../BuilderCodes.sol";

/// @title AdConversion
///
/// @notice Attribution hook for processing ad conversions
///
/// @dev Handles both onchain and offchain conversion events
///
/// @author Coinbase
contract AdConversion is CampaignHooks {
    // Conversion configuration structure
    struct ConversionConfig {
        /// @dev Whether the conversion config is active
        bool isActive;
        /// @dev Whether the conversion event is onchain
        bool isEventOnchain;
        /// @dev URI to extra metadata for offchain events
        string metadataURI;
    }

    // Input structure for creating conversion configs (without isActive)
    struct ConversionConfigInput {
        /// @dev Whether the conversion event is onchain
        bool isEventOnchain;
        /// @dev URI to extra metadata for offchain events
        string metadataURI;
    }

    /// @notice Attribution structure containing payout and conversion data
    struct Attribution {
        /// @dev The conversion data
        Conversion conversion;
        /// @dev Empty bytes if offchain conversion, encoded log data if onchain
        bytes logBytes;
    }

    /// @notice Conversion data structure
    struct Conversion {
        /// @dev Unique identifier for the conversion event
        bytes16 eventId;
        /// @dev Click identifier
        string clickId;
        /// @dev Configuration ID for the conversion (0 = no config/unregistered)
        uint16 configId;
        /// @dev Referral code
        string publisherRefCode;
        /// @dev Timestamp of the conversion
        uint32 timestamp;
        /// @dev Recipient address for the conversion, zero address implies using the referral code registry to get the payout address
        address payoutRecipient;
        /// @dev Amount of the payout for this conversion
        uint256 payoutAmount;
    }

    /// @notice Structure for recording onchain attribution events
    struct Log {
        /// @dev Chain ID where the transaction occurred
        uint256 chainId;
        /// @dev Transaction hash where the conversion occurred
        bytes32 transactionHash;
        /// @dev Index of the event log in the transaction
        uint256 index;
    }

    /// @notice Structure for recording finalization information
    struct CampaignState {
        /// @dev Address of the advertiser
        address advertiser;
        /// @dev Whether this campaign has a publisher allowlist
        bool hasAllowlist;
        /// @dev Attribution provider fee in basis points, cached at campaign creation
        uint16 attributionProviderFeeBps;
        /// @dev Address of the attribution provider
        address attributionProvider;
        /// @dev Duration for attribution deadline specific to this campaign
        uint48 attributionWindow;
        /// @dev Timestamp when finalization can occur
        uint48 attributionDeadline;
    }

    /// @notice Maximum basis points
    uint16 public constant MAX_BPS = 10_000;

    /// @notice Maximum number of conversion configs per campaign (65535 since we use uint16, IDs are 1-indexed)
    uint16 public constant MAX_CONVERSION_CONFIGS = type(uint16).max;

    /// @notice Address of the publisher registry contract
    BuilderCodes public immutable publisherCodesRegistry;

    /// @notice Mapping of campaign addresses to their URI
    mapping(address campaign => string uri) public override campaignURI;

    /// @notice Mapping of campaign addresses to finalization information
    mapping(address campaign => CampaignState) public state;

    /// @notice Mapping from campaign to allowed publisher ref codes
    mapping(address campaign => mapping(string publisherRefCode => bool allowed)) public allowedPublishers;

    /// @notice Mapping from campaign to conversion configs by config ID
    mapping(address campaign => mapping(uint16 configId => ConversionConfig)) public conversionConfigs;

    /// @notice Mapping from campaign to number of conversion configs
    mapping(address campaign => uint16) public conversionConfigCount;

    /// @notice Emitted when an offchain attribution event occurred
    ///
    /// @param campaign Address of the campaign
    /// @param isPublisherPayout True if original payout address was zero (publisher payout via registry)
    /// @param conversion The conversion data
    event OffchainConversionProcessed(address indexed campaign, bool isPublisherPayout, Conversion conversion);

    /// @notice Emitted when an onchain attribution event occurred
    ///
    /// @param campaign Address of the campaign
    /// @param isPublisherPayout True if original payout address was zero (publisher payout via registry)
    /// @param conversion The conversion data
    /// @param log The onchain log data
    event OnchainConversionProcessed(address indexed campaign, bool isPublisherPayout, Conversion conversion, Log log);

    /// @notice Emitted when attribution deadline is updated
    ///
    /// @param campaign Address of the campaign
    /// @param deadline The new deadline
    event AttributionDeadlineUpdated(address indexed campaign, uint48 deadline);

    /// @notice Emitted when a new conversion config is added to a campaign
    event ConversionConfigAdded(address indexed campaign, uint16 indexed configId, ConversionConfig config);

    /// @notice Emitted when a conversion config is disabled
    event ConversionConfigStatusChanged(address indexed campaign, uint16 indexed configId, bool isActive);

    /// @notice Emitted when a publisher is added to campaign allowlist
    event PublisherAddedToAllowlist(address indexed campaign, string publisherRefCode);

    /// @notice Emitted when an ad campaign is created
    ///
    /// @param campaign Address of the campaign
    /// @param attributionProvider Address of the attribution provider
    /// @param advertiser Address of the advertiser
    /// @param uri Campaign URI
    /// @param attributionWindow Duration for attribution deadline in seconds
    event AdCampaignCreated(
        address indexed campaign, address attributionProvider, address advertiser, string uri, uint48 attributionWindow
    );

    /// @notice Error thrown when an unauthorized action is attempted
    error Unauthorized();

    /// @notice Emitted when an invalid fee BPS is provided
    ///
    /// @param feeBps The invalid fee BPS
    error InvalidFeeBps(uint16 feeBps);

    /// @notice Error thrown when referral code is invalid
    error InvalidPublisherRefCode();

    /// @notice Error thrown when referral code is not in allowlist
    error PublisherNotAllowed();

    /// @notice Error thrown when conversion config ID is invalid
    error InvalidConversionConfigId();

    /// @notice Error thrown when conversion config is disabled
    error ConversionConfigDisabled();

    /// @notice Error thrown when conversion type doesn't match config
    error InvalidConversionType();

    /// @notice Error thrown when trying to add too many conversion configs
    error TooManyConversionConfigs();

    /// @notice Error thrown when attribution deadline duration is invalid (if non-zero, must be in days precision)
    ///
    /// @param duration The invalid duration
    error InvalidAttributionWindow(uint48 duration);

    /// @notice Error thrown when an invalid address is provided
    error ZeroAddress();

    /// @notice Constructor for ConversionAttestation
    ///
    /// @param protocol_ Address of the protocol contract
    /// @param owner_ Address of the contract owner
    /// @param publisherCodesRegistry_ Address of the referral code registry contract
    constructor(address protocol_, address owner_, address publisherCodesRegistry_) CampaignHooks(protocol_) {
        if (publisherCodesRegistry_ == address(0)) revert ZeroAddress();

        publisherCodesRegistry = BuilderCodes(publisherCodesRegistry_);
    }

    /// @inheritdoc CampaignHooks
    function _onCreateCampaign(address campaign, uint256 nonce, bytes calldata hookData) internal override {
        (
            address attributionProvider,
            address advertiser,
            string memory uri,
            string[] memory allowedPublisherRefCodes,
            ConversionConfigInput[] memory configs,
            uint48 campaignAttributionWindow,
            uint16 attributionProviderFeeBps
        ) = abi.decode(hookData, (address, address, string, string[], ConversionConfigInput[], uint48, uint16));

        // Validate attribution deadline duration (if non-zero, must be in days precision)
        if (campaignAttributionWindow % 1 days != 0) revert InvalidAttributionWindow(campaignAttributionWindow);

        // Validate attribution window is between 0 and 6 months (180 days)
        if (campaignAttributionWindow > 180 days) revert InvalidAttributionWindow(campaignAttributionWindow);

        // Validate attribution provider fee
        if (attributionProviderFeeBps > MAX_BPS) revert InvalidFeeBps(attributionProviderFeeBps);

        bool hasAllowlist = allowedPublisherRefCodes.length > 0;

        // Store campaign state
        state[campaign] = CampaignState({
            attributionProvider: attributionProvider,
            advertiser: advertiser,
            attributionDeadline: 0,
            attributionWindow: campaignAttributionWindow,
            hasAllowlist: hasAllowlist,
            attributionProviderFeeBps: attributionProviderFeeBps
        });
        campaignURI[campaign] = uri;

        // Set up allowed publishers mapping if allowlist exists
        if (hasAllowlist) {
            uint256 publisherCount = allowedPublisherRefCodes.length;
            for (uint256 i = 0; i < publisherCount; i++) {
                allowedPublishers[campaign][allowedPublisherRefCodes[i]] = true;
                emit PublisherAddedToAllowlist(campaign, allowedPublisherRefCodes[i]);
            }
        }

        // Store conversion configs
        conversionConfigCount[campaign] = uint16(configs.length);
        uint256 count = configs.length;
        for (uint16 i = 0; i < count; i++) {
            uint16 configId = i + 1;
            // Always set isActive to true for new configs
            ConversionConfig memory activeConfig = ConversionConfig({
                isActive: true,
                isEventOnchain: configs[i].isEventOnchain,
                metadataURI: configs[i].metadataURI
            });
            conversionConfigs[campaign][configId] = activeConfig;
            emit ConversionConfigAdded(campaign, configId, activeConfig);
        }

        // Emit campaign creation event with all decoded data
        emit AdCampaignCreated(campaign, attributionProvider, advertiser, uri, campaignAttributionWindow);
    }

    /// @inheritdoc CampaignHooks
    function _onSend(address attributionProvider, address campaign, address payoutToken, bytes calldata hookData)
        internal
        override
        returns (
            Flywheel.Payout[] memory payouts,
            Flywheel.Payout[] memory, /*immediateFees*/
            Flywheel.Allocation[] memory delayedFees
        )
    {
        // Validate that the caller is the authorized attribution provider for this campaign
        if (attributionProvider != state[campaign].attributionProvider) revert Unauthorized();

        // Get the fee from the cached campaign state
        uint16 feeBps = state[campaign].attributionProviderFeeBps;

        // Decode only the attributions from hookData
        Attribution[] memory attributions = abi.decode(hookData, (Attribution[]));

        // Arrays to track unique recipients and their accumulated amounts
        address[] memory recipients = new address[](attributions.length);
        uint256[] memory amounts = new uint256[](attributions.length);
        uint256 uniqueCount = 0;
        uint256 feeAmount = 0;

        // Loop over attributions, deducting attribution fee from payout amount and emitting appropriate events
        uint256 count = attributions.length;
        for (uint256 i = 0; i < count; i++) {
            // Validate referral code exists in the registry
            string memory publisherRefCode = attributions[i].conversion.publisherRefCode;
            if (bytes(publisherRefCode).length != 0 && !publisherCodesRegistry.isRegistered(publisherRefCode)) {
                revert InvalidPublisherRefCode();
            }

            // Check if referral code is in allowlist (if allowlist exists)
            if (state[campaign].hasAllowlist) {
                if (bytes(publisherRefCode).length != 0 && !allowedPublishers[campaign][publisherRefCode]) {
                    revert PublisherNotAllowed();
                }
            }

            // Validate conversion config (if configId is not 0)
            uint16 configId = attributions[i].conversion.configId;
            bytes memory logBytes = attributions[i].logBytes;

            // Validating that the config exists
            if (configId != 0) {
                if (configId > conversionConfigCount[campaign]) {
                    revert InvalidConversionConfigId();
                }

                ConversionConfig memory config = conversionConfigs[campaign][configId];

                // Validate that the conversion type matches the config
                if (config.isEventOnchain && logBytes.length == 0) revert InvalidConversionType();
                if (!config.isEventOnchain && logBytes.length > 0) revert InvalidConversionType();
            }

            address payoutAddress = attributions[i].conversion.payoutRecipient;

            // Determine if attribution was for a publisher (original payout address was zero)
            bool isPublisherPayout = (payoutAddress == address(0));

            // If the recipient is the zero address, we use the referral code registry to get the payout address
            if (isPublisherPayout) {
                payoutAddress = publisherCodesRegistry.payoutAddress(publisherRefCode);
                attributions[i].conversion.payoutRecipient = payoutAddress;
            }

            // Deduct attribution fee from payout amount
            uint256 netAmount = attributions[i].conversion.payoutAmount;
            if (feeBps > 0) {
                uint256 attributionFee = (attributions[i].conversion.payoutAmount * feeBps) / MAX_BPS;
                feeAmount += attributionFee;
                netAmount -= attributionFee;
            }

            // Find if this payoutAddress already exists in our tracking arrays
            bool found = false;
            for (uint256 j = 0; j < uniqueCount; j++) {
                if (recipients[j] == payoutAddress) {
                    amounts[j] += netAmount;
                    found = true;
                    break;
                }
            }

            // If not found, add as new recipient
            if (!found && netAmount > 0) {
                recipients[uniqueCount] = payoutAddress;
                amounts[uniqueCount] = netAmount;
                uniqueCount++;
            }

            // Emit onchain conversion if logBytes is present, else emit offchain conversion
            Conversion memory conversion = attributions[i].conversion;

            if (logBytes.length > 0) {
                emit OnchainConversionProcessed(campaign, isPublisherPayout, conversion, abi.decode(logBytes, (Log)));
            } else {
                emit OffchainConversionProcessed(campaign, isPublisherPayout, conversion);
            }
        }

        // Create the final payouts array with only unique recipients
        payouts = new Flywheel.Payout[](uniqueCount);
        for (uint256 i = 0; i < uniqueCount; i++) {
            payouts[i] = Flywheel.Payout({recipient: recipients[i], amount: amounts[i], extraData: ""});
        }

        // Add delayed fee for attribution provider to claim later
        if (feeAmount > 0) {
            delayedFees = new Flywheel.Allocation[](1);
            delayedFees[0] =
                Flywheel.Allocation({key: bytes32(bytes20(attributionProvider)), amount: feeAmount, extraData: ""});
        }
    }

    /// @inheritdoc CampaignHooks
    /// @dev Only advertiser allowed to withdraw funds on finalized campaigns
    function _onWithdrawFunds(address sender, address campaign, address token, bytes calldata hookData)
        internal
        override
        returns (Flywheel.Payout memory payout)
    {
        if (sender != state[campaign].advertiser) revert Unauthorized();
        if (flywheel.campaignStatus(campaign) != Flywheel.CampaignStatus.FINALIZED) revert Unauthorized();

        (address recipient, uint256 amount) = abi.decode(hookData, (address, uint256));
        return (Flywheel.Payout({recipient: recipient, amount: amount, extraData: ""}));
    }

    /// @inheritdoc CampaignHooks
    function _onDistributeFees(address sender, address campaign, address token, bytes calldata hookData)
        internal
        override
        returns (Flywheel.Distribution[] memory distributions)
    {
        if (sender != state[campaign].attributionProvider) revert Unauthorized();
        bytes32 key = bytes32(bytes20(sender));
        uint256 amount = flywheel.allocatedFee(campaign, token, key);
        address recipient = abi.decode(hookData, (address));

        distributions = new Flywheel.Distribution[](1);
        distributions[0] = Flywheel.Distribution({recipient: recipient, key: key, amount: amount, extraData: ""});
        return distributions;
    }

    /// @inheritdoc CampaignHooks
    function _onUpdateStatus(
        address sender,
        address campaign,
        Flywheel.CampaignStatus oldStatus,
        Flywheel.CampaignStatus newStatus,
        bytes calldata hookData
    ) internal override {
        address attributionProvider = state[campaign].attributionProvider;
        address advertiser = state[campaign].advertiser;

        // Only attribution provider and advertiser can update status
        if (sender != attributionProvider && sender != advertiser) {
            revert Unauthorized();
        }

        // Advertiser constraints from INACTIVE: only INACTIVE → FINALIZED allowed
        if (oldStatus == Flywheel.CampaignStatus.INACTIVE) {
            if (sender == advertiser && newStatus != Flywheel.CampaignStatus.FINALIZED) {
                revert Unauthorized();
            }
            // Attribution provider constraint: cannot do INACTIVE → FINALIZING/FINALIZED (fund recovery is advertiser-only)
            if (sender == attributionProvider && (newStatus != Flywheel.CampaignStatus.ACTIVE)) {
                revert Unauthorized();
            }
        }

        // Security restriction: No one can pause active campaigns (ACTIVE → INACTIVE)
        if (oldStatus == Flywheel.CampaignStatus.ACTIVE && newStatus == Flywheel.CampaignStatus.INACTIVE) {
            revert Unauthorized();
        }

        // Attribution window protection: Advertiser cannot bypass FINALIZING (ACTIVE → FINALIZED) but Attribution Provider can
        if (oldStatus == Flywheel.CampaignStatus.ACTIVE && newStatus == Flywheel.CampaignStatus.FINALIZED) {
            if (sender == advertiser) {
                revert Unauthorized();
            }
        }

        // Set attribution deadline when entering FINALIZING
        if (newStatus == Flywheel.CampaignStatus.FINALIZING) {
            state[campaign].attributionDeadline = uint48(block.timestamp) + state[campaign].attributionWindow;
            emit AttributionDeadlineUpdated(campaign, state[campaign].attributionDeadline);
        }

        // Attribution deadline enforcement for FINALIZING → FINALIZED for Advertiser
        if (oldStatus == Flywheel.CampaignStatus.FINALIZING && newStatus == Flywheel.CampaignStatus.FINALIZED) {
            if (sender == advertiser && state[campaign].attributionDeadline > block.timestamp) {
                revert Unauthorized();
            }
        }
    }

    /// @inheritdoc CampaignHooks
    function _onUpdateMetadata(address sender, address campaign, bytes calldata hookData) internal override {
        if (sender != state[campaign].attributionProvider && sender != state[campaign].advertiser) {
            revert Unauthorized();
        }
    }

    /// @notice Adds a referral code to the campaign allowlist
    /// @param campaign Address of the campaign
    /// @param publisherRefCode Referral code to add
    /// @dev Only advertiser can add referral codes to allowlist
    function addAllowedPublisherRefCode(address campaign, string memory publisherRefCode) external {
        if (msg.sender != state[campaign].advertiser) revert Unauthorized();

        // Validate referral code exists in registry
        if (!publisherCodesRegistry.isRegistered(publisherRefCode)) {
            revert InvalidPublisherRefCode();
        }

        // @notice: if the allowlist is not enabled during campaign creation, we revert
        if (!state[campaign].hasAllowlist) {
            revert Unauthorized();
        }

        // Check if already allowed to avoid redundant operations
        if (allowedPublishers[campaign][publisherRefCode]) {
            return; // Already allowed, no-op
        }

        // Add to mapping
        allowedPublishers[campaign][publisherRefCode] = true;
        emit PublisherAddedToAllowlist(campaign, publisherRefCode);
    }

    /// @notice Adds a new conversion config to an existing campaign
    /// @param campaign Address of the campaign
    /// @param config The conversion config input (without isActive)
    /// @dev Only advertiser can add conversion configs
    function addConversionConfig(address campaign, ConversionConfigInput memory config) external {
        if (msg.sender != state[campaign].advertiser) revert Unauthorized();

        uint16 currentCount = conversionConfigCount[campaign];
        if (currentCount >= type(uint16).max) revert TooManyConversionConfigs();

        // Add the new config - always set isActive to true
        uint16 newConfigId = currentCount + 1;
        ConversionConfig memory activeConfig =
            ConversionConfig({isActive: true, isEventOnchain: config.isEventOnchain, metadataURI: config.metadataURI});
        conversionConfigs[campaign][newConfigId] = activeConfig;
        conversionConfigCount[campaign] = newConfigId;

        emit ConversionConfigAdded(campaign, newConfigId, activeConfig);
    }

    /// @notice Disables a conversion config for a campaign
    /// @param campaign Address of the campaign
    /// @param configId The ID of the conversion config to disable
    /// @dev Only advertiser can disable conversion configs
    function disableConversionConfig(address campaign, uint16 configId) external {
        if (msg.sender != state[campaign].advertiser) revert Unauthorized();

        if (configId == 0 || configId > conversionConfigCount[campaign]) {
            revert InvalidConversionConfigId();
        }

        // Check if config is already disabled
        if (!conversionConfigs[campaign][configId].isActive) revert ConversionConfigDisabled();

        // Disable the config
        conversionConfigs[campaign][configId].isActive = false;

        emit ConversionConfigStatusChanged(campaign, configId, false);
    }

    /// @notice Checks if a campaign has a publisher allowlist
    /// @param campaign Address of the campaign
    /// @return True if the campaign has an allowlist
    function hasPublisherAllowlist(address campaign) external view returns (bool) {
        return state[campaign].hasAllowlist;
    }

    /// @notice Checks if a referral code is allowed for a campaign
    /// @param campaign Address of the campaign
    /// @param publisherRefCode Referral code to check
    /// @return True if the referral code is allowed (or if no allowlist exists)
    function isPublisherRefCodeAllowed(address campaign, string memory publisherRefCode) external view returns (bool) {
        // If no allowlist exists, all referral codes are allowed
        if (!state[campaign].hasAllowlist) {
            return true;
        }
        return allowedPublishers[campaign][publisherRefCode];
    }

    /// @notice Gets a conversion config for a campaign
    /// @param campaign Address of the campaign
    /// @param configId The ID of the conversion config
    /// @return The conversion config
    function getConversionConfig(address campaign, uint16 configId) external view returns (ConversionConfig memory) {
        if (configId == 0 || configId > conversionConfigCount[campaign]) {
            revert InvalidConversionConfigId();
        }
        return conversionConfigs[campaign][configId];
    }
}
