/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {ALTBCTestSetup, ALTBCPool, MathLibs, packedFloat} from "test/util/ALTBCTestSetup.sol";
import {ALTBCDef} from "src/amm/ALTBC.sol";

import {ALTBCTestSetup} from "test/util/ALTBCTestSetup.sol";

import {ALTBCPool} from "src/amm/ALTBCPool.sol";
import {TestCommonSetup} from "lib/liquidity-base/test/util/TestCommonSetup.sol";

/**
 * @title Test Pool functionality
 * @dev unit test
 * @author @oscarsernarosero @mpetersoCode55 @cirsteve
 */
abstract contract ALTBCPoolStressTest is TestCommonSetup, ALTBCTestSetup {
    using MathLibs for packedFloat;

    uint8 constant MAX_TOLERANCE_X = 2;
    uint8 constant TOLERANCE_PRECISION_X = 17;
    uint256 constant TOLERANCE_DEN_X = 10 ** TOLERANCE_PRECISION_X;

    uint8 constant MAX_TOLERANCE_B = 5;
    uint8 constant TOLERANCE_PRECISION_B = 17;
    uint256 constant TOLERANCE_DEN_B = 10 ** TOLERANCE_PRECISION_B;

    uint8 constant TOLERANCE_PRECISION_B_WMATIC = 12;
    uint256 constant TOLERANCE_DEN_B_WMATIC = 10 ** TOLERANCE_PRECISION_B_WMATIC;

    uint8 constant MAX_TOLERANCE_C = 5;
    uint8 constant TOLERANCE_PRECISION_C = 16;
    uint256 constant TOLERANCE_DEN_C = 10 ** TOLERANCE_PRECISION_C;

    uint8 constant TOLERANCE_PRECISION_C_WMATIC = 13;
    uint256 constant TOLERANCE_DEN_C_WMATIC = 10 ** TOLERANCE_PRECISION_C_WMATIC;

    uint8 constant MAX_TOLERANCE_ABS_X = 2;
    uint8 constant TOLERANCE_PRECISION_ABS_X = 17;
    uint256 constant TOLERANCE_DEN_ABS_X = 10 ** TOLERANCE_PRECISION_ABS_X;

    string constant PATH = "./test/amm/stress/tradeData/simTrades";

    packedFloat previousSolX;
    uint previousPyX;
    uint previousSolBn;
    uint previousPyBn;
    uint previousSolCn;
    uint previousPyCn;

    bool withStableCoin;
    bool wEth;
    bool wMatic;

    function _setUp(bool _withStableCoin) internal endWithStopPrank {
        pool = _setupStressTestPool(_withStableCoin);
        withStableCoin = _withStableCoin;
        _yToken = IERC20(pool.yToken());
        fullToken = address(_yToken) == address(stableCoin) ? STABLECOIN_DEC : ERC20_DECIMALS;
    }

    function testLiquidity_ALTBCPoolUnit_simGeneratedSwaps() public startAsAdmin endWithStopPrank {
        vm.skip(true);
        uint count = 910;

        string memory fileEnd = withStableCoin ? "StableCoin-v1.1.txt" : "WETH-v1.1.txt";
        for (uint i = 0; i < count; i++) {
            string memory swap = vm.readLine(string.concat(PATH, fileEnd));
            uint swapAmount = vm.parseJsonUint(swap, ".swap_amount");
            uint x = vm.parseJsonUint(swap, ".x");
            uint buy = vm.parseJsonUint(swap, ".buy");
            uint bn = vm.parseJsonUint(swap, ".bn");
            uint cn = vm.parseJsonUint(swap, ".cn");

            if (buy == 1) {
                (uint expected, , ) = pool.simSwap(address(_yToken), swapAmount);
                pool.swap(address(_yToken), swapAmount, expected);
            } else {
                (uint256 expected, , ) = pool.simSwap(address(xToken), swapAmount);
                pool.swap(address(xToken), swapAmount, expected);
            }
            {
                // absolute x
                ALTBCPool basePool = ALTBCPool(address(pool));
                packedFloat xPool = basePool.x();
                assertTrue(
                    areWithinTolerance(x, uint(xPool.convertpackedFloatToWAD()), MAX_TOLERANCE_ABS_X, TOLERANCE_DEN_ABS_X),
                    "x out of tolerance"
                );

                // delta x
                uint deltaSolX = absoluteDiff(uint(xPool.convertpackedFloatToWAD()), uint(previousSolX.convertpackedFloatToWAD()));
                uint deltaPyX = absoluteDiff(x, previousPyX);
                assertTrue(areWithinTolerance(deltaSolX, deltaPyX, MAX_TOLERANCE_X, TOLERANCE_DEN_X), "delta x out of tolerance");
                previousSolX = xPool;
                previousPyX = x;
            }
            {
                (packedFloat b, , , , , , ) = ALTBCPool(address(pool)).tbc();

                uint deltaSolBn = absoluteDiff(uint(b.convertpackedFloatToDoubleWAD()), previousSolBn);
                uint deltaPyBn = absoluteDiff(bn, previousPyBn);
                if (wMatic)
                    assertTrue(
                        areWithinTolerance(deltaSolBn, deltaPyBn, MAX_TOLERANCE_B, TOLERANCE_DEN_B_WMATIC),
                        "delta bn out of tolerance - matic"
                    );
                else assertTrue(areWithinTolerance(deltaSolBn, deltaPyBn, MAX_TOLERANCE_B, TOLERANCE_DEN_B), "delta bn out of tolerance");

                previousSolBn = uint(b.convertpackedFloatToDoubleWAD());
                previousPyBn = bn;
            }
            {
                (, packedFloat c, , , , , ) = ALTBCPool(address(pool)).tbc();

                uint deltaSolCn = absoluteDiff(uint(c.convertpackedFloatToDoubleWAD()), previousSolCn);
                uint deltaPyCn = absoluteDiff(cn, previousPyCn);

                if (wMatic)
                    assertTrue(
                        areWithinTolerance(deltaSolCn, deltaPyCn, MAX_TOLERANCE_C, TOLERANCE_DEN_C_WMATIC),
                        "cn out of tolerance - matic"
                    );
                else assertTrue(areWithinTolerance(deltaSolCn, deltaPyCn, MAX_TOLERANCE_C, TOLERANCE_DEN_C), "cn out of tolerance");

                previousSolCn = uint(c.convertpackedFloatToDoubleWAD());
                previousPyCn = cn;
            }
        }
    }
}

contract ALTBCStressTestStableCoin is ALTBCPoolStressTest {
    function setUp() public endWithStopPrank {
        _setUp(true);
    }
}

contract ALTBCStressTestWETH is ALTBCPoolStressTest {
    function setUp() public endWithStopPrank {
        _setUp(false);
    }
}
