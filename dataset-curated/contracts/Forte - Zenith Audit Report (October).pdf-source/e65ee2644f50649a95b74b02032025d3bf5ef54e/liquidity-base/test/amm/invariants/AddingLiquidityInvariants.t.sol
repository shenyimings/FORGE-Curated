// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {TestCommonSetup} from "test/util/TestCommonSetup.sol";
import {PoolBase} from "src/amm/base/PoolBase.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title Test all invariants in relation to adding liquidity to the pool.
 * @dev unit test
 * @author @oscarsernarosero @mpetersoCode55 @cirsteve
 */
abstract contract AddingLiquidityInvariants is TestCommonSetup {
    uint xTokenLiquidity;
    uint yTokenLiquidity;
    

    function _setUp(bytes4[] memory selectors) public endWithStopPrank {
        pool = _setupPool(false);
        uint amountToTrade = 50_000 * ERC20_DECIMALS;

        vm.startPrank(admin);
        (uint _expected, , ) = pool.simSwap(pool.yToken(), amountToTrade);
        pool.swap(pool.yToken(), amountToTrade, _expected, msg.sender, getValidExpiration());
        xTokenLiquidity = IERC20(pool.xToken()).balanceOf(address(pool));
        yTokenLiquidity = _getYTokenLiquidity(address(pool));
        vm.startPrank(admin);
        
        targetContract(address(pool));
        targetSelector(FuzzSelector({addr: address(pool), selectors: selectors}));
        targetSender(admin);
    }

    function invariant_liquidityCanNeverDecreaseCallingAddLiquidity_TokenX() public startAsAdmin {
        assertGe(IERC20(pool.xToken()).balanceOf(address(pool)), xTokenLiquidity);
    }

    function invariant_liquidityCanNeverDecreaseCallingAddLiquidity_TokenY() public {
        assertGe(_getYTokenLiquidity(address(pool)), yTokenLiquidity);
    }
}
