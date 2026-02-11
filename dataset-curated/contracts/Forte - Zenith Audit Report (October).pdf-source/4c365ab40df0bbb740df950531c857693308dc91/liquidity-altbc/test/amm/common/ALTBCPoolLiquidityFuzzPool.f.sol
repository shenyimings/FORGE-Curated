// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ALTBCTestSetup, PoolBase} from "test/util/ALTBCTestSetup.sol";
import {packedFloat, MathLibs} from "lib/liquidity-base/src/amm/mathLibs/MathLibs.sol";
import {GenericERC20} from "lib/liquidity-base/src/example/ERC20/GenericERC20.sol";
import {QofMTestBase} from "test/equations/QofM/QofMTestBase.sol";
import {ALTBCEquations} from "src/amm/ALTBCEquations.sol";
import {ALTBCInput, ALTBCDef} from "src/amm/ALTBC.sol";
import {IERC20Errors} from "lib/liquidity-base/lib/openzeppelin-contracts/contracts/interfaces/draft-IERC6093.sol";
import {ALTBCPool, IERC20} from "src/amm/ALTBCPool.sol";
import {MathLibs, packedFloat} from "lib/liquidity-base/src/amm/mathLibs/MathLibs.sol";
import "lib/liquidity-base/src/common/IErrors.sol";
import {TestCommonSetup, LPToken} from "lib/liquidity-base/test/util/TestCommonSetup.sol";
import {IPoolEvents, ILPTokenEvents} from "lib/liquidity-base/src/common/IEvents.sol";
import "forge-std/console2.sol";

contract ALTBCPoolLiquidityFuzzPoolTest is TestCommonSetup, ALTBCTestSetup {
    using ALTBCEquations for ALTBCDef;
    using MathLibs for int256;
    using MathLibs for packedFloat;

    ALTBCPool _pool;

    uint256 constant MAX_SUPPLY = 1e9 * ERC20_DECIMALS;

    function setUp() public {
        _deployFactory();
        _setUpTokensAndFactories(MAX_SUPPLY);
        _loadAdminAndAlice();
    }

    function testLiquidity_fuzzedPool_PoolWithLPToken_UpdateLPTokenDeposit_InitialState(
        uint _lowerPrice,
        uint _V,
        uint _xMin,
        uint _C,
        uint _xAdd,
        uint __wInactive,
        uint A,
        uint B
    ) public {
        (_lowerPrice, _V, _xMin, _C, _xAdd, __wInactive) = boundPoolInputs(_lowerPrice, _V, _xMin, _C, _xAdd, __wInactive);
        A = bound(A, 1e18, 1e27);
        B = bound(B, 1e18, 1e27);
        _getFuzzedPool(_lowerPrice, _V, _xMin, _C, _xAdd, __wInactive);

        IERC20(_pool.xToken()).approve(address(_pool), type(uint256).max);
        IERC20(_pool.yToken()).approve(address(_pool), type(uint256).max);
        // we simulate to know what to expect
        (uint minAx, uint minAy, , , , ) = ALTBCPool(_pool).simulateLiquidityDeposit(A, B);
        // we test the event
        vm.expectEmit(true, true, false, false, address(lpToken));
        emit ILPTokenEvents.LPTokenUpdated(deployerActivePosition, packedFloat.wrap(0), packedFloat.wrap(0));
        console2.log("min", minAx, minAy);
        // now we can deposit
        _pool.depositLiquidity(2, A, B, minAx, minAy, getValidExpiration());
        (packedFloat wj, ) = lpToken.getLPToken(deployerActivePosition);
        uint256 _w = _pool.w();
        // At this point, admin owns the entire pool
        assertEq(uint(wj.convertpackedFloatToWAD()), _w - __wInactive);
    }

    function testLiquidity_fuzzedPool_PoolWithLPToken_UpdateLPTokenDeposit_InitialSwap(
        uint _lowerPrice,
        uint _V,
        uint _xMin,
        uint _C,
        uint _xAdd,
        uint __wInactive,
        uint sellYAmount,
        uint A,
        uint B
    ) public {
        (_lowerPrice, _V, _xMin, _C, _xAdd, __wInactive) = boundPoolInputs(_lowerPrice, _V, _xMin, _C, _xAdd, __wInactive);
        A = bound(A, 1e18, MAX_SUPPLY);
        B = bound(B, 1e18, MAX_SUPPLY);
        _getFuzzedPool(_lowerPrice, _V, _xMin, _C, _xAdd, __wInactive);
        sellYAmount = bound(sellYAmount, _lowerPrice * 60, (_lowerPrice * _xAdd) / 1e20);

        // GenericERC20(address(_pool.xToken())).mint(admin, initialX);
        IERC20(_pool.xToken()).approve(address(_pool), type(uint256).max);
        IERC20(_pool.yToken()).approve(address(_pool), type(uint256).max);
        // let's initialize x to a value different than xMin to make sure we can provide liquidity for both tokens
        _pool.swap(_pool.yToken(), sellYAmount, 1, address(0), getValidExpiration());
        // we simulate to know what to expect
        (uint minAx, uint minAy, , , , ) = ALTBCPool(_pool).simulateLiquidityDeposit(A, B);
        (packedFloat wjBefore, ) = lpToken.getLPToken(2);
        // we test the event
        vm.expectEmit(true, true, false, false, address(lpToken));
        emit ILPTokenEvents.LPTokenUpdated(deployerActivePosition, packedFloat.wrap(0), packedFloat.wrap(0));
        // now we can deposit
        _pool.depositLiquidity(deployerActivePosition, A, B, minAx, minAy, getValidExpiration());
        (packedFloat wj, ) = lpToken.getLPToken(2);
        uint256 _w = _pool.w();
        // B - 1 ≤ A ≤ B + 1  ==>   A ≤ B + 1 AND A + 1 ≥ B
        assertLe(uint(wj.convertpackedFloatToWAD()), _w - __wInactive + 1, "w above +1");
        assertGe(uint(wj.convertpackedFloatToWAD()) + 1, _w - __wInactive, "w belowe -1");

        uint availableRevenue = _pool.revenueAvailable(deployerActivePosition);
        _pool.withdrawRevenue(deployerActivePosition, availableRevenue, address(admin));

        (uint256 Ax, uint256 Ay, , , , , ) = _pool.simulateWithdrawLiquidity(
            deployerActivePosition,
            uint((wj.sub(wjBefore)).convertpackedFloatToWAD()) / 2,
            packedFloat.wrap(0)
        );

        _pool.withdrawPartialLiquidity(
            deployerActivePosition,
            uint((wj.sub(wjBefore)).convertpackedFloatToWAD()) / 2,
            address(0),
            Ax,
            Ay,
            getValidExpiration()
        );
    }

    function boundPoolInputs(
        uint _lowerPrice,
        uint _V,
        uint _xMin,
        uint _C,
        uint _xAdd,
        uint __wInactive
    ) internal pure returns (uint lowerPrice, uint V, uint xMin, uint C, uint xAdd, uint wInactive) {
        lowerPrice = bound(_lowerPrice, 1e16, 1e20);
        V = bound(_V, 1e14, 1e21);
        xMin = bound(_xMin, 1e18, MAX_SUPPLY / 1e6);
        C = bound(_C, 1e6, 1e41);
        xAdd = bound(_xAdd, 1e22, MAX_SUPPLY);
        console2.log("xAdd", xAdd);
        wInactive = bound(__wInactive, 0, (xAdd * 99) / 100);
        console2.log("wInactive", wInactive);
    }

    function _getFuzzedPool(uint _lowerPrice, uint _V, uint _xMin, uint _C, uint _xAdd, uint __wInactive) internal startAsAdmin {
        ALTBCInput memory _altbcInput = ALTBCInput(_lowerPrice, _V, _xMin, _C);
        xToken.approve(address(altbcFactory), MAX_SUPPLY * 2);
        _pool = ALTBCPool(altbcFactory.createPool(address(xToken), address(yToken), fees._lpFee, _altbcInput, _xAdd, __wInactive));
        assertEq(lpToken.currentTokenId(), 2);
        assertEq(lpToken.balanceOf(admin), 2);
        assertEq(_pool.w(), _xAdd);
        (packedFloat b, packedFloat c, packedFloat C, packedFloat xMin, packedFloat maxX, packedFloat V, ) = ALTBCPool(address(_pool))
            .tbc();
        (altbc.b, altbc.c, altbc.C, altbc.xMin, altbc.xMax, altbc.V) = (b, c, C, xMin, maxX, V);
    }
}
