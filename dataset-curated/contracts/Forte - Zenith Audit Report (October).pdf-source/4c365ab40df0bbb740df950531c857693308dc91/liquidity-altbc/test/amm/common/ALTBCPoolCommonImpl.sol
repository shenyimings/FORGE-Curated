// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

// import {ALTBCEquations} from "src/amm/ALTBCEquations.sol";
import "src/common/IALTBCEvents.sol";
import {PoolCommonAbs} from "liquidity-base/test/amm/common/PoolCommon.t.u.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import "forge-std/console2.sol";
import {ALTBCTestSetup, ALTBCPool, MathLibs, ALTBCDef, ALTBCEquations} from "test/util/ALTBCTestSetup.sol";
import {IFeeOnTransferERC20} from "liquidity-base/src/example/ERC20/FeeOnTransferERC20.sol";
import {IERC20Metadata} from "openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Metadata.sol";
/**
 * @title Test Pool functionality
 * @dev unit test
 * @author @oscarsernarosero @mpetersoCode55 @cirsteve
 */
contract ALTBCPoolCommonImpl is ALTBCTestSetup, PoolCommonAbs {
    using MathLibs for packedFloat;
    using MathLibs for int256;

    function _checkWithdrawRevenueState() internal override {
        uint256 balanceBefore = IERC20(pool.yToken()).balanceOf(admin);

        uint256 w = ALTBCPool(address(pool)).w();
        uint256 h = uint(ALTBCPool(address(pool)).retrieveH().convertpackedFloatToWAD());

        assertTrue(w > 0);
        assertEq(h, 0);

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

        vm.expectEmit(true, true, true, true, address(pool));
        emit IPoolEvents.RevenueWithdrawn(admin, 2, 1, admin);
        pool.withdrawRevenue(2, 1, address(admin));

        uint256 balanceAfter = IERC20(pool.yToken()).balanceOf(admin);
        w = ALTBCPool(address(pool)).w();
        h = uint(ALTBCPool(address(pool)).retrieveH().convertpackedFloatToWAD());

        assertGt(h, 0);
        assertEq((balanceBefore + h), balanceAfter);
    }

    function _checkRevenueState() internal override {
        (packedFloat b, packedFloat c, packedFloat C, packedFloat xMin, packedFloat xMax, packedFloat V, packedFloat Zn) = ALTBCPool(
            address(pool)
        ).tbc();
        altbc.b = b;
        altbc.c = c;
        altbc.C = C;
        altbc.xMin = xMin;
        altbc.xMax = xMax;
        altbc.V = V;
        altbc.Zn = Zn;

        bool dec = IERC20Metadata(address(_yToken)).decimals() == 18;
        packedFloat h = ALTBCPool(address(pool)).retrieveH();
        (packedFloat _wIanctive, ) = lpToken.getLPToken(pool.activeLpId());
        uint256 revenue = uint(h.mul(int(ALTBCPool(address(pool)).w()).toPackedFloat(-18).sub(_wIanctive)).convertpackedFloatToWAD());
        (dec, revenue);
        // TODO: come up with a better way to test revenue
        // uint totalRevenue = ALTBCPool(address(pool)).totalRevenue();

        // // ensure revenue thaso y token decimnals
        // revenue = dec ? revenue : revenue / 1e12;
        // totalRevenue = dec ? totalRevenue : totalRevenue / 1e12;
        // assertGe(totalRevenue, revenue - 1, "revenue too low");
        // assertLe(totalRevenue, revenue + 1, "revenue too high");
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
