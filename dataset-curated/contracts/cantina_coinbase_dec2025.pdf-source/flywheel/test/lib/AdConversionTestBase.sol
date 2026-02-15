// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Test} from "forge-std/Test.sol";

import {PublisherSetupHelper, PublisherTestSetup} from "./PublisherSetupHelper.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

import {Flywheel} from "../../src/Flywheel.sol";
import {AdConversion} from "../../src/hooks/AdConversion.sol";
import {BuilderCodes} from "builder-codes/BuilderCodes.sol";

/// @notice Comprehensive test base for AdConversion hook testing
/// @dev Provides utilities for both unit and integration testing with clean setup/teardown
abstract contract AdConversionTestBase is PublisherTestSetup {
    // ========================================
    // CORE CONTRACTS
    // ========================================

    Flywheel public flywheel;
    BuilderCodes public builderCodes;
    AdConversion public adConversion;

    // ========================================
    // TEST ACTORS
    // ========================================

    address public admin = makeAddr("admin");
    address public registrarSigner = makeAddr("registrarSigner");

    // Campaign actors
    address public advertiser1 = makeAddr("advertiser1");
    address public advertiser2 = makeAddr("advertiser2");
    address public attributionProvider1 = makeAddr("attributionProvider1");
    address public attributionProvider2 = makeAddr("attributionProvider2");

    // Publisher actors
    address public publisher1 = makeAddr("publisher1");
    address public publisher2 = makeAddr("publisher2");
    address public publisher3 = makeAddr("publisher3");
    address public publisherPayout1 = makeAddr("publisherPayout1");
    address public publisherPayout2 = makeAddr("publisherPayout2");
    address public publisherPayout3 = makeAddr("publisherPayout3");

    // Utility actors
    address public unauthorizedUser = makeAddr("unauthorizedUser");
    address public randomRecipient = makeAddr("randomRecipient");
    address public burnAddress = makeAddr("burnAddress");

    // ========================================
    // TEST TOKENS
    // ========================================

    MockERC20 public tokenA;
    MockERC20 public tokenB;

    // ========================================
    // TEST CONSTANTS
    // ========================================

    // Publisher ref codes
    string public constant REF_CODE_1 = "pub1";
    string public constant REF_CODE_2 = "pub2";
    string public constant REF_CODE_3 = "pub3";
    string public constant UNREGISTERED_REF_CODE = "unregistered";
    string public constant EMPTY_REF_CODE = "";

    // Campaign constants
    uint256 public constant DEFAULT_CAMPAIGN_NONCE = 1;
    uint48 public constant DEFAULT_ATTRIBUTION_WINDOW = 7 days;
    uint16 public constant DEFAULT_FEE_BPS = 500; // 5%
    uint16 public constant ZERO_FEE_BPS = 0;
    uint16 public constant MAX_FEE_BPS = 10000; // 100%

    // Attribution constants (MockERC20 uses 6 decimals)
    uint256 public constant DEFAULT_ATTRIBUTION_AMOUNT = 100 * 1e6;
    uint256 public constant LARGE_ATTRIBUTION_AMOUNT = 1000000 * 1e6;
    uint256 public constant SMALL_ATTRIBUTION_AMOUNT = 1e3; // For rounding tests

    // Campaign funding (MockERC20 uses 6 decimals)
    uint256 public constant DEFAULT_CAMPAIGN_FUNDING = 10000 * 1e6;
    uint256 public constant LARGE_CAMPAIGN_FUNDING = 1000000 * 1e6;

    // Fuzzing bounds (constrained by MockERC20 balance of 1M tokens per holder, 6 decimals)
    uint256 public constant MIN_CAMPAIGN_FUNDING = 1000 * 1e6; // 1K tokens minimum
    uint256 public constant MAX_CAMPAIGN_FUNDING = 500000 * 1e6; // 500K tokens maximum (half of MockERC20 balance)
    uint256 public constant MIN_ATTRIBUTION_AMOUNT = 1 * 1e6; // 1 token minimum
    uint256 public constant MAX_ATTRIBUTION_AMOUNT = 50000 * 1e6; // 50K tokens maximum (fitting within funding limits)
    uint256 public constant MIN_FEE_BPS = 0; // 0% fee minimum
    uint16 public constant MAX_REASONABLE_FEE_BPS = MAX_FEE_BPS; // Flex full range of fees
    uint48 public constant MIN_ATTRIBUTION_WINDOW = 0; // No attribution window minimum
    uint48 public constant MAX_ATTRIBUTION_WINDOW = 180 days; // 180 days maximum

    // Fee distribution testing constants
    uint256 public constant NUM_MULTI_ATTRIBUTIONS = 3; // For tests with multiple attributions
    uint256 public constant MULTI_ATTRIBUTION_BASE_AMOUNT = MAX_ATTRIBUTION_AMOUNT / NUM_MULTI_ATTRIBUTIONS; // Ensure total fits in funding

    // ========================================
    // SETUP AND TEARDOWN
    // ========================================

    function setUp() public virtual {
        _deployContracts();
        _setupTokens();
        _registerPublishers();
        _labelAddresses();
    }

    function _deployContracts() internal {
        // Deploy Flywheel
        flywheel = new Flywheel();

        // Deploy BuilderCodes as upgradeable proxy
        BuilderCodes implementation = new BuilderCodes();
        bytes memory initData = abi.encodeWithSelector(
            BuilderCodes.initialize.selector, admin, registrarSigner, "https://api.flywheel.co/metadata/"
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        builderCodes = BuilderCodes(address(proxy));

        // Deploy AdConversion hook
        adConversion = new AdConversion(address(flywheel), address(builderCodes));
    }

    function _setupTokens() internal {
        // Create token holders for funding
        address[] memory tokenHolders = new address[](4);
        tokenHolders[0] = advertiser1;
        tokenHolders[1] = advertiser2;
        tokenHolders[2] = attributionProvider1;
        tokenHolders[3] = attributionProvider2;

        tokenA = new MockERC20(tokenHolders);
        tokenB = new MockERC20(tokenHolders);
    }

    function _registerPublishers() internal {
        vm.startPrank(registrarSigner);
        builderCodes.register(REF_CODE_1, publisher1, publisherPayout1);
        builderCodes.register(REF_CODE_2, publisher2, publisherPayout2);
        builderCodes.register(REF_CODE_3, publisher3, publisherPayout3);
        vm.stopPrank();
    }

    // ========================================
    // CAMPAIGN CREATION UTILITIES
    // ========================================

    /// @notice Creates a basic campaign with default parameters
    function createBasicCampaign() public returns (address campaign) {
        campaign = createCampaign(
            advertiser1,
            attributionProvider1,
            new string[](0), // No allowlist
            _createDefaultConfigs(),
            DEFAULT_ATTRIBUTION_WINDOW,
            DEFAULT_FEE_BPS
        );
    }

    /// @notice Creates a campaign with custom parameters
    function createCampaign(
        address advertiser,
        address attributionProvider,
        string[] memory allowedRefCodes,
        AdConversion.ConversionConfigInput[] memory configs,
        uint48 attributionWindow,
        uint16 feeBps
    ) public returns (address campaign) {
        bytes memory hookData = abi.encode(
            attributionProvider,
            advertiser,
            "https://campaign.example.com/metadata",
            allowedRefCodes,
            configs,
            attributionWindow,
            feeBps
        );

        campaign = flywheel.createCampaign(address(adConversion), DEFAULT_CAMPAIGN_NONCE, hookData);
    }

    /// @notice Creates a campaign with custom URI
    function createCampaignWithURI(
        address advertiser,
        address attributionProvider,
        string[] memory allowedRefCodes,
        AdConversion.ConversionConfigInput[] memory configs,
        uint48 attributionWindow,
        uint16 feeBps,
        string memory uri
    ) public returns (address campaign) {
        bytes memory hookData = abi.encode(
            attributionProvider, advertiser, uri, allowedRefCodes, configs, attributionWindow, feeBps
        );

        campaign = flywheel.createCampaign(address(adConversion), DEFAULT_CAMPAIGN_NONCE, hookData);
    }

    /// @notice Creates a campaign with allowlist
    function createCampaignWithAllowlist(
        address advertiser,
        address attributionProvider,
        string[] memory allowedRefCodes
    ) public returns (address campaign) {
        campaign = createCampaign(
            advertiser,
            attributionProvider,
            allowedRefCodes,
            _createDefaultConfigs(),
            DEFAULT_ATTRIBUTION_WINDOW,
            DEFAULT_FEE_BPS
        );
    }

    /// @notice Creates a campaign with zero fee
    function createZeroFeeCampaign(address advertiser, address attributionProvider) public returns (address campaign) {
        campaign = createCampaign(
            advertiser,
            attributionProvider,
            new string[](0),
            _createDefaultConfigs(),
            DEFAULT_ATTRIBUTION_WINDOW,
            ZERO_FEE_BPS
        );
    }

    /// @notice Creates a campaign with maximum fee
    function createMaxFeeCampaign(address advertiser, address attributionProvider) public returns (address campaign) {
        campaign = createCampaign(
            advertiser,
            attributionProvider,
            new string[](0),
            _createDefaultConfigs(),
            DEFAULT_ATTRIBUTION_WINDOW,
            MAX_FEE_BPS
        );
    }

    // ========================================
    // CONVERSION CONFIG UTILITIES
    // ========================================

    function _createDefaultConfigs() internal pure returns (AdConversion.ConversionConfigInput[] memory) {
        AdConversion.ConversionConfigInput[] memory configs = new AdConversion.ConversionConfigInput[](2);
        configs[0] = AdConversion.ConversionConfigInput({
            isEventOnchain: false, metadataURI: "https://campaign.example.com/offchain-config"
        });
        configs[1] = AdConversion.ConversionConfigInput({
            isEventOnchain: true, metadataURI: "https://campaign.example.com/onchain-config"
        });
        return configs;
    }

    function createOnchainConfig(string memory metadataURI)
        public
        pure
        returns (AdConversion.ConversionConfigInput memory)
    {
        return AdConversion.ConversionConfigInput({isEventOnchain: true, metadataURI: metadataURI});
    }

    function createOffchainConfig(string memory metadataURI)
        public
        pure
        returns (AdConversion.ConversionConfigInput memory)
    {
        return AdConversion.ConversionConfigInput({isEventOnchain: false, metadataURI: metadataURI});
    }

    // ========================================
    // ATTRIBUTION UTILITIES
    // ========================================

    /// @notice Creates a basic offchain attribution
    function createOffchainAttribution(string memory publisherRefCode, address payoutRecipient, uint256 payoutAmount)
        public
        view
        returns (AdConversion.Attribution memory)
    {
        return AdConversion.Attribution({
            conversion: AdConversion.Conversion({
                eventId: bytes16(uint128(block.timestamp)),
                clickId: "test_click_id",
                configId: 1, // Offchain config
                publisherRefCode: publisherRefCode,
                timestamp: uint32(block.timestamp),
                payoutRecipient: payoutRecipient,
                payoutAmount: payoutAmount
            }),
            logBytes: ""
        });
    }

    /// @notice Creates a basic onchain attribution
    function createOnchainAttribution(string memory publisherRefCode, address payoutRecipient, uint256 payoutAmount)
        public
        view
        returns (AdConversion.Attribution memory)
    {
        AdConversion.Log memory logData =
            AdConversion.Log({chainId: block.chainid, transactionHash: keccak256("test_transaction"), index: 0});

        return AdConversion.Attribution({
            conversion: AdConversion.Conversion({
                eventId: bytes16(uint128(block.timestamp + 1)),
                clickId: "test_onchain_click_id",
                configId: 2, // Onchain config
                publisherRefCode: publisherRefCode,
                timestamp: uint32(block.timestamp),
                payoutRecipient: payoutRecipient,
                payoutAmount: payoutAmount
            }),
            logBytes: abi.encode(logData)
        });
    }

    /// @notice Creates attribution with custom config ID
    function createAttributionWithConfigId(
        uint16 configId,
        string memory publisherRefCode,
        address payoutRecipient,
        uint256 payoutAmount
    ) public view returns (AdConversion.Attribution memory) {
        return AdConversion.Attribution({
            conversion: AdConversion.Conversion({
                eventId: bytes16(uint128(block.timestamp + configId)),
                clickId: string(abi.encodePacked("click_", vm.toString(configId))),
                configId: configId,
                publisherRefCode: publisherRefCode,
                timestamp: uint32(block.timestamp),
                payoutRecipient: payoutRecipient,
                payoutAmount: payoutAmount
            }),
            logBytes: ""
        });
    }

    /// @notice Creates attribution with zero recipient (for testing resolution)
    function createZeroRecipientAttribution(string memory publisherRefCode, uint256 payoutAmount)
        public
        view
        returns (AdConversion.Attribution memory)
    {
        return createOffchainAttribution(publisherRefCode, address(0), payoutAmount);
    }

    /// @notice Creates attribution with empty ref code
    function createEmptyRefCodeAttribution(address payoutRecipient, uint256 payoutAmount)
        public
        view
        returns (AdConversion.Attribution memory)
    {
        return createOffchainAttribution("", payoutRecipient, payoutAmount);
    }

    /// @notice Generates valid publisher ref code from seed
    /// @param seed Random number to seed the valid code generation
    /// @return code Valid publisher ref code
    function generateValidRefCodeFromSeed(uint256 seed) public view returns (string memory code) {
        bytes memory allowedCharacters = bytes(builderCodes.ALLOWED_CHARACTERS());
        uint256 divisor = allowedCharacters.length;
        uint256 maxLength = 32;
        bytes memory codeBytes = new bytes(maxLength);
        uint256 codeLength = 0;

        // Iteratively generate code with modulo arithmetic on pseudo-random hash
        for (uint256 i; i < maxLength; i++) {
            codeLength++;
            codeBytes[i] = allowedCharacters[seed % divisor];
            seed /= divisor;
            if (seed == 0) break;
        }

        // Resize codeBytes to actual output length
        assembly {
            mstore(codeBytes, codeLength)
        }

        return string(codeBytes);
    }

    // ========================================
    // CAMPAIGN FUNDING UTILITIES
    // ========================================

    /// @notice Funds a campaign with default amount
    function fundCampaign(address campaign) public {
        fundCampaign(campaign, address(tokenA), DEFAULT_CAMPAIGN_FUNDING);
    }

    /// @notice Funds a campaign with specific token and amount
    function fundCampaign(address campaign, address token, uint256 amount) public {
        // Use advertiser1 as the funding source since they have token balance
        vm.prank(advertiser1);
        MockERC20(token).transfer(campaign, amount);
    }

    /// @notice Funds multiple campaigns
    function fundCampaigns(address[] memory campaigns, address token, uint256 amountEach) public {
        for (uint256 i = 0; i < campaigns.length; i++) {
            fundCampaign(campaigns[i], token, amountEach);
        }
    }

    // ========================================
    // CAMPAIGN LIFECYCLE UTILITIES
    // ========================================

    /// @notice Activates a campaign
    function activateCampaign(address campaign, address attributionProvider) public {
        vm.prank(attributionProvider);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.ACTIVE, "");
    }

    /// @notice Finalizes a campaign (ACTIVE → FINALIZING → FINALIZED)
    function finalizeCampaign(address campaign, address attributionProvider) public {
        vm.startPrank(attributionProvider);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.FINALIZING, "");
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.FINALIZED, "");
        vm.stopPrank();
    }

    /// @notice Creates a complete campaign lifecycle (create → fund → activate)
    function createActiveCampaign() public returns (address campaign) {
        campaign = createBasicCampaign();
        fundCampaign(campaign);
        activateCampaign(campaign, attributionProvider1);
    }

    /// @notice Creates a finalized campaign for withdrawal testing
    function createFinalizedCampaign() public returns (address campaign) {
        campaign = createActiveCampaign();
        finalizeCampaign(campaign, attributionProvider1);
    }

    // ========================================
    // ATTRIBUTION PROCESSING UTILITIES
    // ========================================

    /// @notice Processes a single attribution
    function processAttribution(
        address campaign,
        address token,
        AdConversion.Attribution memory attribution,
        address attributionProvider
    ) public {
        AdConversion.Attribution[] memory attributions = new AdConversion.Attribution[](1);
        attributions[0] = attribution;
        processAttributions(campaign, token, attributions, attributionProvider);
    }

    /// @notice Processes multiple attributions
    function processAttributions(
        address campaign,
        address token,
        AdConversion.Attribution[] memory attributions,
        address attributionProvider
    ) public {
        bytes memory attributionData = abi.encode(attributions);
        vm.prank(attributionProvider);
        flywheel.send(campaign, token, attributionData);
    }

    /// @notice Generates fees through a single attribution send call
    /// @dev Creates an attribution with specified amount and fee basis points, then processes it to accumulate fees
    /// @param campaign Campaign address
    /// @param token Token address
    /// @param attributionProvider Attribution provider address
    /// @param payoutAmount Payout amount for the attribution (will generate fee based on campaign feeBps)
    /// @param publisherRefCode Publisher ref code to use in attribution
    /// @return generatedFeeAmount The fee amount that was generated and accumulated
    function generateFeesWithSingleAttribution(
        address campaign,
        address token,
        address attributionProvider,
        uint256 payoutAmount,
        string memory publisherRefCode
    ) public returns (uint256 generatedFeeAmount) {
        // Get campaign fee basis points
        (,, uint16 feeBps,,,) = adConversion.state(campaign);

        // Calculate expected fee amount
        generatedFeeAmount = (payoutAmount * feeBps) / adConversion.MAX_BPS();

        // Create attribution
        AdConversion.Attribution[] memory attributions = new AdConversion.Attribution[](1);
        attributions[0] = AdConversion.Attribution({
            conversion: AdConversion.Conversion({
                eventId: bytes16(uint128(1)),
                clickId: "click1",
                configId: 1,
                publisherRefCode: publisherRefCode,
                timestamp: uint32(block.timestamp),
                payoutRecipient: publisher1,
                payoutAmount: payoutAmount
            }),
            logBytes: ""
        });

        // Process attribution to generate fees
        processAttributions(campaign, token, attributions, attributionProvider);
    }

    /// @notice Generates fees through multiple attributions with varying amounts
    /// @dev Creates multiple attributions with different amounts to test fee accumulation
    /// @param campaign Campaign address
    /// @param token Token address
    /// @param attributionProvider Attribution provider address
    /// @param baseAmount Base amount for calculations (other amounts derived from this)
    /// @return totalGeneratedFeeAmount The total fee amount generated across all attributions
    function generateFeesWithMultipleAttributions(
        address campaign,
        address token,
        address attributionProvider,
        uint256 baseAmount
    ) public returns (uint256 totalGeneratedFeeAmount) {
        // Get campaign fee basis points
        (,, uint16 feeBps,,,) = adConversion.state(campaign);

        // Create attributions with different amounts
        AdConversion.Attribution[] memory attributions = new AdConversion.Attribution[](NUM_MULTI_ATTRIBUTIONS);

        // Attribution 1: base amount
        uint256 amount1 = baseAmount;
        attributions[0] = AdConversion.Attribution({
            conversion: AdConversion.Conversion({
                eventId: bytes16(uint128(1)),
                clickId: "click1",
                configId: 1,
                publisherRefCode: REF_CODE_1,
                timestamp: uint32(block.timestamp),
                payoutRecipient: publisher1,
                payoutAmount: amount1
            }),
            logBytes: ""
        });

        // Attribution 2: double amount
        uint256 amount2 = baseAmount * 2;
        attributions[1] = AdConversion.Attribution({
            conversion: AdConversion.Conversion({
                eventId: bytes16(uint128(2)),
                clickId: "click2",
                configId: 1,
                publisherRefCode: REF_CODE_2,
                timestamp: uint32(block.timestamp),
                payoutRecipient: publisher2,
                payoutAmount: amount2
            }),
            logBytes: ""
        });

        // Attribution 3: half amount
        uint256 amount3 = baseAmount / 2;
        attributions[2] = AdConversion.Attribution({
            conversion: AdConversion.Conversion({
                eventId: bytes16(uint128(3)),
                clickId: "click3",
                configId: 1,
                publisherRefCode: REF_CODE_3,
                timestamp: uint32(block.timestamp),
                payoutRecipient: publisher3,
                payoutAmount: amount3
            }),
            logBytes: ""
        });

        // Calculate total expected fee (individual calculation to match contract logic)
        uint256 fee1 = (amount1 * feeBps) / adConversion.MAX_BPS();
        uint256 fee2 = (amount2 * feeBps) / adConversion.MAX_BPS();
        uint256 fee3 = (amount3 * feeBps) / adConversion.MAX_BPS();
        totalGeneratedFeeAmount = fee1 + fee2 + fee3;

        // Process attributions to generate fees
        processAttributions(campaign, token, attributions, attributionProvider);
    }

    // ========================================
    // ASSERTION HELPERS
    // ========================================

    /// @notice Asserts token balance
    function assertTokenBalance(address token, address account, uint256 expectedBalance) public view {
        uint256 actualBalance = MockERC20(token).balanceOf(account);
        assertEq(actualBalance, expectedBalance, "Token balance mismatch");
    }

    /// @notice Asserts campaign status
    function assertCampaignStatus(address campaign, Flywheel.CampaignStatus expectedStatus) public view {
        Flywheel.CampaignStatus actualStatus = flywheel.campaignStatus(campaign);
        assertEq(uint8(actualStatus), uint8(expectedStatus), "Campaign status mismatch");
    }

    /// @notice Asserts allocated fee amount
    function assertAllocatedFee(address campaign, address token, address provider, uint256 expectedFee) public view {
        uint256 actualFee = flywheel.allocatedFee(campaign, token, bytes32(bytes20(provider)));
        assertEq(actualFee, expectedFee, "Allocated fee mismatch");
    }

    /// @notice Asserts campaign state fields
    function assertCampaignState(
        address campaign,
        address expectedAdvertiser,
        address expectedAttributionProvider,
        uint16 expectedFeeBps,
        uint48 expectedAttributionWindow
    ) public view {
        (
            address advertiser,
            bool hasAllowlist,
            uint16 feeBps,
            address attributionProvider,
            uint48 attributionWindow,
            uint48 deadline
        ) = adConversion.state(campaign);

        assertEq(advertiser, expectedAdvertiser, "Campaign advertiser mismatch");
        assertEq(attributionProvider, expectedAttributionProvider, "Campaign attribution provider mismatch");
        assertEq(feeBps, expectedFeeBps, "Campaign fee BPS mismatch");
        assertEq(attributionWindow, expectedAttributionWindow, "Campaign attribution window mismatch");
    }

    /// @notice Asserts campaign URI
    function assertCampaignURI(address campaign, string memory expectedURI) public view {
        string memory actualURI = adConversion.campaignURI(campaign);
        assertEq(actualURI, expectedURI, "Campaign URI mismatch");
    }

    /// @notice Asserts conversion config exists and matches expected values
    function assertConversionConfig(
        address campaign,
        uint16 configId,
        bool expectedIsActive,
        bool expectedIsOnchain,
        string memory expectedMetadataURI
    ) public view {
        (bool isActive, bool isEventOnchain, string memory metadataURI) =
            adConversion.conversionConfigs(campaign, configId);

        assertEq(isActive, expectedIsActive, "Config active status mismatch");
        assertEq(isEventOnchain, expectedIsOnchain, "Config onchain status mismatch");
        assertEq(metadataURI, expectedMetadataURI, "Config metadata URI mismatch");
    }

    /// @notice Asserts conversion config count
    function assertConversionConfigCount(address campaign, uint16 expectedCount) public view {
        uint16 actualCount = adConversion.conversionConfigCount(campaign);
        assertEq(actualCount, expectedCount, "Conversion config count mismatch");
    }

    /// @notice Asserts publisher allowlist status
    function assertPublisherAllowed(address campaign, string memory refCode, bool expectedAllowed) public view {
        bool actualAllowed = adConversion.isPublisherRefCodeAllowed(campaign, refCode);
        assertEq(actualAllowed, expectedAllowed, "Publisher allowlist status mismatch");
    }

    // ========================================
    // CAMPAIGN INVARIANT ASSERTIONS
    // ========================================

    /// @notice Comprehensive campaign state validation
    function assertCampaignInvariants(address campaign, address token) public view {
        // Campaign must exist
        assertTrue(flywheel.campaignExists(campaign), "Campaign does not exist");

        // If campaign has allocated fees, they should be <= campaign balance
        address attributionProvider = getCampaignAttributionProvider(campaign);
        if (attributionProvider != address(0)) {
            uint256 allocatedFee = flywheel.allocatedFee(campaign, token, bytes32(bytes20(attributionProvider)));
            uint256 campaignBalance = MockERC20(token).balanceOf(campaign);
            assertLe(allocatedFee, campaignBalance, "Allocated fee exceeds campaign balance");
        }
    }

    /// @notice Attribution provider balance and fee consistency check
    function assertAttributionProviderInvariants(
        address campaign,
        address token,
        address attributionProvider,
        uint256 balanceBeforeDistribution,
        uint256 expectedFeeAmount
    ) public view {
        uint256 currentBalance = MockERC20(token).balanceOf(attributionProvider);
        uint256 currentAllocatedFee = flywheel.allocatedFee(campaign, token, bytes32(bytes20(attributionProvider)));

        // After fee distribution, balance should increase by expected amount
        assertEq(
            currentBalance,
            balanceBeforeDistribution + expectedFeeAmount,
            "Attribution provider balance incorrect after fee distribution"
        );

        // After fee distribution, allocated fee should be zero
        assertEq(currentAllocatedFee, 0, "Allocated fee should be zero after distribution");
    }

    /// @notice Assert campaign is properly finalized after complete lifecycle
    function assertCampaignCompletedLifecycle(address campaign, address token, address attributionProvider)
        public
        view
    {
        // Campaign should be finalized
        assertCampaignStatus(campaign, Flywheel.CampaignStatus.FINALIZED);

        // Campaign should be empty after withdrawal
        assertTokenBalance(token, campaign, 0);

        // No fees should remain allocated
        assertAllocatedFee(campaign, token, attributionProvider, 0);
    }

    // ========================================
    // CAMPAIGN DATA GETTERS
    // ========================================

    /// @notice Gets campaign attribution provider from state
    function getCampaignAttributionProvider(address campaign) public view returns (address) {
        (,,, address attributionProvider,,) = adConversion.state(campaign);
        return attributionProvider;
    }

    /// @notice Gets campaign advertiser from state
    function getCampaignAdvertiser(address campaign) public view returns (address) {
        (address advertiser,,,,,) = adConversion.state(campaign);
        return advertiser;
    }

    /// @notice Gets campaign fee BPS from state
    function getCampaignFeeBps(address campaign) public view returns (uint16) {
        (,, uint16 feeBps,,,) = adConversion.state(campaign);
        return feeBps;
    }

    // ========================================
    // TEST DATA GENERATORS
    // ========================================

    /// @notice Generates test allowlist
    function generateAllowlist() public pure returns (string[] memory) {
        string[] memory allowlist = new string[](2);
        allowlist[0] = REF_CODE_1;
        allowlist[1] = REF_CODE_2;
        return allowlist;
    }

    /// @notice Generates large allowlist for stress testing
    function generateLargeAllowlist(uint256 size) public pure returns (string[] memory) {
        string[] memory allowlist = new string[](size);
        for (uint256 i = 0; i < size; i++) {
            allowlist[i] = string(abi.encodePacked("ref", vm.toString(i)));
        }
        return allowlist;
    }

    /// @notice Generates batch attributions for testing
    function generateBatchAttributions(
        uint256 count,
        string memory publisherRefCode,
        address payoutRecipient,
        uint256 payoutAmountEach
    ) public view returns (AdConversion.Attribution[] memory) {
        AdConversion.Attribution[] memory attributions = new AdConversion.Attribution[](count);
        for (uint256 i = 0; i < count; i++) {
            attributions[i] = AdConversion.Attribution({
                conversion: AdConversion.Conversion({
                    eventId: bytes16(uint128(block.timestamp + i)),
                    clickId: string(abi.encodePacked("batch_click_", vm.toString(i))),
                    configId: 1,
                    publisherRefCode: publisherRefCode,
                    timestamp: uint32(block.timestamp),
                    payoutRecipient: payoutRecipient,
                    payoutAmount: payoutAmountEach
                }),
                logBytes: ""
            });
        }
        return attributions;
    }

    // ========================================
    // MOCK DATA UTILITIES
    // ========================================

    /// @notice Creates mock log data for onchain attributions
    function createMockLogData() public view returns (AdConversion.Log memory) {
        return AdConversion.Log({
            chainId: block.chainid, transactionHash: keccak256(abi.encodePacked("mock_tx", block.timestamp)), index: 0
        });
    }

    /// @notice Creates very long string for edge case testing
    function createLongString(uint256 length) public pure returns (string memory) {
        bytes memory longBytes = new bytes(length);
        for (uint256 i = 0; i < length; i++) {
            longBytes[i] = bytes1(uint8(65 + (i % 26))); // A-Z repeating
        }
        return string(longBytes);
    }

    // ========================================
    // HOOK CALL UTILITIES (FOR UNIT TESTING)
    // ========================================

    /// @notice Calls hook function directly (for unit testing)
    /// @dev Uses vm.prank(address(flywheel)) to simulate Flywheel calling the hook
    function callHookOnCreateCampaign(address campaign, bytes memory hookData) public {
        vm.prank(address(flywheel));
        adConversion.onCreateCampaign(campaign, DEFAULT_CAMPAIGN_NONCE, hookData);
    }

    /// @notice Calls hook onSend directly (for unit testing)
    function callHookOnSend(address sender, address campaign, address token, bytes memory hookData)
        public
        returns (Flywheel.Payout[] memory payouts, Flywheel.Distribution[] memory fees, bool sendFeesNow)
    {
        vm.prank(address(flywheel));
        return adConversion.onSend(sender, campaign, token, hookData);
    }

    /// @notice Calls hook onWithdrawFunds directly (for unit testing)
    function callHookOnWithdrawFunds(address sender, address campaign, address token, bytes memory hookData)
        public
        returns (Flywheel.Payout memory payout)
    {
        vm.prank(address(flywheel));
        return adConversion.onWithdrawFunds(sender, campaign, token, hookData);
    }

    /// @notice Calls hook onDistributeFees directly (for unit testing)
    function callHookOnDistributeFees(address sender, address campaign, address token, bytes memory hookData)
        public
        returns (Flywheel.Distribution[] memory distributions)
    {
        vm.prank(address(flywheel));
        return adConversion.onDistributeFees(sender, campaign, token, hookData);
    }

    /// @notice Calls hook onUpdateStatus directly (for unit testing)
    function callHookOnUpdateStatus(
        address sender,
        address campaign,
        Flywheel.CampaignStatus fromStatus,
        Flywheel.CampaignStatus toStatus,
        bytes memory hookData
    ) public {
        vm.prank(address(flywheel));
        adConversion.onUpdateStatus(sender, campaign, fromStatus, toStatus, hookData);
    }

    /// @notice Calls hook onUpdateMetadata directly (for unit testing)
    function callHookOnUpdateMetadata(address sender, address campaign, bytes memory hookData) public {
        vm.prank(address(flywheel));
        adConversion.onUpdateMetadata(sender, campaign, hookData);
    }

    // ========================================
    // ADDRESS LABELING (FOR READABLE LOGS)
    // ========================================

    /// @notice Labels all important addresses for readable foundry logs
    function _labelAddresses() internal {
        // Core contracts
        vm.label(address(flywheel), "Flywheel");
        vm.label(address(builderCodes), "BuilderCodes");
        vm.label(address(adConversion), "AdConversion");

        // Test tokens
        vm.label(address(tokenA), "TokenA");
        vm.label(address(tokenB), "TokenB");

        // Admin/System actors
        vm.label(admin, "Admin");
        vm.label(registrarSigner, "RegistrarSigner");

        // Campaign actors
        vm.label(advertiser1, "Advertiser1");
        vm.label(advertiser2, "Advertiser2");
        vm.label(attributionProvider1, "AttributionProvider1");
        vm.label(attributionProvider2, "AttributionProvider2");

        // Publisher actors
        vm.label(publisher1, "Publisher1");
        vm.label(publisher2, "Publisher2");
        vm.label(publisher3, "Publisher3");
        vm.label(publisherPayout1, "PublisherPayout1");
        vm.label(publisherPayout2, "PublisherPayout2");
        vm.label(publisherPayout3, "PublisherPayout3");

        // Utility actors
        vm.label(unauthorizedUser, "UnauthorizedUser");
        vm.label(randomRecipient, "RandomRecipient");
        vm.label(burnAddress, "BurnAddress");

        // Test contract itself
        vm.label(address(this), "TestContract");
    }
}
