// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {SetupGGVStrategy} from "./SetupGGVStrategy.sol";
import {GGVStrategy} from "src/strategy/GGVStrategy.sol";

contract RequestExitByWstethZeroTest is SetupGGVStrategy {
    function test_requestExitByWsteth_reverts_on_zero_amount() public {
        GGVStrategy.GGVParamsRequestExit memory params =
            GGVStrategy.GGVParamsRequestExit({discount: 0, secondsToDeadline: type(uint24).max});

        vm.prank(userAlice);
        vm.expectRevert(abi.encodeWithSelector(GGVStrategy.ZeroArgument.selector, "_wsteth"));
        ggvStrategy.requestExitByWsteth(0, abi.encode(params));
    }
}

