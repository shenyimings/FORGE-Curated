/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

/**
 * @title Test to verify invariants related to transactions when the contract is paused.
 * @dev unit test
 * @author @oscarsernarosero @mpetersoCode55 @cirsteve
 */
import {pausedAuthorizationHandler} from "test/authorization/invariants/pausedAuthorizationHandler.sol";
import {TestCommonSetup} from "test/util/TestCommonSetup.sol";
abstract contract pausedAuthorizationInvariants is TestCommonSetup {
    uint256 _startingXLiquidity;
    uint256 _startingYLiquidity;
    pausedAuthorizationHandler handler;
    function setUp() public endWithStopPrank {
        pool = _setupPool(false);
        handler = new pausedAuthorizationHandler(pool);
        bytes4[] memory selectors = new bytes4[](1);
        selectors[0] = handler.swap.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
        targetSender(admin);
        vm.startPrank(admin);
        pool.enableSwaps(false);
        _startingXLiquidity = pool.xTokenLiquidity();
        _startingYLiquidity = pool.yTokenLiquidity();
    }
    function invariant_verifyRevertsWhilePaused_removeLiquidityXToken() public view {
        assertEq(pool.xTokenLiquidity(), _startingXLiquidity);
    }
    function invariant_verifyRevertsWhilePaused_removeLiquidityYToken() public view {
        assertEq(pool.yTokenLiquidity(), _startingYLiquidity);
    }
}
