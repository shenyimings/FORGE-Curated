// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {AddingLiquidityInvariants} from "liquidity-base/test/amm/invariants/AddingLiquidityInvariants.t.sol";
import {ALTBCTestSetup} from "test/util/ALTBCTestSetup.sol";
import "forge-std/console2.sol";

contract ALTBCAddingLiquidityInvariants is AddingLiquidityInvariants, ALTBCTestSetup {
    function setUp() public endWithStopPrank {
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = 0x2f27872c;
        super._setUp(selectors);
    }
}
