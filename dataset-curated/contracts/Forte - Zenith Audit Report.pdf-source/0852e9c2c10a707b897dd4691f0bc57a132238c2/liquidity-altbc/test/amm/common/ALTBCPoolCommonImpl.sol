/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {ALTBCEquations} from "src/amm/ALTBCEquations.sol";
import "src/common/IALTBCEvents.sol";
import {PoolCommonAbs} from "liquidity-base/test/amm/common/PoolCommon.t.u.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import "forge-std/console2.sol";
import {ALTBCTestSetup, ALTBCPool, MathLibs, packedFloat} from "test/util/ALTBCTestSetup.sol";
import {IFeeOnTransferERC20} from "liquidity-base/src/example/ERC20/FeeOnTransferERC20.sol";

/**
 * @title Test Pool functionality
 * @dev unit test
 * @author @oscarsernarosero @mpetersoCode55 @cirsteve
 */
contract ALTBCPoolCommonImpl is ALTBCTestSetup, PoolCommonAbs {
    using MathLibs for packedFloat;

    function _checkLiquidityExcessState() internal override {
        uint yBalance = IERC20(pool.yToken()).balanceOf(address(pool));
        uint yliq = pool.yTokenLiquidity();

        (packedFloat b, packedFloat c, packedFloat C, packedFloat xMin, , packedFloat V, ) = ALTBCPool(address(pool)).tbc();

        altbc.b = b;
        altbc.c = c;
        altbc.C = C;
        altbc.xMin = xMin;
        altbc.V = V;

        /// we check that liquidity is exactly the same as the balance minus the fees (no liquidity excess)
        assertEq(
            (yBalance + pool.r()) - (pool.collectedProtocolFees() + pool.totalRevenue()),
            yliq,
            "not enough liquidity to buy back x tokens"
        );
    }

    function _checkWithdrawRevenueState() internal override {
        uint256 balanceBefore = IERC20(pool.yToken()).balanceOf(admin);

        uint256 HBefore = uint(ALTBCPool(address(pool)).h().convertpackedFloatToWAD());

        assertEq(HBefore, 0);
        packedFloat b;
        packedFloat xMin;
        packedFloat c;
        packedFloat C;
        packedFloat V;

        (b, c, C, xMin, , V, ) = ALTBCPool(address(pool)).tbc();

        altbc.b = b;
        altbc.c = c;
        altbc.C = C;
        altbc.xMin = xMin;
        altbc.V = V;

        // TODO Revisit this and associated test testLiquidity_Pool_WithdrawRevenueAccrued_Positive when RevenueWithdrawn event is included
        vm.expectEmit(true, true, true, true, address(pool));
        emit IPoolEvents.RevenueWithdrawn(admin, 1, 0);
        pool.withdrawRevenue(1, 1);

        uint256 balanceAfter = IERC20(pool.yToken()).balanceOf(admin);
        uint HAfter = uint(ALTBCPool(address(pool)).h().convertpackedFloatToWAD());

        assertGt(HAfter, 0);
        assertEq((balanceBefore + HAfter), balanceAfter);
    }

    function _checkBackAndForthSwapsState() internal override {
        uint yBalance = IERC20(pool.yToken()).balanceOf(address(pool));
        uint yliq = pool.yTokenLiquidity();
        (packedFloat b, packedFloat c, packedFloat C, packedFloat xMin, , packedFloat V, ) = ALTBCPool(address(pool)).tbc();
        altbc.b = b;
        altbc.c = c;
        altbc.C = C;
        altbc.xMin = xMin;
        altbc.V = V;

        assertEq(
            (yBalance + pool.r()) - (pool.collectedProtocolFees() + pool.totalRevenue()),
            yliq,
            "not enough liquidity to buy back x tokens"
        );
        /// we check that liquidity is exactly the same as the balance minus the fees (no liquidity excess)
    }

    function _getMinMaxX() internal view override returns (uint min, uint max) {
        packedFloat maxUnconv;
        packedFloat minUnconv;
        (, , , minUnconv, maxUnconv, , ) = ALTBCPool(address(pool)).tbc();
        min = uint(minUnconv.convertpackedFloatToWAD());
        max = uint(maxUnconv.convertpackedFloatToWAD());
        max = max + min;
    }
}
