// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

/**
 * @title Test to verify invariants related to transactions when the contract is paused.
 * @dev unit test
 * @author @oscarsernarosero @mpetersoCode55 @cirsteve
 */
import {pausedAuthorizationHandler} from "test/authorization/invariants/pausedAuthorizationHandler.sol";
import {TestCommonSetup} from "test/util/TestCommonSetup.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
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
        _startingXLiquidity = IERC20(pool.xToken()).balanceOf(address(pool));
        _startingYLiquidity = IERC20(pool.yToken()).balanceOf(address(pool));
    }
    function invariant_verifyRevertsWhilePaused_removeLiquidityXToken() public view {
        // First argument is XToken Liquidity
        assertEq(IERC20(pool.xToken()).balanceOf(address(pool)), _startingXLiquidity);
    }
    function invariant_verifyRevertsWhilePaused_removeLiquidityYToken() public view {
        assertEq(IERC20(pool.yToken()).balanceOf(address(pool)), _startingYLiquidity);
    }
}
