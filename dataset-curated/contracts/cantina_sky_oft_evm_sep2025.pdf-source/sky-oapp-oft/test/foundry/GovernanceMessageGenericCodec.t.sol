// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

import "forge-std/Test.sol";

import { GovernanceAction } from "../../contracts/IGovernanceController.sol";
import { GovernanceMessageGenericCodec } from "../../contracts/GovernanceMessageGenericCodec.sol";
import { GovernanceGenericCodecLibraryHelper } from "./helpers/GovernanceGenericCodecLibraryHelper.sol";

contract GovernanceMessageGenericCodecTest is Test {
    uint8 private constant ACTION_OFFSET = 0;
    uint8 private constant ORIGIN_CALLER_OFFSET = ACTION_OFFSET + 1;

    GovernanceGenericCodecLibraryHelper helper = new GovernanceGenericCodecLibraryHelper();

    function test_invalid_message_length() public {
        bytes memory message = abi.encodePacked(uint8(GovernanceAction.SOLANA_CALL), uint32(1), bytes32(0));
        helper.assertValidMessageLength(message);

        bytes memory messageTooShort = hex"0200000001000000000000000000000000000000000000000000000000000000";
        vm.expectRevert(abi.encodeWithSelector(GovernanceMessageGenericCodec.InvalidGenericMessageLength.selector));
        helper.assertValidMessageLength(messageTooShort);
    }
}
