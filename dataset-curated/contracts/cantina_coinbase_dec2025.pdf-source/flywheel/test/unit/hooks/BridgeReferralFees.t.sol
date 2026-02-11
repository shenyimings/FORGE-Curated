// SPDX-License-Identifier: Unlicense
pragma solidity 0.8.29;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {BuilderCodes} from "builder-codes/BuilderCodes.sol";

import {Test} from "forge-std/Test.sol";
import {LibString} from "solady/utils/LibString.sol";

import {MockERC3009Token} from "../../../lib/commerce-payments/test/mocks/MockERC3009Token.sol";
import {MockAccount} from "../../lib/mocks/MockAccount.sol";

import {Constants} from "../../../src/Constants.sol";
import {Flywheel} from "../../../src/Flywheel.sol";
import {BridgeReferralFees} from "../../../src/hooks/BridgeReferralFees.sol";

contract BridgeReferralFeesTest is Test {
    Flywheel public flywheel;
    BridgeReferralFees public bridgeReferralFees;
    BuilderCodes public builderCodes;
    MockERC3009Token public usdc;

    address public bridgeReferralFeesCampaign;
    address public owner = address(0x1);
    address public user = address(0x2);
    address public builder = address(0x3);
    address public builderPayout = address(0x4);

    string public constant TEST_CODE = "testcode";
    string public constant CAMPAIGN_URI = "https://example.com/campaign/metadata";

    function setUp() public virtual {
        // Deploy Flywheel
        flywheel = new Flywheel();

        // Deploy and initialize BuilderCodes
        BuilderCodes impl = new BuilderCodes();
        bytes memory initData = abi.encodeWithSelector(
            BuilderCodes.initialize.selector,
            owner,
            owner, // registrar
            "" // empty baseURI
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        builderCodes = BuilderCodes(address(proxy));

        // Deploy BridgeReferralFees
        bridgeReferralFees = new BridgeReferralFees(address(flywheel), address(builderCodes), 200, owner, CAMPAIGN_URI);

        // Deploy mock USDC
        usdc = new MockERC3009Token("USD Coin", "USDC", 6);

        // Register a test builder code
        vm.startPrank(owner);
        builderCodes.register(TEST_CODE, builder, builderPayout);
        vm.stopPrank();

        // Create campaign
        bridgeReferralFeesCampaign = flywheel.createCampaign(address(bridgeReferralFees), 0, "");

        // Activate the campaign since BridgeReferralFees only allows ACTIVE status
        flywheel.updateStatus(bridgeReferralFeesCampaign, Flywheel.CampaignStatus.ACTIVE, "");

        vm.label(bridgeReferralFeesCampaign, "BridgeReferralFeesCampaign");
        vm.label(address(flywheel), "Flywheel");
        vm.label(address(bridgeReferralFees), "BridgeReferralFees");
        vm.label(address(builderCodes), "BuilderCodes");
        vm.label(address(usdc), "USDC");
        vm.label(owner, "Owner");
        vm.label(user, "User");
        vm.label(builder, "Builder");
        vm.label(builderPayout, "BuilderPayout");
    }

    function test_onCreateCampaign_revert_invalidNonce() public {
        // Should revert with non-zero nonce
        vm.expectRevert(BridgeReferralFees.InvalidCampaignInitialization.selector);
        flywheel.createCampaign(address(bridgeReferralFees), 1, "");
    }

    function test_onCreateCampaign_revert_invalidHookData() public {
        // Should revert with non-empty hook data
        vm.expectRevert(BridgeReferralFees.InvalidCampaignInitialization.selector);
        flywheel.createCampaign(address(bridgeReferralFees), 0, "invalid");
    }

    function test_onSend_success(uint256 bridgedAmount, uint8 feeBps) public {
        // Fund the campaign
        vm.assume(bridgedAmount > 0);
        usdc.mint(bridgeReferralFeesCampaign, bridgedAmount);

        // Prepare hook data with fee
        vm.assume(feeBps > 0);
        vm.assume(feeBps <= bridgeReferralFees.MAX_FEE_BASIS_POINTS());
        bytes memory hookData = abi.encode(user, TEST_CODE, feeBps);

        uint256 feeAmount = (bridgedAmount / 1e4) * feeBps + ((bridgedAmount % 1e4) * feeBps) / 1e4;
        uint256 userAmount = bridgedAmount - feeAmount;

        // Record balances before
        uint256 userBalanceBefore = usdc.balanceOf(user);
        uint256 builderPayoutBalanceBefore = usdc.balanceOf(builderPayout);

        // Execute send
        flywheel.send(bridgeReferralFeesCampaign, address(usdc), hookData);

        // Check final balances
        assertEq(usdc.balanceOf(user), userBalanceBefore + userAmount, "User should receive balance minus fee");
        assertEq(usdc.balanceOf(builderPayout), builderPayoutBalanceBefore + feeAmount, "Builder should receive fee");
        assertEq(usdc.balanceOf(bridgeReferralFeesCampaign), 0, "Campaign should be empty");
    }

    function test_onSend_success_no_fee(uint256 bridgedAmount) public {
        // Fund the campaign
        vm.assume(bridgedAmount > 0);
        usdc.mint(bridgeReferralFeesCampaign, bridgedAmount);

        // Prepare hook data with 0% fee
        uint8 feeBps = 0;
        bytes memory hookData = abi.encode(user, TEST_CODE, feeBps);

        // Record balances before
        uint256 userBalanceBefore = usdc.balanceOf(user);
        uint256 builderPayoutBalanceBefore = usdc.balanceOf(builderPayout);

        // Execute send
        flywheel.send(bridgeReferralFeesCampaign, address(usdc), hookData);

        // Check final balances
        assertEq(usdc.balanceOf(user), userBalanceBefore + bridgedAmount, "User should receive full balance");
        assertEq(usdc.balanceOf(builderPayout), builderPayoutBalanceBefore, "Builder should receive no fee");
        assertEq(usdc.balanceOf(bridgeReferralFeesCampaign), 0, "Campaign should be empty");
    }

    function test_onSend_success_builderCodeNotRegistered(uint256 bridgedAmount, uint8 feeBps) public {
        // Fund the campaign
        vm.assume(bridgedAmount > 0);
        usdc.mint(bridgeReferralFeesCampaign, bridgedAmount);

        // Prepare hook data with fee
        string memory unregisteredCode = "unregistered";
        bytes memory hookData = abi.encode(user, unregisteredCode, feeBps);

        // Record balances before
        uint256 userBalanceBefore = usdc.balanceOf(user);
        uint256 builderPayoutBalanceBefore = usdc.balanceOf(builderPayout);

        // Execute send
        flywheel.send(bridgeReferralFeesCampaign, address(usdc), hookData);

        // Check final balances
        assertEq(usdc.balanceOf(user), userBalanceBefore + bridgedAmount, "User should receive full balance");
        assertEq(usdc.balanceOf(builderPayout), builderPayoutBalanceBefore, "Builder should receive no fee");
        assertEq(usdc.balanceOf(bridgeReferralFeesCampaign), 0, "Campaign should be empty");
    }

    function test_onSend_success_feeBasisPointsTooHigh(uint256 bridgedAmount, uint8 feeBps) public {
        // Fund the campaign
        vm.assume(bridgedAmount > 0);
        usdc.mint(bridgeReferralFeesCampaign, bridgedAmount);

        // Use fee higher than maximum (2%)
        uint8 maxFeeBps = bridgeReferralFees.MAX_FEE_BASIS_POINTS();
        vm.assume(feeBps > maxFeeBps);
        bytes memory hookData = abi.encode(user, TEST_CODE, feeBps);

        uint256 feeAmount = (bridgedAmount / 1e4) * maxFeeBps + ((bridgedAmount % 1e4) * maxFeeBps) / 1e4;
        uint256 userAmount = bridgedAmount - feeAmount;

        // Record balances before
        uint256 userBalanceBefore = usdc.balanceOf(user);
        uint256 builderPayoutBalanceBefore = usdc.balanceOf(builderPayout);

        // Execute send
        flywheel.send(bridgeReferralFeesCampaign, address(usdc), hookData);

        // Check final balances
        assertEq(usdc.balanceOf(user), userBalanceBefore + userAmount, "User should receive balance minus fee");
        assertEq(usdc.balanceOf(builderPayout), builderPayoutBalanceBefore + feeAmount, "Builder should receive fee");
        assertEq(usdc.balanceOf(bridgeReferralFeesCampaign), 0, "Campaign should be empty");
    }

    function test_onSend_allocatedFeesNotIncludedInAvailableBalance(uint256 bridgedAmount, uint8 feeBps) public {
        // Fund the campaign
        bridgedAmount = bound(bridgedAmount, 1, type(uint256).max / 2);
        vm.deal(bridgeReferralFeesCampaign, bridgedAmount);

        // Prepare mock account
        MockAccount mockAccount = new MockAccount(address(0), false); // reject native token initially
        vm.prank(builder);
        builderCodes.updatePayoutAddress(TEST_CODE, address(mockAccount));

        // Prepare hook data with fee
        vm.assume(feeBps > 0);
        vm.assume(feeBps <= bridgeReferralFees.MAX_FEE_BASIS_POINTS());
        bytes memory hookData = abi.encode(user, TEST_CODE, feeBps);

        uint256 feeAmount = (bridgedAmount / 1e4) * feeBps + ((bridgedAmount % 1e4) * feeBps) / 1e4;
        uint256 userAmount = bridgedAmount - feeAmount;

        // Record balances before
        uint256 userBalanceBefore = user.balance;
        uint256 builderPayoutBalanceBefore = builderPayout.balance;

        // Execute send
        flywheel.send(bridgeReferralFeesCampaign, Constants.NATIVE_TOKEN, hookData);

        // Check balances after send with failed fee send
        assertEq(user.balance, userBalanceBefore + userAmount, "User should receive balance minus fee");
        assertEq(builderPayout.balance, builderPayoutBalanceBefore, "Builder should not receive fee");
        assertEq(
            bridgeReferralFeesCampaign.balance,
            flywheel.totalAllocatedFees(bridgeReferralFeesCampaign, Constants.NATIVE_TOKEN),
            "Campaign should only have total allocated fees left over"
        );
        bytes32 code = bytes32(builderCodes.toTokenId(TEST_CODE));
        assertEq(
            flywheel.totalAllocatedFees(bridgeReferralFeesCampaign, Constants.NATIVE_TOKEN),
            flywheel.allocatedFee(bridgeReferralFeesCampaign, Constants.NATIVE_TOKEN, code),
            "Only allocated fee is for TEST_CODE"
        );
        assertEq(
            flywheel.allocatedFee(bridgeReferralFeesCampaign, Constants.NATIVE_TOKEN, code),
            feeAmount,
            "Allocated fee matches intended amount"
        );

        // Perform another send with no fees
        vm.deal(bridgeReferralFeesCampaign, bridgeReferralFeesCampaign.balance + bridgedAmount);

        // Record balances before
        userBalanceBefore = user.balance;
        builderPayoutBalanceBefore = builderPayout.balance;

        // Execute send
        feeBps = 0;
        hookData = abi.encode(user, TEST_CODE, feeBps);
        flywheel.send(bridgeReferralFeesCampaign, Constants.NATIVE_TOKEN, hookData);

        // Check balances after send with no fees
        assertEq(user.balance, userBalanceBefore + bridgedAmount, "User should receive all of new campaign funding");
        assertEq(builderPayout.balance, builderPayoutBalanceBefore, "Builder should not receive fee");
        assertEq(
            bridgeReferralFeesCampaign.balance,
            flywheel.totalAllocatedFees(bridgeReferralFeesCampaign, Constants.NATIVE_TOKEN),
            "Campaign should only have allocated fees left over"
        );
    }

    function test_onWithdrawFunds_success(uint256 amount) public {
        // Fund the campaign
        vm.assume(amount > 0);
        usdc.mint(bridgeReferralFeesCampaign, amount);

        // Prepare withdrawal hook data
        Flywheel.Payout memory payout = Flywheel.Payout({recipient: user, amount: amount, extraData: ""});
        bytes memory hookData = abi.encode(payout);

        // Record balances before
        uint256 userBalanceBefore = usdc.balanceOf(user);

        // Execute withdrawal
        flywheel.withdrawFunds(bridgeReferralFeesCampaign, address(usdc), hookData);

        // Check final balances
        assertEq(usdc.balanceOf(user), userBalanceBefore + amount, "User should receive withdrawn amount");
        assertEq(usdc.balanceOf(bridgeReferralFeesCampaign), 0, "Campaign should be empty");
    }

    function test_onUpdateStatus_revert_newStatusNotActive() public {
        // Try to set status to something other than ACTIVE
        vm.expectRevert(Flywheel.InvalidCampaignStatus.selector);
        flywheel.updateStatus(bridgeReferralFeesCampaign, Flywheel.CampaignStatus.FINALIZED, "");

        vm.expectRevert(Flywheel.InvalidCampaignStatus.selector);
        flywheel.updateStatus(bridgeReferralFeesCampaign, Flywheel.CampaignStatus.FINALIZING, "");
    }

    function test_onUpdateStatus_success() public view {
        // The setUp already created a campaign and activated it successfully
        // So we just need to verify that this transition worked
        Flywheel.CampaignStatus status = flywheel.campaignStatus(bridgeReferralFeesCampaign);
        assertEq(uint256(status), uint256(Flywheel.CampaignStatus.ACTIVE), "Campaign should be active");
    }

    function test_onUpdateMetadata_success_updatesUriPrefix(string memory newUriPrefix) public {
        vm.assume(bytes(newUriPrefix).length > 0);
        vm.prank(owner);
        flywheel.updateMetadata(bridgeReferralFeesCampaign, bytes(newUriPrefix));
        assertEq(bridgeReferralFees.uriPrefix(), newUriPrefix, "Uri prefix should be updated");
        assertEq(
            flywheel.campaignURI(bridgeReferralFeesCampaign),
            string.concat(newUriPrefix, LibString.toHexStringChecksummed(bridgeReferralFeesCampaign)),
            "Campaign URI should be updated"
        );
    }

    function test_onUpdateMetadata_success_noUriPrefixChange() public {
        string memory oldUriPrefix = bridgeReferralFees.uriPrefix();
        vm.prank(owner);
        flywheel.updateMetadata(bridgeReferralFeesCampaign, "");
        assertEq(bridgeReferralFees.uriPrefix(), oldUriPrefix, "Uri prefix should not change");
        assertEq(
            flywheel.campaignURI(bridgeReferralFeesCampaign),
            string.concat(oldUriPrefix, LibString.toHexStringChecksummed(bridgeReferralFeesCampaign)),
            "Campaign URI should not change"
        );
    }

    // =============================================================
    //                    NATIVE TOKEN TESTS
    // =============================================================

    function test_send_nativeToken_succeeds(uint256 bridgedAmount, uint8 feeBps) public {
        // Fund campaign with native token
        vm.assume(bridgedAmount > 0);
        vm.deal(bridgeReferralFeesCampaign, bridgedAmount);

        // Prepare hook data (user, code, fee)
        vm.assume(feeBps > 0);
        vm.assume(feeBps <= bridgeReferralFees.MAX_FEE_BASIS_POINTS());
        bytes memory hookData = abi.encode(user, TEST_CODE, feeBps);

        // Expected amounts based on contract logic
        uint256 startingBalance = bridgeReferralFeesCampaign.balance;
        uint256 expectedFee = (startingBalance / 1e4) * feeBps + ((startingBalance % 1e4) * feeBps) / 1e4;
        uint256 expectedUser = startingBalance - expectedFee;

        uint256 userBefore = user.balance;
        uint256 builderBefore = builderPayout.balance;

        flywheel.send(bridgeReferralFeesCampaign, Constants.NATIVE_TOKEN, hookData);

        assertEq(user.balance, userBefore + expectedUser, "User should receive balance minus fee");
        assertEq(builderPayout.balance, builderBefore + expectedFee, "Builder should receive fee");
        assertEq(bridgeReferralFeesCampaign.balance, 0, "Campaign should be empty");
    }

    function test_withdraw_nativeToken_succeeds(uint256 amount) public {
        // Fund campaign with native token
        vm.assume(amount > 0);
        vm.deal(bridgeReferralFeesCampaign, amount);

        // Prepare withdrawal hook data
        Flywheel.Payout memory payout = Flywheel.Payout({recipient: user, amount: amount, extraData: ""});
        bytes memory hookData = abi.encode(payout);

        // Execute withdraw; assert balances updated
        uint256 beforeUser = user.balance;
        flywheel.withdrawFunds(bridgeReferralFeesCampaign, Constants.NATIVE_TOKEN, hookData);
        assertEq(user.balance, beforeUser + amount);
        assertEq(bridgeReferralFeesCampaign.balance, 0);
    }
}
