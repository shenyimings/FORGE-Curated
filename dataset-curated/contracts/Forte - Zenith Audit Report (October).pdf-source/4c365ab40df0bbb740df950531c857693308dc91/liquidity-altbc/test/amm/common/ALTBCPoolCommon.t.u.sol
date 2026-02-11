// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {IERC20} from "src/amm/ALTBCPool.sol";
import "src/common/IALTBCEvents.sol";
import {ALTBCPoolCommonImpl} from "test/amm/common/ALTBCPoolCommonImpl.sol";
import {PoolCommonTest} from "liquidity-base/test/amm/common/PoolCommon.t.u.sol";
import {MathLibs, packedFloat} from "lib/liquidity-base/src/amm/mathLibs/MathLibs.sol";
import {QTooHigh, InvalidToken} from "lib/liquidity-base/src/common/IErrors.sol";
import {ALTBCCurveState} from "src/common/IALTBCEvents.sol";
import "forge-std/console2.sol";
import {ALTBCTestSetup, ALTBCPool, MathLibs, packedFloat} from "test/util/ALTBCTestSetup.sol";
/**
 * @title Test Pool functionality
 * @dev unit test
 * @author @oscarsernarosero @mpetersoCode55 @cirsteve
 */
abstract contract ALTBCPoolCommonTest is ALTBCPoolCommonImpl, PoolCommonTest {
    using MathLibs for packedFloat;
    using MathLibs for int256;

    function testLiquidity_Pool_deployment_CannotBeInitializedTwice() public {
        _deployAllowLists();
        _setupAllowLists();
        _setupFactory(address(altbcFactory));
        vm.startPrank(admin);
        address deployedPool = altbcFactory.createPool(address(xToken), address(yToken), 0, altbcInput, X_TOKEN_MAX_SUPPLY, 1);
        vm.expectRevert(abi.encodeWithSignature("InvalidInitialization()"));
        ALTBCPool(deployedPool).initializePool(admin, 1e19, 1);
        vm.stopPrank();
    }

    function testestLiquidity_Pool_verifyInitialState() public startAsAdmin {
        vm.expectEmit(true, true, true, true);
        emit ALTBCPoolDeployed(address(xToken), address(yToken), "v1.0.0", 0, 0, address(0xB0b), altbcInput);
        address deployedPool = altbcFactory.createPool(address(xToken), address(yToken), 0, altbcInput, X_TOKEN_MAX_SUPPLY, _wInactive);
        (packedFloat b, packedFloat c, packedFloat C, packedFloat xMin, packedFloat xMax, packedFloat V, packedFloat Z) = ALTBCPool(
            address(deployedPool)
        ).tbc();

        // V comparison
        (int256 mantissa, int256 exponent) = V.decode();
        packedFloat comparison = int(1e14).toPackedFloat(-18);
        (int256 comparisonMantissa, int256 comparisonExponent) = comparison.decode();
        assertEq(mantissa, comparisonMantissa, "V mantissa does not match");
        assertEq(exponent, comparisonExponent, "V exponent does not match");

        // xMin comparison
        (mantissa, exponent) = xMin.decode();
        comparison = int(1e18).toPackedFloat(-18);
        (comparisonMantissa, comparisonExponent) = comparison.decode();
        assertEq(mantissa, comparisonMantissa, "xMin mantissa does not match");
        assertEq(exponent, comparisonExponent, "xMin exponent does not match");

        // C comparison
        (mantissa, exponent) = C.decode();
        comparison = int(1e24).toPackedFloat(-18);
        (comparisonMantissa, comparisonExponent) = comparison.decode();
        assertEq(exponent, comparisonExponent, "C exponent does not match");
        assertEq(mantissa, comparisonMantissa, "C mantissa does not match");

        // b comparison
        (mantissa, exponent) = b.decode();
        assertEq(exponent, -48, "b exponent does not match");
        assertEq(mantissa, 99999900000099999900000099999900000099, "b mantissa does not match");

        // c comparison
        (mantissa, exponent) = c.decode();
        assertEq(exponent, -37, "c exponent does not match");
        assertEq(mantissa, 10000000000000000499999500000499999500, "c mantissa does not match");

        // xMax comparison
        (mantissa, exponent) = xMax.decode();
        assertEq(exponent, -26, "xMax exponent does not match");
        assertEq(mantissa, 10000000000100000000000000000000000000, "xMax mantissa does not match");

        // Z comparison
        (mantissa, exponent) = Z.decode();
        assertEq(exponent, -8192, "Z exponent does not match");
        assertEq(mantissa, 0, "Z mantissa does not match");
    }

    function testestLiquidity_Pool_deployment_NoInitialLiquidity() public startAsAdmin {
        vm.expectRevert(abi.encodeWithSignature("InactiveLiquidityExceedsLimit()"));
        altbcFactory.createPool(address(xToken), address(yToken), 0, altbcInput, 0, 1);
    }

    function testestLiquidity_Pool_deployment_CZero() public startAsAdmin {
        altbcInput._C = 0;
        vm.expectRevert(abi.encodeWithSignature("CCannotBeZero()"));
        altbcFactory.createPool(address(xToken), address(yToken), 0, altbcInput, X_TOKEN_MAX_SUPPLY, _wInactive);
    }

    function testestLiquidity_Pool_deployment_VZero() public startAsAdmin {
        altbcInput._V = 0;
        vm.expectRevert(abi.encodeWithSignature("VCannotBeZero()"));
        altbcFactory.createPool(address(xToken), address(yToken), 0, altbcInput, X_TOKEN_MAX_SUPPLY, _wInactive);
    }

    function testestLiquidity_Pool_deployment_xMinZero() public startAsAdmin {
        altbcInput._xMin = 0;
        vm.expectRevert(abi.encodeWithSignature("xMinCannotBeZero()"));
        altbcFactory.createPool(address(xToken), address(yToken), 0, altbcInput, X_TOKEN_MAX_SUPPLY, _wInactive);
    }

    function testestLiquidity_Pool_deployment_xAddZero() public startAsAdmin {
        vm.expectRevert(abi.encodeWithSignature("InactiveLiquidityExceedsLimit()"));
        altbcFactory.createPool(address(xToken), address(yToken), 0, altbcInput, 0, _wInactive);
    }
    function testestLiquidity_Pool_deployment_ActiveLiquidityZero() public startAsAdmin {
        uint __wInactive = X_TOKEN_MAX_SUPPLY;
        vm.expectRevert(abi.encodeWithSignature("InactiveLiquidityExceedsLimit()"));
        altbcFactory.createPool(address(xToken), address(yToken), 0, altbcInput, X_TOKEN_MAX_SUPPLY, __wInactive);
    }

    function testLiquidity_Pool_deploymentEvent() public startAsAdmin {
        IERC20(address(xToken)).approve(address(altbcFactory), X_TOKEN_MAX_SUPPLY);
        vm.expectEmit(true, true, true, true);
        emit ALTBCPoolDeployed(address(xToken), address(yToken), "v1.0.0", 0, 0, address(0xB0b), altbcInput);
        altbcFactory.createPool(address(xToken), address(yToken), 0, altbcInput, X_TOKEN_MAX_SUPPLY, _wInactive);
    }

    function testLiquidity_Pool_HighDecimalYToken() public {
        _setUpTokensAndFactories(X_TOKEN_MAX_SUPPLY);
        vm.startPrank(admin);
        IERC20(address(xToken)).approve(address(altbcFactory), X_TOKEN_MAX_SUPPLY);
        vm.expectRevert(abi.encodeWithSignature("YTokenDecimalsGT18()"));
        altbcFactory.createPool(address(xToken), address(highDecimalCoin), 30, altbcInput, X_TOKEN_MAX_SUPPLY, _wInactive);
    }

    function testLiquidity_Pool_HighDecimalXToken() public {
        _setUpTokensAndFactories(X_TOKEN_MAX_SUPPLY);
        vm.startPrank(admin);
        IERC20(address(xToken)).approve(address(altbcFactory), X_TOKEN_MAX_SUPPLY);
        vm.expectRevert(abi.encodeWithSignature("XTokenDecimalsIsNot18()"));
        altbcFactory.createPool(address(highDecimalCoin), address(stableCoin), 30, altbcInput, X_TOKEN_MAX_SUPPLY, _wInactive);
    }

    function testLiquidity_Pool_DepositInactiveLiquidity() public {
        vm.startPrank(admin);
        uint __wInactive = fullToken;
        address poolAddr = altbcFactory.createPool(address(xToken), address(yToken), 0, altbcInput, X_TOKEN_MAX_SUPPLY, __wInactive);
        uint inactiveId = ALTBCPool(poolAddr).inactiveLpId();
        uint A = 1e18;
        uint B = 1e18;
        (uint minAx, uint minAy, , , , ) = ALTBCPool(poolAddr).simulateLiquidityDeposit(A, B);
        vm.expectRevert(abi.encodeWithSignature("CannotDepositInactiveLiquidity()"));
        ALTBCPool(poolAddr).depositLiquidity(inactiveId, A, B, minAx, minAy, block.timestamp + 1);
    }

    function testLiquidity_Pool_WithdrawRevenueInactiveLiquidity() public {
        vm.startPrank(admin);
        uint __wInactive = fullToken;
        address poolAddr = altbcFactory.createPool(address(xToken), address(yToken), 0, altbcInput, X_TOKEN_MAX_SUPPLY, __wInactive);
        uint inactiveId = ALTBCPool(poolAddr).inactiveLpId();
        vm.expectRevert(abi.encodeWithSelector(InvalidToken.selector));
        ALTBCPool(poolAddr).withdrawRevenue(inactiveId, 1, address(admin));
    }

    function testLiquidity_Pool_EmitsStateEvent() public startAsAdmin {
        ALTBCDef memory state;
        packedFloat _x;
        address _yToken = pool.yToken();
        IERC20(_yToken).approve(address(pool), (10000 * fullToken));
        vm.expectEmit(true, false, false, false, address(pool));
        emit ALTBCCurveState(state, _x);
        pool.swap(_yToken, (1 * fullToken), 10, address(0), getValidExpiration());
        vm.expectEmit(true, false, false, false, address(pool));
        emit ALTBCCurveState(state, _x);
        // zero means new position
        uint A = (100 * fullToken);
        uint B = (100 * fullToken);
        (uint minAx, uint minAy, , , , ) = ALTBCPool(address(pool)).simulateLiquidityDeposit(A, B);
        ALTBCPool(address(pool)).depositLiquidity(0, A, B, minAx, minAy, block.timestamp + 1);
        emit ALTBCCurveState(state, _x);
        // last token id was 2, so we know now that the current id is 3
        (minAx, minAy, , , , , ) = ALTBCPool(address(pool)).simulateWithdrawLiquidity(3, 10 * fullToken, packedFloat.wrap(0));
        ALTBCPool(address(pool)).withdrawPartialLiquidity(3, 10 * fullToken, address(0), minAx, minAy, getValidExpiration());
        (packedFloat wj, ) = lpToken.getLPToken(3);
        (minAx, minAy, , , , , ) = ALTBCPool(address(pool)).simulateWithdrawLiquidity(3, 0, wj);
        emit ALTBCCurveState(state, _x);
        ALTBCPool(address(pool)).withdrawAllLiquidity(3, address(0), minAx, minAy, getValidExpiration());
    }

    function testLiquidity_Pool_depositLiquidity_expiredTransaction() public startAsAdmin {
        uint A = 1e18;
        uint B = 1e18;
        (uint minAx, uint minAy, , , , ) = ALTBCPool(address(pool)).simulateLiquidityDeposit(A, B);
        vm.expectRevert(abi.encodeWithSignature("TransactionExpired()"));
        ALTBCPool(address(pool)).depositLiquidity(0, A, B, minAx, minAy, block.timestamp - 1);

        uint warpTarget = block.timestamp + 10000000000;
        vm.warp(warpTarget);

        vm.expectRevert(abi.encodeWithSignature("TransactionExpired()"));
        ALTBCPool(address(pool)).depositLiquidity(0, A, B, minAx, minAy, warpTarget - 1);

        vm.expectRevert(abi.encodeWithSignature("TransactionExpired()"));
        ALTBCPool(address(pool)).depositLiquidity(0, A, B, minAx, minAy, warpTarget - 10000);
    }

    function testLiquidity_Pool_withdrawPartialLiquidity_expiredTransaction() public startAsAdmin {
        (uint256 minAx, uint256 minAy, , , , , ) = ALTBCPool(address(pool)).simulateWithdrawLiquidity(2, 1e18, packedFloat.wrap(0));
        vm.expectRevert(abi.encodeWithSignature("TransactionExpired()"));
        ALTBCPool(address(pool)).withdrawPartialLiquidity(2, 1e18, msg.sender, minAx, minAy, block.timestamp - 1);

        uint warpTarget = block.timestamp + 10000000000;
        vm.warp(warpTarget);

        vm.expectRevert(abi.encodeWithSignature("TransactionExpired()"));
        ALTBCPool(address(pool)).withdrawPartialLiquidity(2, 1e18, msg.sender, minAx, minAy, warpTarget - 1);

        vm.expectRevert(abi.encodeWithSignature("TransactionExpired()"));
        ALTBCPool(address(pool)).withdrawPartialLiquidity(2, 1e18, msg.sender, minAx, minAy, warpTarget - 10000);
    }

    function testLiquidity_Pool_withdrawAlllLiquidity_expiredTransaction() public startAsAdmin {
        vm.expectRevert(abi.encodeWithSignature("TransactionExpired()"));
        ALTBCPool(address(pool)).withdrawAllLiquidity(0, msg.sender, 0, 0, block.timestamp - 1);

        uint warpTarget = block.timestamp + 10000000000;
        vm.warp(warpTarget);

        vm.expectRevert(abi.encodeWithSignature("TransactionExpired()"));
        ALTBCPool(address(pool)).withdrawAllLiquidity(0, msg.sender, 0, 0, warpTarget - 1);

        vm.expectRevert(abi.encodeWithSignature("TransactionExpired()"));
        ALTBCPool(address(pool)).withdrawAllLiquidity(0, msg.sender, 0, 0, warpTarget - 10000);
    }
}

/**
 * @title Test Pool Stable Coin functionality
 * @dev unit test
 * @author @oscarsernarosero @mpetersoCode55
 */
contract PoolStableCoinTest is ALTBCPoolCommonTest {
    function setUp() public endWithStopPrank {
        _setupPool(true);
    }
}

/**
 * @title Test Pool WETH functionality
 * @dev unit test
 * @author @oscarsernarosero @mpetersoCode55
 */
contract PoolWETHTest is ALTBCPoolCommonTest {
    function setUp() public endWithStopPrank {
        _setupPool(false);
    }
}
