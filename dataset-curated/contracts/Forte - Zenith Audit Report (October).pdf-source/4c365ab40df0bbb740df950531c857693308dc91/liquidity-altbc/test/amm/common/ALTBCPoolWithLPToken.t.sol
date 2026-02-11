// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {ALTBCTestSetup, PoolBase} from "test/util/ALTBCTestSetup.sol";
import {packedFloat, MathLibs} from "lib/liquidity-base/src/amm/mathLibs/MathLibs.sol";
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

contract ALTBCPoolWithLPToken is TestCommonSetup, ALTBCTestSetup {
    ALTBCPool _pool;

    using ALTBCEquations for ALTBCDef;
    using MathLibs for int256;
    using MathLibs for packedFloat;

    uint256 constant MAX_SUPPLY = 1e11 * ERC20_DECIMALS;

    function setUp() public {
        _deployFactory();
        _setUpTokensAndFactories(1e29);
        _loadAdminAndAlice();
        vm.startPrank(admin);

        xToken.approve(address(altbcFactory), MAX_SUPPLY * 2);
        _pool = ALTBCPool(altbcFactory.createPool(address(xToken), address(yToken), fees._lpFee, altbcInput, X_TOKEN_MAX_SUPPLY, 1));
        // Initial liquidity deposit with w0 is done in constructor

        assertEq(lpToken.currentTokenId(), 2);
        assertEq(lpToken.balanceOf(admin), 2);
        assertEq(_pool.w(), X_TOKEN_MAX_SUPPLY);

        (packedFloat b, packedFloat c, packedFloat C, packedFloat xMin, packedFloat maxX, packedFloat V, ) = ALTBCPool(address(_pool))
            .tbc();
        (altbc.b, altbc.c, altbc.C, altbc.xMin, altbc.xMax, altbc.V) = (b, c, C, xMin, maxX, V);
    }

    function testLiquidity_PoolWithLPToken_PurchaseAllXAndAddItBackAsLiquidity() public {
        (uint256 amountIn, uint256 lpFeeAmount, uint256 protocolFeeAmount) = _pool.simSwapReversed(address(xToken), X_TOKEN_MAX_SUPPLY);
        uint256 amountOut;
        vm.startPrank(address(admin));
        IERC20(address(yToken)).approve(address(_pool), amountIn);
        (amountOut, lpFeeAmount, protocolFeeAmount) = _pool.swap(
            address(yToken),
            amountIn,
            X_TOKEN_MAX_SUPPLY - 1,
            msg.sender,
            getValidExpiration()
        );
        IERC20(address(xToken)).approve(address(_pool), amountOut);
        uint adminYBalance = IERC20(address(xToken)).balanceOf(address(admin));
        IERC20(address(yToken)).approve(address(_pool), adminYBalance);
        (uint minAx, uint minAy, , , , ) = ALTBCPool(_pool).simulateLiquidityDeposit(amountOut, adminYBalance);
        uint currentTokenId = lpToken.currentTokenId();
        vm.expectEmit(true, true, true, true, address(_pool));
        emit IPoolEvents.PositionMinted(currentTokenId + 1, address(admin), false);
        _pool.depositLiquidity(0, amountOut, adminYBalance, minAx, minAy, getValidExpiration());
        vm.stopPrank();
    }

    function testLiquidity_PoolWithLPToken_UpdateLPTokenDeposit_InitialState(uint initialX, uint A, uint B) public {
        initialX = bound(initialX, 1e24, 1e25);
        A = bound(A, 1e18, 1e27);
        B = bound(B, 1e18, 1e27);

        IERC20(_pool.xToken()).approve(address(_pool), type(uint256).max);
        IERC20(_pool.yToken()).approve(address(_pool), type(uint256).max);
        // we simulate to know what to expect
        (uint minAx, uint minAy, , , , ) = ALTBCPool(_pool).simulateLiquidityDeposit(A, B);
        // we test the event
        vm.expectEmit(true, true, false, false, address(lpToken));
        emit ILPTokenEvents.LPTokenUpdated(deployerActivePosition, packedFloat.wrap(0), packedFloat.wrap(0));
        console2.log("min", minAx, minAy);
        // now we can deposit
        _pool.depositLiquidity(deployerActivePosition, A, B, minAx, minAy, getValidExpiration());
        (packedFloat wj, packedFloat rj) = lpToken.getLPToken(deployerActivePosition);
        uint256 _w = _pool.w();
        assertEq(rj.convertpackedFloatToWAD(), 10000000);
        // At this point, admin owns the entire pool
        assertEq(uint(wj.convertpackedFloatToWAD()), _w - _wInactive);
    }

    function testLiquidity_PoolWithLPToken_UpdateLPTokenDeposit_AfterSomeSwaps(uint initialX, uint A, uint B) public {
        initialX = bound(initialX, 1e24, 1e25);
        A = bound(A, 1e18, 1e27);
        B = bound(B, 1e18, 1e27);

        IERC20(_pool.xToken()).approve(address(_pool), type(uint256).max);
        IERC20(_pool.yToken()).approve(address(_pool), type(uint256).max);
        (uint sellYAmount, , ) = _pool.simSwapReversed(_pool.xToken(), initialX);
        // let's initialize x to a value different than xMin to make sure we can provide liquidity for both tokens
        _pool.swap(_pool.yToken(), sellYAmount, (initialX * 99) / 100, address(0), getValidExpiration());
        // we simulate to know what to expect
        (uint minAx, uint minAy, , , , ) = ALTBCPool(_pool).simulateLiquidityDeposit(A, B);
        // we test the event
        vm.expectEmit(true, true, false, false, address(lpToken));
        emit ILPTokenEvents.LPTokenUpdated(deployerActivePosition, packedFloat.wrap(0), packedFloat.wrap(0));
        console2.log("min", minAx, minAy);
        // now we can deposit
        _pool.depositLiquidity(deployerActivePosition, A, B, minAx, minAy, getValidExpiration());
        (packedFloat wj, ) = lpToken.getLPToken(deployerActivePosition);
        uint256 _w = _pool.w();
        assertEq(uint(wj.convertpackedFloatToWAD()), _w - _wInactive);
    }

    function testLiquidity_PoolWithLPToken_MultipleLPs() public {
        // TokenId 2
        uint256 A = 1e18;
        uint256 B = 1e18;
        uint256 _w0 = _pool.w();

        // Give some tokens to user 1 to deposit
        _tokenDistributionAndApproveHelper(address(_pool), address(1), A * 2, B * 2);
        vm.startPrank(address(1));
        (uint minAx, uint minAy, , , , ) = ALTBCPool(_pool).simulateLiquidityDeposit(A, B);
        // negative path testing max slippage
        vm.expectRevert(abi.encodeWithSignature("MaxSlippageReached()"));
        _pool.depositLiquidity(0, A, B, minAx + 1, minAy, getValidExpiration());
        vm.expectRevert(abi.encodeWithSignature("MaxSlippageReached()"));
        _pool.depositLiquidity(0, A, B, minAx + 1, minAy, getValidExpiration());
        // now we continue to test
        uint currentTokenId = lpToken.currentTokenId();
        vm.expectEmit(true, true, true, true, address(_pool));
        emit IPoolEvents.PositionMinted(currentTokenId + 1, address(1), false);
        _pool.depositLiquidity(0, A, B, minAx, minAy, getValidExpiration());
        (packedFloat wj, packedFloat rj) = lpToken.getLPToken(3);
        uint256 _w1 = _pool.w();
        // This value is coming from the _calculateRj method: (hn * wj + r_hat * w_hat) / w_hat + wj
        assertEq(uint(rj.convertpackedFloatToWAD()), 10000000);
        assertEq(uint(wj.convertpackedFloatToWAD()), 1000000000000000000, "a");
        assertGe(_w1 + 1, _w0 + uint(wj.convertpackedFloatToWAD()));
        assertLe(_w1, _w0 + uint(wj.convertpackedFloatToWAD()) + 1);

        // TokenId 3
        // Give some tokens to user 2 to deposit
        _tokenDistributionAndApproveHelper(address(_pool), address(2), A * 2, B * 2);
        vm.startPrank(address(2));
        (minAx, minAy, , , , ) = ALTBCPool(_pool).simulateLiquidityDeposit(A * 2, B * 2);
        currentTokenId = lpToken.currentTokenId();
        vm.expectEmit(true, true, true, true, address(_pool));
        emit IPoolEvents.PositionMinted(currentTokenId + 1, address(2), false);
        _pool.depositLiquidity(0, A * 2, B * 2, minAx, minAy, getValidExpiration());
        (wj, rj) = lpToken.getLPToken(4);
        uint256 _w2 = _pool.w();
        // This value is coming from the _calculateRj method: (hn * wj + r_hat * w_hat) / w_hat + wj
        assertEq(uint(rj.convertpackedFloatToWAD()), 10000000);
        assertEq(uint(wj.convertpackedFloatToWAD()), 1999999999999999999, "b");
        assertGe(_w2 + 1, _w1 + uint(wj.convertpackedFloatToWAD()));
        assertLe(_w2, _w1 + uint(wj.convertpackedFloatToWAD()) + 1);

        // TokenId 4
        // Give some tokens to user 3 to deposit
        _tokenDistributionAndApproveHelper(address(_pool), address(3), A * 100, B * 100);
        vm.startPrank(address(3));
        (minAx, minAy, , , , ) = ALTBCPool(_pool).simulateLiquidityDeposit(A * 100, B * 100);
        currentTokenId = lpToken.currentTokenId();
        vm.expectEmit(true, true, true, true, address(_pool));
        emit IPoolEvents.PositionMinted(currentTokenId + 1, address(3), false);
        _pool.depositLiquidity(0, A * 100, B * 100, minAx, minAy, getValidExpiration());
        (wj, rj) = lpToken.getLPToken(5);
        uint256 _w3 = _pool.w();
        // This value is coming from the _calculateRj method: (hn * wj + r_hat * w_hat) / w_hat + wj
        assertEq(uint(rj.convertpackedFloatToWAD()), 10000000);
        assertEq(uint(wj.convertpackedFloatToWAD()), 99999999999999999999, "c");
        assertGe(_w3 + 1, _w2 + uint(wj.convertpackedFloatToWAD()));
        assertLe(_w3, _w2 + uint(wj.convertpackedFloatToWAD()) + 1);

        // check that burning the inactive liquidity position won't affect the active positions for the deployer
        vm.startPrank(admin);
        uint inactiveId = _pool.inactiveLpId();
        uint balanceBefore = lpToken.balanceOf(admin);
        // burn the inactive position
        _pool.withdrawAllLiquidity(inactiveId, address(0), 0, 0, getValidExpiration());
        // we check the numbers
        (wj, rj) = lpToken.getLPToken(inactiveId);
        assertEq(balanceBefore - 1, lpToken.balanceOf(admin));
        assertTrue(lpToken.inactiveToken(inactiveId), "inactive token should be true");
        vm.expectRevert(abi.encodeWithSelector(URIQueryForNonexistentToken.selector));
        lpToken.tokenURI(inactiveId);
        assertEq(uint(rj.convertpackedFloatToWAD()), 0);
        assertEq(uint(wj.convertpackedFloatToWAD()), 0);
        _pool.withdrawPartialLiquidity(_pool.activeLpId(), 100, address(0), 0, 0, getValidExpiration());
    }

    function test_LPToken_PoolWithLPToken_PartialWithdrawal() public {
        // TokenId 2
        uint256 A = 1e29;
        uint256 B = 1e30;

        // Give some tokens to user 1 to deposit
        _tokenDistributionAndApproveHelper(address(_pool), address(1), A, B);

        vm.startPrank(address(1));

        // Swap to get some yTokens into the pool so it will allow liquidity deposits of Y
        (uint256 amountOut, , ) = _pool.simSwap(address(yToken), 2e18);
        _pool.swap(address(yToken), 2e18, amountOut - 1, msg.sender, getValidExpiration());

        (uint minAx, uint minAy, , , , ) = ALTBCPool(_pool).simulateLiquidityDeposit(A, (B - 2e18));
        _pool.depositLiquidity(0, A, (B - 2e18), minAx, minAy, getValidExpiration()); //mint tokenId 3
        vm.stopPrank();

        (packedFloat wj, ) = lpToken.getLPToken(_pool.activeLpId());
        vm.startPrank(admin);
        (minAx, minAy, , , , , ) = ALTBCPool(address(_pool)).simulateWithdrawLiquidity(
            2,
            uint(wj.div(int(2).toPackedFloat(0)).convertpackedFloatToWAD()),
            packedFloat.wrap(0)
        );
        // we test negative paths firts
        vm.expectRevert(abi.encodeWithSignature("MaxSlippageReached()"));
        _pool.withdrawPartialLiquidity(
            2,
            uint(wj.div(int(2).toPackedFloat(0)).convertpackedFloatToWAD()),
            address(0),
            minAx + 1,
            minAy,
            getValidExpiration()
        );
        vm.expectRevert(abi.encodeWithSignature("MaxSlippageReached()"));
        _pool.withdrawPartialLiquidity(
            2,
            uint(wj.div(int(2).toPackedFloat(0)).convertpackedFloatToWAD()),
            address(0),
            minAx,
            minAy + 1,
            getValidExpiration()
        );
        // now we continue to test
        vm.expectEmit(true, true, true, true, address(lpToken));
        emit ILPTokenEvents.LPTokenUpdated(
            2,
            packedFloat.wrap(57705225135662032204190496374263718726975624071957715172251658534216961884160),
            packedFloat.wrap(57556809982220647920505499384201313571606115424620663179769443613308481822975)
        );
        _pool.withdrawPartialLiquidity(
            2,
            uint(wj.div(int(2).toPackedFloat(0)).convertpackedFloatToWAD()),
            address(0),
            minAx,
            minAy,
            getValidExpiration()
        );
        (packedFloat wjUpdated, ) = lpToken.getLPToken(_pool.activeLpId());

        // Make sure the liquidity position is updated, and LPToken still in admin owned
        (packedFloat user1Wj, ) = lpToken.getLPToken(3);
        assertEq(uint(wjUpdated.convertpackedFloatToWAD()), _pool.w() - _wInactive - uint(user1Wj.convertpackedFloatToWAD()));
        assertEq(lpToken.balanceOf(address(admin)), 2);

        // Make sure the LPToken wasnt burned. This would revert if the token no longer exists
        lpToken.ownerOf(2);
        lpToken.tokenURI(2);
    }

    function test_LPToken_PoolWithLPToken_FullWithdrawal() public {
        // TokenId 2
        uint256 A = 1e29;
        uint256 B = 1e30;

        // Give some tokens to user 1 to deposit
        _tokenDistributionAndApproveHelper(address(_pool), address(1), A, B);

        vm.startPrank(address(1));
        // Swap to get some yTokens into the pool so it will allow liquidity deposits of Y
        (uint256 amountOut, , ) = _pool.simSwap(address(yToken), 2e18);
        _pool.swap(address(yToken), 2e18, amountOut - 1, msg.sender, getValidExpiration());

        (uint minAx, uint minAy, , , , ) = ALTBCPool(address(_pool)).simulateLiquidityDeposit(A, (B - 2e18));
        _pool.depositLiquidity(0, A, (B - 2e18), minAx, minAy, getValidExpiration());
        vm.stopPrank();

        (packedFloat wj, ) = lpToken.getLPToken(_pool.activeLpId());
        vm.startPrank(admin);

        vm.expectEmit(true, true, false, false, address(lpToken));
        emit ILPTokenEvents.LPTokenUpdated(1, packedFloat.wrap(0), packedFloat.wrap(0));
        _pool.withdrawAllLiquidity(1, admin, 0, 0, getValidExpiration());
        packedFloat _wj;
        packedFloat _rj;
        (minAx, minAy, , , , _wj, _rj) = ALTBCPool(address(_pool)).simulateWithdrawLiquidity(
            2,
            uint(wj.convertpackedFloatToWAD()),
            packedFloat.wrap(0)
        );
        vm.expectEmit(true, true, true, true, address(lpToken));
        emit ILPTokenEvents.LPTokenUpdated(2, packedFloat.wrap(0), _rj);
        _pool.withdrawAllLiquidity(2, admin, minAx, minAy, getValidExpiration());
        (packedFloat wjUpdated, ) = lpToken.getLPToken(_pool.activeLpId());

        // Make sure the liquidity position is reset, and LPToken representing the position is burned
        assertEq(packedFloat.unwrap(wjUpdated), 0);
        assertEq(lpToken.balanceOf(address(admin)), 0);

        // Expect revert when checking the burned token URI
        vm.expectRevert(abi.encodeWithSelector(URIQueryForNonexistentToken.selector));
        lpToken.tokenURI(2);
    }

    function test_LPToken_PoolWithLPToken_RevenueClaim() public {
        uint256 A = 1e18;
        uint256 B = 1e18;
        uint256 lps = 10;

        // Get alice in early
        _tokenDistributionAndApproveHelper(address(_pool), alice, A, B);
        vm.startPrank(alice);
        (uint minAx, uint minAy, , , , ) = ALTBCPool(_pool).simulateLiquidityDeposit(A, B);
        _pool.depositLiquidity(0, A, B, minAx, minAy, getValidExpiration());

        // Generate some revenue for alice
        for (uint160 i = 1; i < lps; ++i) {
            _tokenDistributionAndApproveHelper(address(_pool), address(i), A, B);
            vm.startPrank(address(i));
            (minAx, minAy, , , , ) = ALTBCPool(_pool).simulateLiquidityDeposit(A, B);
            _pool.depositLiquidity(0, A, B, minAx, minAy, getValidExpiration());
        }
        for (uint160 i = 1; i < lps; ++i) {
            _tokenDistributionAndApproveHelper(address(_pool), address(i), A, B);
            (uint expected, , ) = _pool.simSwap(address(yToken), B);
            vm.startPrank(address(i));
            _pool.swap(address(yToken), B, expected, msg.sender, getValidExpiration());
        }
        uint256 yBalanceBefore = IERC20(address(yToken)).balanceOf(alice);
        console2.log(yBalanceBefore);
        (packedFloat wj, ) = lpToken.getLPToken(3);
        vm.startPrank(alice);
        // Expect revert when Q is too high
        vm.expectRevert(abi.encodeWithSelector(QTooHigh.selector));
        _pool.withdrawRevenue(3, uint(wj.mul(int(2).toPackedFloat(0)).convertpackedFloatToWAD()), address(alice));

        vm.expectEmit(true, true, true, true, address(lpToken));
        emit ILPTokenEvents.LPTokenUpdated(
            3,
            packedFloat.wrap(57634551253070896831007164474234001986302524716082690413926794286165257093120),
            packedFloat.wrap(57556809982220647920505499384201313571606116424620663179769443613308481822975)
        );
        _pool.withdrawRevenue(3, 1000, address(alice));
    }

    function test_LPToken_PoolWithLPToken_Withdawal_RevertCases() public {
        vm.startPrank(admin);
        uint256 w = _pool.w();
        console2.log("w", w);
        // Expect revert when trying to withdraw 0 amount
        vm.expectRevert(abi.encodeWithSelector(ZeroValueNotAllowed.selector));
        _pool.withdrawPartialLiquidity(2, 0, admin, 0, 0, getValidExpiration());

        // Expect revert when trying to withdraw more than total w
        vm.expectRevert(abi.encodeWithSelector(LPTokenWithdrawalAmountExceedsAllowance.selector));
        _pool.withdrawPartialLiquidity(2, w + 1, admin, 0, 0, getValidExpiration());

        // Expect revert when non token owner tries updating a position
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(InvalidToken.selector));
        _pool.withdrawPartialLiquidity(2, w, admin, 0, 0, getValidExpiration());
    }

    function test_LPToken_PoolWithLPToken_NegativeInputs() public {
        // _pool_BackAndForthSwaps();
        vm.expectRevert(
            abi.encodeWithSignature(
                "SafeCastOverflowedUintToInt(uint256)",
                115792089237316195423570985008687907853269984665640564039457584007913129539936
            )
        );
        _pool.withdrawRevenue(2, uint(int(-100000)), address(0));

        vm.expectRevert(
            abi.encodeWithSignature(
                "SafeCastOverflowedUintToInt(uint256)",
                115792089237316195423570985008687907853269984665640564039457584007913129639935
            )
        );
        _pool.withdrawPartialLiquidity(2, uint(int(-1)), admin, 0, 0, getValidExpiration());

        vm.expectRevert(
            abi.encodeWithSignature(
                "SafeCastOverflowedUintToInt(uint256)",
                115792089237316195423570985008687907853269984665640564039457584007913129639935
            )
        );
        _pool.depositLiquidity(0, uint(int(-1)), 1e18, 0, 0, getValidExpiration());
        vm.expectRevert(
            abi.encodeWithSignature(
                "SafeCastOverflowedUintToInt(uint256)",
                115792089237316195423570985008687907853269984665640564039457584007913129639935
            )
        );
        _pool.depositLiquidity(0, 1e18, uint(int(-1)), 0, 0, getValidExpiration());
        vm.expectRevert(
            abi.encodeWithSignature(
                "SafeCastOverflowedUintToInt(uint256)",
                115792089237316195423570985008687907853269984665640564039457584007913129639935
            )
        );
        _pool.depositLiquidity(0, uint(int(-1)), uint(int(-1)), 0, 0, getValidExpiration());
    }
}
