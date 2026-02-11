// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {TestCommonSetup} from "test/util/TestCommonSetup.sol";
import {InitialSwapHandler} from "test/amm/invariants/InitialSwapHandler.sol";
/**
 * @title Test the invariant that swaps selling token X will fail until the initial swap selling token Y
 * @dev invariant test
 * @author @oscarsernarosero @mpetersoCode55 @cirsteve
 */
abstract contract InitialSwapInvariant is TestCommonSetup {
    InitialSwapHandler _handler;
    function setUp() public endWithStopPrank {
        pool = _setupPool(false);
        _handler = new InitialSwapHandler(pool);
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = _handler.swap.selector;
        targetContract(address(_handler));
        targetSelector(FuzzSelector({addr: address(_handler), selectors: selectors}));
        targetSender(admin);
    }
    function invariant_initialSwapsOfXFail() public view {
        assertEq(_handler.trackedAmountOutX(), 0);
    }
}
