// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {Payments} from "../src/Payments.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {PaymentsTestHelpers} from "./helpers/PaymentsTestHelpers.sol";
import {BaseTestHelper} from "./helpers/BaseTestHelper.sol";
import {Errors} from "../src/Errors.sol";

contract AccessControlTest is Test, BaseTestHelper {
    Payments payments;
    PaymentsTestHelpers helper;

    uint256 constant DEPOSIT_AMOUNT = 100 ether;
    uint256 constant MAX_LOCKUP_PERIOD = 100;
    uint256 railId;

    function setUp() public {
        helper = new PaymentsTestHelpers();
        helper.setupStandardTestEnvironment();
        payments = helper.payments();

        // Setup operator approval
        helper.setupOperatorApproval(
            USER1,
            OPERATOR,
            10 ether, // rateAllowance
            100 ether, // lockupAllowance
            MAX_LOCKUP_PERIOD // maxLockupPeriod
        );

        // Deposit funds for client
        helper.makeDeposit(USER1, USER1, DEPOSIT_AMOUNT);

        // Create a rail for testing
        railId = helper.createRail(USER1, USER2, OPERATOR, address(0), SERVICE_FEE_RECIPIENT);

        // Set up rail parameters
        vm.startPrank(OPERATOR);
        payments.modifyRailPayment(railId, 1 ether, 0); // 1 ether per block
        payments.modifyRailLockup(railId, 10, 10 ether); // 10 block lockup period, 10 ether fixed
        vm.stopPrank();
    }

    function testTerminateRail_SucceedsWhenCalledByClient() public {
        vm.startPrank(USER1);
        payments.terminateRail(railId);
        vm.stopPrank();
    }

    function testTerminateRail_SucceedsWhenCalledByOperator() public {
        vm.startPrank(OPERATOR);
        payments.terminateRail(railId);
        vm.stopPrank();
    }

    function testTerminateRail_RevertsWhenCalledByRecipient() public {
        vm.startPrank(USER2);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.NotAuthorizedToTerminateRail.selector, railId, USER1, OPERATOR, USER2)
        );
        payments.terminateRail(railId);
        vm.stopPrank();
    }

    function testTerminateRail_RevertsWhenCalledByUnauthorized() public {
        vm.startPrank(address(0x99));
        vm.expectRevert(
            abi.encodeWithSelector(Errors.NotAuthorizedToTerminateRail.selector, railId, USER1, OPERATOR, address(0x99))
        );
        payments.terminateRail(railId);
        vm.stopPrank();
    }

    function testModifyRailLockup_SucceedsWhenCalledByOperator() public {
        vm.startPrank(OPERATOR);
        payments.modifyRailLockup(railId, 20, 20 ether);
        vm.stopPrank();
    }

    function testModifyRailLockup_RevertsWhenCalledByClient() public {
        vm.startPrank(USER1);
        vm.expectRevert(abi.encodeWithSelector(Errors.OnlyRailOperatorAllowed.selector, OPERATOR, USER1));
        payments.modifyRailLockup(railId, 20, 20 ether);
        vm.stopPrank();
    }

    function testModifyRailLockup_RevertsWhenCalledByRecipient() public {
        vm.startPrank(USER2);
        vm.expectRevert(abi.encodeWithSelector(Errors.OnlyRailOperatorAllowed.selector, OPERATOR, USER2));
        payments.modifyRailLockup(railId, 20, 20 ether);
        vm.stopPrank();
    }

    function testModifyRailLockup_RevertsWhenCalledByUnauthorized() public {
        vm.startPrank(address(0x99));
        vm.expectRevert(abi.encodeWithSelector(Errors.OnlyRailOperatorAllowed.selector, OPERATOR, address(0x99)));
        payments.modifyRailLockup(railId, 20, 20 ether);
        vm.stopPrank();
    }

    function testModifyRailPayment_SucceedsWhenCalledByOperator() public {
        vm.startPrank(OPERATOR);
        payments.modifyRailPayment(railId, 2 ether, 0);
        vm.stopPrank();
    }

    function testModifyRailPayment_RevertsWhenCalledByClient() public {
        vm.startPrank(USER1);
        vm.expectRevert(abi.encodeWithSelector(Errors.OnlyRailOperatorAllowed.selector, OPERATOR, USER1));
        payments.modifyRailPayment(railId, 2 ether, 0);
        vm.stopPrank();
    }

    function testModifyRailPayment_RevertsWhenCalledByRecipient() public {
        vm.startPrank(USER2);
        vm.expectRevert(abi.encodeWithSelector(Errors.OnlyRailOperatorAllowed.selector, OPERATOR, USER2));
        payments.modifyRailPayment(railId, 2 ether, 0);
        vm.stopPrank();
    }

    function testModifyRailPayment_RevertsWhenCalledByUnauthorized() public {
        vm.startPrank(address(0x99));
        vm.expectRevert(abi.encodeWithSelector(Errors.OnlyRailOperatorAllowed.selector, OPERATOR, address(0x99)));
        payments.modifyRailPayment(railId, 2 ether, 0);
        vm.stopPrank();
    }

    function testSettleTerminatedRailWithoutValidation_RevertsWhenCalledByOperator() public {
        // 2. Add more funds
        helper.makeDeposit(
            USER1,
            USER1,
            100 ether // Plenty of funds
        );

        // Terminate the rail
        vm.startPrank(USER1);
        payments.terminateRail(railId);
        vm.stopPrank();

        // Attempt to settle from operator account
        vm.startPrank(OPERATOR);
        vm.expectRevert(abi.encodeWithSelector(Errors.OnlyRailClientAllowed.selector, USER1, OPERATOR));
        payments.settleTerminatedRailWithoutValidation(railId);
        vm.stopPrank();
    }

    function testTerminateRail_OnlyOperatorCanTerminateWhenLockupNotFullySettled() public {
        // Advance blocks to create an unsettled state
        helper.advanceBlocks(500);

        // Client should not be able to terminate because lockup is not fully settled
        vm.startPrank(USER1);
        vm.expectRevert(
            abi.encodeWithSelector(Errors.NotAuthorizedToTerminateRail.selector, railId, USER1, OPERATOR, USER1)
        );
        payments.terminateRail(railId);
        vm.stopPrank();

        // Operator should be able to terminate even when lockup is not fully settled
        vm.startPrank(OPERATOR);
        payments.terminateRail(railId);
        vm.stopPrank();

        // Verify the rail was terminated by checking its end epoch is set
        Payments.RailView memory railView = payments.getRail(railId);
        assertTrue(railView.endEpoch > 0, "Rail was not terminated properly");
    }
}
