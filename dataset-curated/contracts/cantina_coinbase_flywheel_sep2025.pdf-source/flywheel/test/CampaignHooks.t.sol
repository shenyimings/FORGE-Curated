// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";
import {Flywheel} from "../src/Flywheel.sol";
import {CampaignHooks} from "../src/CampaignHooks.sol";

/// @notice Test implementation of CampaignHooks for testing the abstract base contract
contract TestCampaignHooks is CampaignHooks {
    constructor(address flywheel_) CampaignHooks(flywheel_) {}

    function campaignURI(address campaign) external view override returns (string memory uri) {
        return "";
    }

    function _onCreateCampaign(address campaign, uint256 nonce, bytes calldata hookData) internal override {}

    function _onWithdrawFunds(address sender, address campaign, address token, bytes calldata hookData)
        internal
        override
        returns (Flywheel.Payout memory payout)
    {}

    function _onUpdateStatus(
        address sender,
        address campaign,
        Flywheel.CampaignStatus oldStatus,
        Flywheel.CampaignStatus newStatus,
        bytes calldata hookData
    ) internal override {}

    function _onUpdateMetadata(address sender, address campaign, bytes calldata hookData) internal override {}
}

/// @notice Test contract for CampaignHooks abstract base contract
contract CampaignHooksTest is Test {
    Flywheel public flywheel;
    TestCampaignHooks public hooks;

    address public flywheelOwner;
    address public campaign;
    address public user;
    address public token;

    function setUp() public {
        flywheelOwner = makeAddr("flywheelOwner");
        campaign = makeAddr("campaign");
        user = makeAddr("user");
        token = makeAddr("token");

        // Deploy flywheel
        vm.prank(flywheelOwner);
        flywheel = new Flywheel();

        // Deploy test hooks contract
        hooks = new TestCampaignHooks(address(flywheel));
    }

    /// @notice Test constructor sets flywheel correctly
    function test_constructor_setsFlywheel() public view {
        assertEq(address(hooks.flywheel()), address(flywheel));
    }

    /// @notice Test onCreateCampaign can be called by flywheel
    function test_onCreateCampaign_calledByFlywheel(uint256 nonce) public {
        bytes memory hookData = abi.encode(user);

        vm.prank(address(flywheel));
        hooks.onCreateCampaign(campaign, nonce, hookData);
        // Should not revert
    }

    /// @notice Test onCreateCampaign reverts when not called by flywheel
    function test_onCreateCampaign_revertsWhenNotFlywheel(uint256 nonce) public {
        bytes memory hookData = abi.encode(user);

        vm.prank(user);
        vm.expectRevert();
        hooks.onCreateCampaign(campaign, nonce, hookData);
    }

    /// @notice Test onUpdateMetadata reverts when not called by flywheel
    function test_onUpdateMetadata_revertsWhenNotFlywheel() public {
        bytes memory hookData = abi.encode("metadata");

        vm.prank(user);
        vm.expectRevert();
        hooks.onUpdateMetadata(user, campaign, hookData);
    }

    /// @notice Test onUpdateStatus reverts when not called by flywheel
    function test_onUpdateStatus_revertsWhenNotFlywheel() public {
        bytes memory hookData = "";

        vm.prank(user);
        vm.expectRevert();
        hooks.onUpdateStatus(
            user, campaign, Flywheel.CampaignStatus.ACTIVE, Flywheel.CampaignStatus.FINALIZED, hookData
        );
    }

    /// @notice Test onReward reverts with Unsupported
    function test_onReward_revertsUnsupported() public {
        bytes memory hookData = "";

        vm.prank(address(flywheel));
        vm.expectRevert(CampaignHooks.Unsupported.selector);
        hooks.onSend(user, campaign, token, hookData);
    }

    /// @notice Test onReward reverts when not called by flywheel
    function test_onReward_revertsWhenNotFlywheel() public {
        bytes memory hookData = "";

        vm.prank(user);
        vm.expectRevert();
        hooks.onSend(user, campaign, token, hookData);
    }

    /// @notice Test onAllocate reverts with Unsupported
    function test_onAllocate_revertsUnsupported() public {
        bytes memory hookData = "";

        vm.prank(address(flywheel));
        vm.expectRevert(CampaignHooks.Unsupported.selector);
        hooks.onAllocate(user, campaign, token, hookData);
    }

    /// @notice Test onAllocate reverts when not called by flywheel
    function test_onAllocate_revertsWhenNotFlywheel() public {
        bytes memory hookData = "";

        vm.prank(user);
        vm.expectRevert();
        hooks.onAllocate(user, campaign, token, hookData);
    }

    /// @notice Test onDeallocate reverts with Unsupported
    function test_onDeallocate_revertsUnsupported() public {
        bytes memory hookData = "";

        vm.prank(address(flywheel));
        vm.expectRevert(CampaignHooks.Unsupported.selector);
        hooks.onDeallocate(user, campaign, token, hookData);
    }

    /// @notice Test onDeallocate reverts when not called by flywheel
    function test_onDeallocate_revertsWhenNotFlywheel() public {
        bytes memory hookData = "";

        vm.prank(user);
        vm.expectRevert();
        hooks.onDeallocate(user, campaign, token, hookData);
    }

    /// @notice Test onDistribute reverts with Unsupported
    function test_onDistribute_revertsUnsupported() public {
        bytes memory hookData = "";

        vm.prank(address(flywheel));
        vm.expectRevert(CampaignHooks.Unsupported.selector);
        hooks.onDistribute(user, campaign, token, hookData);
    }

    /// @notice Test onDistribute reverts when not called by flywheel
    function test_onDistribute_revertsWhenNotFlywheel() public {
        bytes memory hookData = "";

        vm.prank(user);
        vm.expectRevert();
        hooks.onDistribute(user, campaign, token, hookData);
    }

    /// @notice Test onWithdrawFunds reverts when not called by flywheel
    function test_onWithdrawFunds_revertsWhenNotFlywheel() public {
        bytes memory hookData = "";
        uint256 amount = 1000;

        vm.prank(user);
        vm.expectRevert();
        hooks.onWithdrawFunds(user, campaign, token, hookData);
    }

    /// @notice Test onlyFlywheel modifier with different addresses
    function test_onlyFlywheel_modifier(uint256 nonce) public {
        address notFlywheel = makeAddr("notFlywheel");
        bytes memory hookData = abi.encode(user);

        // Should work with flywheel address
        vm.prank(address(flywheel));
        hooks.onCreateCampaign(campaign, nonce, hookData);

        // Should revert with non-flywheel address
        vm.prank(notFlywheel);
        vm.expectRevert();
        hooks.onCreateCampaign(campaign, nonce, hookData);

        // Should revert with zero address
        vm.prank(address(0));
        vm.expectRevert();
        hooks.onCreateCampaign(campaign, nonce, hookData);
    }

    /// @notice Test constructor with zero address
    function test_constructor_withZeroAddress() public {
        // Should be able to create with zero address (no validation in constructor)
        TestCampaignHooks hooksWithZero = new TestCampaignHooks(address(0));
        assertEq(address(hooksWithZero.flywheel()), address(0));
    }
}
