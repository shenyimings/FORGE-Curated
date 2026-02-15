// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {AdConversion} from "../../src/hooks/AdConversion.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {BuilderCodes} from "builder-codes/BuilderCodes.sol";
import {Test} from "forge-std/Test.sol";

import {PublisherSetupHelper, PublisherTestSetup} from "./PublisherSetupHelper.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

import {Flywheel} from "../../src/Flywheel.sol";

/// @notice Common test helpers for Flywheel protocol testing
abstract contract FlywheelTest is Test, PublisherTestSetup {
    using PublisherSetupHelper for *;
    // Core contracts

    Flywheel public flywheel;
    BuilderCodes public referralCodeRegistry;
    MockERC20 public token;

    // Common test addresses
    address public constant OWNER = address(0x1000);
    address public constant ADVERTISER = address(0x2000);
    address public constant ATTRIBUTION_PROVIDER = address(0x3000);
    address public constant PUBLISHER_1 = address(0x4000);
    address public constant PUBLISHER_2 = address(0x5000);
    address public constant PUBLISHER_1_PAYOUT = address(0x6000);
    address public constant PUBLISHER_2_PAYOUT = address(0x7000);
    address public constant USER = address(0x8000);
    address public constant SIGNER = address(0x9000);

    // Common constants
    uint16 public constant DEFAULT_ATTRIBUTION_FEE_BPS = 500; // 5%
    uint256 public constant INITIAL_TOKEN_BALANCE = 1000e18;
    string public constant DEFAULT_REF_CODE_1 = "ref1";
    string public constant DEFAULT_REF_CODE_2 = "ref2";

    /// @notice Sets up core Flywheel infrastructure
    function _setupFlywheelInfrastructure() internal {
        // Deploy Flywheel
        flywheel = new Flywheel();

        // Deploy token with initial holders
        address[] memory initialHolders = new address[](3);
        initialHolders[0] = ADVERTISER;
        initialHolders[1] = ATTRIBUTION_PROVIDER;
        initialHolders[2] = address(this);
        token = new MockERC20(initialHolders);

        // Deploy upgradeable PublisherRegistry
        BuilderCodes impl = new BuilderCodes();
        bytes memory initData = abi.encodeWithSelector(BuilderCodes.initialize.selector, OWNER, SIGNER, "");
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        referralCodeRegistry = BuilderCodes(address(proxy));
    }

    /// @notice Registers default test publishers using PublisherSetupHelper
    function _registerDefaultPublishers() internal {
        // Create configs for default publishers
        PublisherSetupHelper.PublisherConfig[] memory configs = new PublisherSetupHelper.PublisherConfig[](2);

        configs[0] = PublisherSetupHelper.createPublisherConfig(
            DEFAULT_REF_CODE_1, PUBLISHER_1, PUBLISHER_1_PAYOUT, "https://example.com/publisher1"
        );

        configs[1] = PublisherSetupHelper.createPublisherConfig(
            DEFAULT_REF_CODE_2, PUBLISHER_2, PUBLISHER_2_PAYOUT, "https://example.com/publisher2"
        );

        // Batch register both publishers
        setupPublishers(referralCodeRegistry, configs, OWNER);
    }

    /// @notice Funds a campaign with tokens
    function _fundCampaign(address campaign, uint256 amount) internal {
        vm.prank(ADVERTISER);
        token.transfer(campaign, amount);
    }

    /// @notice Activates a campaign using attribution provider
    function _activateCampaign(address campaign) internal {
        vm.prank(ATTRIBUTION_PROVIDER);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.ACTIVE, "");
    }

    /// @notice Finalizes a campaign (ACTIVE -> FINALIZING -> FINALIZED)
    function _finalizeCampaign(address campaign) internal {
        vm.startPrank(ATTRIBUTION_PROVIDER);
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.FINALIZING, "");
        flywheel.updateStatus(campaign, Flywheel.CampaignStatus.FINALIZED, "");
        vm.stopPrank();
    }

    /// @notice Updates campaign status with given parameters
    function _updateStatus(address campaign, Flywheel.CampaignStatus status, address caller) internal {
        vm.prank(caller);
        flywheel.updateStatus(campaign, status, "");
    }

    /// @notice Collects fees for an attribution provider
    function _distributeFees(address campaign, address feeRecipient) internal {
        vm.prank(feeRecipient);
        flywheel.distributeFees(campaign, address(token), abi.encode(feeRecipient));
    }

    /// @notice Withdraws remaining campaign funds to advertiser
    function _withdrawCampaignFunds(address campaign, uint256 amount) internal {
        vm.prank(ADVERTISER);
        flywheel.withdrawFunds(campaign, address(token), abi.encode(ADVERTISER, amount));
    }

    /// @notice Asserts campaign has expected status
    function _assertCampaignStatus(address campaign, Flywheel.CampaignStatus expectedStatus) internal view {
        assertEq(uint8(flywheel.campaignStatus(campaign)), uint8(expectedStatus));
    }

    /// @notice Asserts token balance for an address
    function _assertTokenBalance(address account, uint256 expectedBalance) internal view {
        assertEq(token.balanceOf(account), expectedBalance);
    }

    /// @notice Asserts fee allocation for attribution provider
    function _assertFeeAllocation(address campaign, address attributionProvider, uint256 expectedFee) internal view {
        assertEq(flywheel.allocatedFee(campaign, address(token), bytes32(bytes20(attributionProvider))), expectedFee);
    }

    /// @notice Calculates fee amount from payout amount and fee basis points
    function _calculateFee(uint256 payoutAmount, uint16 feeBps) internal pure returns (uint256) {
        return payoutAmount * feeBps / 10000;
    }

    /// @notice Calculates net payout after fees
    function _calculateNetPayout(uint256 payoutAmount, uint16 feeBps) internal pure returns (uint256) {
        return payoutAmount - _calculateFee(payoutAmount, feeBps);
    }

    /// @notice Creates a campaign lifecycle test scenario
    function _runCampaignLifecycleTest(address campaign) internal {
        // Start with INACTIVE
        _assertCampaignStatus(campaign, Flywheel.CampaignStatus.INACTIVE);

        // Activate campaign
        _activateCampaign(campaign);
        _assertCampaignStatus(campaign, Flywheel.CampaignStatus.ACTIVE);

        // Finalize campaign
        _finalizeCampaign(campaign);
        _assertCampaignStatus(campaign, Flywheel.CampaignStatus.FINALIZED);
    }

    /// @notice Runs a complete attribution and payout test
    function _runBasicAttributionTest(
        address campaign,
        address hook,
        bytes memory attributionData,
        uint256 expectedPayout,
        address expectedRecipient,
        uint256 expectedFee
    ) internal {
        // Fund and activate campaign
        _fundCampaign(campaign, INITIAL_TOKEN_BALANCE);
        _activateCampaign(campaign);

        // Store initial balances
        uint256 initialRecipientBalance = token.balanceOf(expectedRecipient);
        uint256 initialProviderBalance = token.balanceOf(ATTRIBUTION_PROVIDER);

        // Process attribution
        vm.prank(ATTRIBUTION_PROVIDER);
        flywheel.send(campaign, address(token), attributionData);

        // Verify payout was distributed
        _assertTokenBalance(expectedRecipient, initialRecipientBalance + expectedPayout);

        // Verify fee was allocated
        _assertFeeAllocation(campaign, ATTRIBUTION_PROVIDER, expectedFee);

        // Finalize campaign and collect fees
        _finalizeCampaign(campaign);
        _distributeFees(campaign, ATTRIBUTION_PROVIDER);

        // Verify fee was collected
        _assertTokenBalance(ATTRIBUTION_PROVIDER, initialProviderBalance + expectedFee);
    }
}
