// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {ALTBCTestSetup, PoolBase, TBCInputOption} from "test/util/ALTBCTestSetup.sol";
import {packedFloat, MathLibs} from "lib/liquidity-base/src/amm/mathLibs/MathLibs.sol";
import {QofMTestBase} from "test/equations/QofM/QofMTestBase.sol";
import {ALTBCEquations} from "src/amm/ALTBCEquations.sol";
import {ALTBCInput, ALTBCDef} from "src/amm/ALTBC.sol";
import {IERC20Errors} from "lib/liquidity-base/lib/openzeppelin-contracts/contracts/interfaces/draft-IERC6093.sol";
import {ALTBCPool, IERC20, SafeCast} from "src/amm/ALTBCPool.sol";
import {MathLibs, packedFloat, Float128} from "lib/liquidity-base/src/amm/mathLibs/MathLibs.sol";
import "lib/liquidity-base/src/common/IErrors.sol";
import {TestCommonSetup, LPToken} from "lib/liquidity-base/test/util/TestCommonSetup.sol";
import "forge-std/console2.sol";

contract ALTBCPoolLiquidity is TestCommonSetup, ALTBCTestSetup {
    ALTBCPool _pool1;
    ALTBCPool _pool2;

    using ALTBCEquations for ALTBCDef;
    using MathLibs for int256;
    using MathLibs for packedFloat;
    using Float128 for uint256;
    using SafeCast for uint;

    uint256 constant MAX_SUPPLY = 1e11 * ERC20_DECIMALS;
    uint xPurchase = MAX_SUPPLY / 10;

    function setUp() public {
        (PoolBase p1, PoolBase p2) = _setupDuplicatePools(false, 100);
        _pool1 = ALTBCPool(address(p1));
        _pool2 = ALTBCPool(address(p2));

        vm.startPrank(alice);

        (uint needed, , ) = _pool1.simSwapReversed(address(_pool1.xToken()), xPurchase);
        _pool1.swap(address(_pool1.yToken()), needed, xPurchase - 1, alice, getValidExpiration());

        (uint needed1, , ) = _pool2.simSwapReversed(address(_pool2.xToken()), xPurchase);
        _pool2.swap(address(_pool2.yToken()), needed1, xPurchase - 1, alice, getValidExpiration());
        vm.stopPrank();
    }

    function getCumulativeRevenueAvailable(ALTBCPool _pool, uint256 _start, uint256 _end) internal view returns (uint revenueAvailable) {
        while (_start <= _end) {
            uint _revenueAvailable = _pool.revenueAvailable(_start);
            revenueAvailable += _revenueAvailable;
            _start++;
        }
    }

    function getCumulativeTokens(
        uint256 _start,
        uint256 _end
    ) internal view returns (packedFloat wjTotal, packedFloat rjTotal, packedFloat claimedTotal) {
        while (_start <= _end) {
            (packedFloat wj, packedFloat rj) = lpToken.getLPToken(_start);
            wjTotal = wjTotal.add(wj);
            rjTotal = rjTotal.add(rj);
            claimedTotal = claimedTotal.add(wj.mul(rj));
            _start++;
        }
    }

    function testLiquidity_LastRevenueClaimEqualToNewTokenFuzz(uint256 deposit1, uint256 deposit2, uint256 swap) public {
        deposit1 = bound(deposit1, 1e6, xPurchase / 5);
        deposit2 = bound(deposit2, 1e6, xPurchase / 5);
        swap = bound(swap, 1e6, 1e20);
        packedFloat p1Rj;
        packedFloat p2Rj;
        packedFloat p2Rj1;
        packedFloat p1Wj;
        packedFloat p2Wj;
        packedFloat p2Wj1;

        vm.startPrank(alice);
        (uint minAx, uint minAy, , , , ) = ALTBCPool(_pool1).simulateLiquidityDeposit(deposit1, deposit1);
        _pool1.depositLiquidity(0, deposit1, deposit1, minAx, minAy, getValidExpiration()); //mint token 5
        _pool2.depositLiquidity(0, deposit1, deposit1, minAx, minAy, getValidExpiration()); //mint token 6
        (p1Wj, p1Rj) = lpToken.getLPToken(5);
        (p2Wj, p2Rj) = lpToken.getLPToken(6);

        assertTrue(p1Rj.mul(p1Wj).eq(p2Rj.mul(p2Wj)), "initial deposit rj should be equal");

        (uint needed, , ) = _pool1.simSwapReversed(address(_pool1.xToken()), swap);
        _pool1.swap(address(_pool1.yToken()), needed, swap / 2, msg.sender, getValidExpiration());

        (uint needed1, , ) = _pool2.simSwapReversed(address(_pool2.xToken()), swap);
        _pool2.swap(address(_pool2.yToken()), needed1, swap / 2, msg.sender, getValidExpiration());

        (minAx, minAy, , , , ) = ALTBCPool(_pool1).simulateLiquidityDeposit(deposit2, deposit2);
        _pool1.depositLiquidity(5, deposit2, deposit2, minAx, minAy, getValidExpiration());
        _pool2.depositLiquidity(0, deposit2, deposit2, minAx, minAy, getValidExpiration()); //mint token 7
        (p1Wj, p1Rj) = lpToken.getLPToken(5);
        (p2Wj, p2Rj) = lpToken.getLPToken(6);
        (p2Wj1, p2Rj1) = lpToken.getLPToken(7);

        assertTrue(p1Wj.eq(p2Wj.add(p2Wj1)), "p1Wj should equal p2Wj + p2Wj1");
        // assertTrue(p1Rj.mul(p1Wj).eq(p2Rj.mul(p2Wj).add(p2Rj1.mul(p2Wj1))), "after 2nd deposit cumulative rj should be equal");
        assertEq(
            p1Rj.mul(p1Wj).convertpackedFloatToWAD(),
            (p2Rj.mul(p2Wj).add(p2Rj1.mul(p2Wj1)).convertpackedFloatToWAD()),
            "after 2nd deposit cumulative rj should be equal"
        );

        vm.stopPrank();
    }

    function testLiquidity_LastRevenueClaimEqualToNewTokenStress() public {
        uint deposit1 = xPurchase / 2581;
        uint deposit2 = xPurchase / 1249;
        uint swap = 827214536456455645;
        packedFloat p1Rj;
        packedFloat p1Wj;
        packedFloat p2Rj;
        packedFloat p2Wj;
        packedFloat totalClaimed;
        vm.startPrank(alice);
        (uint minAx, uint minAy, , , , ) = ALTBCPool(_pool1).simulateLiquidityDeposit(deposit1, deposit1);
        _pool1.depositLiquidity(0, deposit1, deposit1, minAx, minAy, getValidExpiration()); //mint token 5
        _pool2.depositLiquidity(0, deposit1, deposit1, minAx, minAy, getValidExpiration()); //mint token 6

        for (uint i = 7; i < 1000; i++) {
            (uint needed, , ) = _pool1.simSwapReversed(address(_pool1.xToken()), swap);
            _pool1.swap(address(_pool1.yToken()), needed, swap / 2, alice, getValidExpiration());

            (uint needed1, , ) = _pool2.simSwapReversed(address(_pool2.xToken()), swap);
            _pool2.swap(address(_pool2.yToken()), needed1, swap / 2, alice, getValidExpiration());
            uint depositAmount = i % 2 == 0 ? deposit1 : deposit2;
            (minAx, minAy, , , , ) = ALTBCPool(_pool1).simulateLiquidityDeposit(depositAmount, depositAmount);
            _pool1.depositLiquidity(5, depositAmount, depositAmount, minAx, minAy, getValidExpiration());
            _pool2.depositLiquidity(0, depositAmount, depositAmount, minAx, minAy, getValidExpiration());
            (p1Wj, p1Rj) = lpToken.getLPToken(5);
            (p2Wj, p2Rj, totalClaimed) = getCumulativeTokens(6, i);

            assertEq(
                p1Rj.mul(p1Wj).convertpackedFloatToWAD(),
                totalClaimed.convertpackedFloatToWAD(),
                "rj * wj should be equal for both pools"
            );
        }

        vm.stopPrank();
    }

    function _generateRevenue(ALTBCPool _pool) internal startAsAdmin endWithStopPrank {
        uint swap = 100e18 - 87545686;
        uint needed;
        uint received;

        for (uint i = 0; i < 100; i++) {
            (needed, , ) = _pool.simSwapReversed(address(_pool.xToken()), swap);
            (received, , ) = _pool.swap(address(_pool.yToken()), needed, swap / 2, msg.sender, getValidExpiration());
            (needed, , ) = _pool.simSwap(address(_pool.xToken()), received);
            _pool.swap(address(_pool.xToken()), needed, received / 2, msg.sender, getValidExpiration());
        }
    }

    function testLiquidity_LastRevenueClaimEqualToNewTokenOnePool() public {
        uint deposit1 = xPurchase / 15000;

        packedFloat t3Rj;
        packedFloat t3Wj;
        packedFloat tcRj;
        packedFloat tcWj;
        packedFloat totalClaimed;
        packedFloat previoust3Rj;
        packedFloat previoustcRj;
        vm.startPrank(alice);
        (uint minAx, uint minAy, , , , ) = ALTBCPool(_pool1).simulateLiquidityDeposit(deposit1, deposit1);
        _pool1.depositLiquidity(0, deposit1, deposit1, minAx, minAy, getValidExpiration()); //mint token 5
        _pool1.depositLiquidity(0, deposit1, deposit1, minAx, minAy, getValidExpiration()); //mint token 6
        vm.stopPrank();

        for (uint i = 7; i < 1000; i++) {
            (, previoust3Rj) = lpToken.getLPToken(5);
            (, previoustcRj, ) = getCumulativeTokens(6, i - 1);
            _generateRevenue(_pool1);

            vm.startPrank(alice);
            uint depositAmount = deposit1; // i % 2 == 0 ? deposit1 : deposit2;
            (minAx, minAy, , , , ) = ALTBCPool(_pool1).simulateLiquidityDeposit(depositAmount, depositAmount);
            _pool1.depositLiquidity(5, depositAmount, depositAmount, minAx, minAy, getValidExpiration());
            _pool1.depositLiquidity(0, depositAmount, depositAmount, minAx, minAy, getValidExpiration()); //mint token 7+i
            (t3Wj, t3Rj) = lpToken.getLPToken(5);
            (tcWj, tcRj, totalClaimed) = getCumulativeTokens(6, i);

            assertEq(
                t3Rj.mul(t3Wj).convertpackedFloatToWAD(),
                totalClaimed.convertpackedFloatToWAD(),
                "rj * wj should be equal for both pools"
            );
        }

        vm.stopPrank();
    }

    function testLiquidity_LastRevenueClaimEqualToNewTokenDepositAndWithdraw() public {
        uint deposit1 = xPurchase / 1500000000;

        uint t3RevAvailable;
        uint tcRevAvailable;
        vm.startPrank(alice);
        uint initialTokenId = lpToken.currentTokenId() + 1;
        (uint minAx, uint minAy, , , , ) = ALTBCPool(_pool1).simulateLiquidityDeposit(deposit1, deposit1);
        _pool1.depositLiquidity(0, deposit1, deposit1, minAx, minAy, getValidExpiration()); //mint token 3
        _pool1.depositLiquidity(0, deposit1, deposit1, minAx, minAy, getValidExpiration()); // mint token 4
        vm.stopPrank();

        _generateRevenue(_pool1);

        for (uint i = initialTokenId + 2; i < 20; i++) {
            _generateRevenue(_pool1);
            vm.startPrank(alice);
            uint depositAmount = deposit1; // i % 2 == 0 ? deposit1 : deposit2;
            (minAx, minAy, , , , ) = ALTBCPool(_pool1).simulateLiquidityDeposit(depositAmount, depositAmount);
            _pool1.depositLiquidity(initialTokenId, depositAmount, depositAmount, minAx, minAy, getValidExpiration());
            _pool1.depositLiquidity(0, depositAmount, depositAmount, minAx, minAy, getValidExpiration());
            t3RevAvailable = getCumulativeRevenueAvailable(_pool1, initialTokenId, initialTokenId);
            tcRevAvailable = getCumulativeRevenueAvailable(_pool1, initialTokenId + 1, i);

            assertEq(t3RevAvailable / 1e6, tcRevAvailable / 1e6, "revenu available should be equal");
        }

        vm.stopPrank();
    }

    function testLiquidity_LastRevenueClaimEqualToNewTokenAmountRange() public {
        packedFloat t3Rj;
        packedFloat t3Wj;
        packedFloat tcRj;
        packedFloat tcWj;
        packedFloat totalClaimed;

        vm.startPrank(alice);
        (uint minAx, uint minAy, , , , ) = ALTBCPool(_pool1).simulateLiquidityDeposit(1, 1);
        uint initialTokenId = lpToken.currentTokenId() + 1;
        _pool1.depositLiquidity(0, 1, 1, minAx, minAy, getValidExpiration());
        _pool1.depositLiquidity(0, 1, 1, minAx, minAy, getValidExpiration());
        vm.stopPrank();

        for (uint i = initialTokenId + 2; i < 24; i++) {
            uint deposit = 10 ** (i - 4);

            _generateRevenue(_pool1);

            vm.startPrank(alice);
            uint depositAmount = deposit; // i % 2 == 0 ? deposit1 : deposit2;
            (minAx, minAy, , , , ) = ALTBCPool(_pool1).simulateLiquidityDeposit(depositAmount, depositAmount);
            _pool1.depositLiquidity(initialTokenId, depositAmount, depositAmount, minAx, minAy, getValidExpiration());
            _pool1.depositLiquidity(0, depositAmount, depositAmount, minAx, minAy, getValidExpiration());
            (t3Wj, t3Rj) = lpToken.getLPToken(initialTokenId);
            (tcWj, tcRj, totalClaimed) = getCumulativeTokens(initialTokenId + 1, i);

            assertEq(
                t3Rj.mul(t3Wj).convertpackedFloatToWAD(),
                totalClaimed.convertpackedFloatToWAD(),
                "rj * wj should be equal for both pools"
            );
        }

        vm.stopPrank();
    }

    function getH(ALTBCPool _pool) internal view returns (uint) {
        return uint(_pool.retrieveH().convertpackedFloatToWAD());
    }

    function testLiquidity_RevenueAccrualWithdrawMultpleLPTokens() public {
        uint deposit1 = xPurchase / 2000581;
        packedFloat latestTokenRj;
        packedFloat latestTokenWj;
        packedFloat previousTokenRj;
        packedFloat previousTokenWj;
        uint previousRevenue;

        vm.startPrank(alice);
        IERC20(address(_pool1.yToken())).approve(address(_pool1), deposit1 * 1001);
        //mint token and generate revenue for initial assertion
        (uint minAx, uint minAy, , , , ) = ALTBCPool(_pool1).simulateLiquidityDeposit(deposit1, deposit1);
        _pool1.depositLiquidity(0, deposit1, deposit1, minAx, minAy, getValidExpiration());
        vm.stopPrank();
        _generateRevenue(_pool1);

        uint hnDelta = MAX_SUPPLY;

        uint initialTokenId = lpToken.currentTokenId();
        uint limit = 1000;

        for (uint i = initialTokenId; i < limit; i++) {
            vm.startPrank(alice);
            (minAx, minAy, , , , ) = ALTBCPool(_pool1).simulateLiquidityDeposit(deposit1, deposit1);
            _pool1.depositLiquidity(0, deposit1, deposit1, minAx, minAy, getValidExpiration());
            vm.stopPrank();

            uint h = getH(_pool1);
            _generateRevenue(_pool1);

            uint hAfter = getH(_pool1);
            assertTrue(hAfter >= h, "h increases after swaps");
            assertTrue(hAfter - h <= hnDelta, "h increases after swaps");
            hnDelta = hAfter - h;

            (previousTokenWj, previousTokenRj) = lpToken.getLPToken(i);
            (latestTokenWj, latestTokenRj) = lpToken.getLPToken(i + 1);

            assertTrue(previousTokenWj.gt(latestTokenWj), "latest token minted should have lower wj than previous token");
            assertTrue(latestTokenRj.gt(previousTokenRj), "latest token minted should have greater rj than previous token");
        }

        for (uint i = limit; i < initialTokenId; i--) {
            uint aliceYBalance = IERC20(address(_pool1.yToken())).balanceOf(address(alice));
            uint revenueAvailable = _pool1.revenueAvailable(i);

            _pool1.withdrawRevenue(i, revenueAvailable, alice);

            uint aliceYBalanceAfter = IERC20(address(_pool1.yToken())).balanceOf(address(alice));

            assertEq(aliceYBalanceAfter - aliceYBalance, revenueAvailable, "balanceAfter - balanceBefore should equal reveue available");
            assertTrue(previousRevenue > revenueAvailable, "previous revenue should be greater than curent revenue");
            previousRevenue = revenueAvailable;
        }
    }

    function test_Liquidity_LiquidityDepositsPriceImpact() public {
        uint iterations = 1000;
        uint depositAmount = 1 * MathLibs.WAD;
        uint purchaseAmount = 1e18;
        uint previousSpendAmount = MAX_SUPPLY;
        uint previousPrice;
        uint previousW;
        uint wDelta;
        uint previousB;
        packedFloat previousWj = int(MAX_SUPPLY).toPackedFloat(18);
        uint userYBalance = IERC20(address(_pool1.yToken())).balanceOf(address(alice));
        vm.startPrank(alice);
        IERC20(address(xToken)).approve(address(_pool1), xPurchase);
        IERC20(address(_pool1.yToken())).approve(address(_pool1), userYBalance);
        uint tokenId = lpToken.currentTokenId() + 1;

        for (uint i = 0; i <= iterations; i++) {
            (uint spendAmount, , ) = _pool1.simSwapReversed(address(_pool1.xToken()), purchaseAmount);
            // (uint minAx, uint minAy, , , , ) = ALTBCPool(_pool1).simulateLiquidityDeposit(depositAmount, depositAmount); // stack too deep error
            (, uint B) = _pool1.depositLiquidity(0, depositAmount, userYBalance, 0, 0, getValidExpiration());
            (packedFloat wj, ) = lpToken.getLPToken(tokenId);

            if (previousB > 0) assertTrue(B == previousB, "b should be unchanged");
            assertTrue(previousW < _pool1.w(), "w should increase after deposit");
            if (previousPrice > 0) assertTrue(previousPrice == _pool1.spotPrice(), "price should be unchanged after deposit");
            assertTrue(spendAmount <= previousSpendAmount, "spend amount should decrease after deposit");
            if (wDelta > 0)
                assertTrue(
                    (_pool1.w() - previousW) / 10 == uint(wj.convertpackedFloatToWAD()) / 10,
                    "change in w should equal wj of minted token"
                );

            wDelta = _pool1.w() - previousW;
            previousW = _pool1.w();
            previousWj = wj;
            previousPrice = _pool1.spotPrice();
            previousSpendAmount = spendAmount;
            previousB = B;
            tokenId++;
        }
        vm.stopPrank();
    }

    function test_Liquidity_LiquidityWithdrawsPriceImpact() public {
        uint iterations = 1000;
        uint depositAmount = 1 * MathLibs.WAD;
        uint purchaseAmount = 1e18;
        uint previousSpendAmount;
        uint previousPrice;
        uint previousW = MAX_SUPPLY * 1000000000000;
        uint previousXBalance = IERC20(address(_pool1.xToken())).balanceOf(address(alice));
        uint previousYBalance = IERC20(address(_pool1.yToken())).balanceOf(address(alice));
        uint xBalanceDelta;
        uint yBalanceDelta;
        vm.startPrank(alice);
        IERC20(address(xToken)).approve(address(_pool1), xPurchase);
        IERC20(address(_pool1.yToken())).approve(address(_pool1), previousYBalance);
        uint initialTokenId = lpToken.currentTokenId() + 1;

        for (uint i = 0; i <= iterations; i++) {
            vm.startPrank(alice);
            // (uint minAx, uint minAy, , , , ) = ALTBCPool(_pool1).simulateLiquidityDeposit(depositAmount, previousYBalance); // stack too deep error
            _pool1.depositLiquidity(0, depositAmount, previousYBalance, 0, 0, getValidExpiration());
        }
        previousXBalance = IERC20(address(_pool1.xToken())).balanceOf(address(alice));
        previousYBalance = IERC20(address(_pool1.yToken())).balanceOf(address(alice));
        for (uint i = initialTokenId + iterations; i >= initialTokenId; i--) {
            (uint spendAmount, , ) = _pool1.simSwapReversed(address(_pool1.xToken()), purchaseAmount);

            (packedFloat wj, ) = lpToken.getLPToken(i);
            (uint minAx, uint minAy, , , , , ) = ALTBCPool(address(_pool1)).simulateWithdrawLiquidity(i, 0, wj);
            _pool1.withdrawAllLiquidity(i, alice, minAx, minAy, getValidExpiration());

            (wj, ) = lpToken.getLPToken(i);

            assertTrue(spendAmount >= previousSpendAmount, "spend amount should increase after withdrawal");
            assertTrue(_pool1.w() <= previousW, "w should be smaller after withdrawal");
            assertTrue(wj.eq(ALTBCEquations.FLOAT_0), "wj should be 0 after withdrawal");
            if (xBalanceDelta > 0)
                assertTrue(
                    IERC20(address(_pool1.xToken())).balanceOf(address(alice)) - xBalanceDelta == previousXBalance,
                    "A value should be unchanged after withdrawal"
                );
            if (yBalanceDelta > 0)
                assertTrue(
                    IERC20(address(_pool1.yToken())).balanceOf(address(alice)) - yBalanceDelta == previousYBalance,
                    "B value should be unchanged after withdrawal"
                );
            if (previousPrice > 0) assertTrue(previousPrice == _pool1.spotPrice(), "price should be unchanged after deposit");

            previousW = _pool1.w();
            previousSpendAmount = spendAmount;
            xBalanceDelta = IERC20(address(_pool1.xToken())).balanceOf(address(alice)) - previousXBalance;
            yBalanceDelta = IERC20(address(_pool1.yToken())).balanceOf(address(alice)) - previousYBalance;
            previousXBalance = IERC20(address(_pool1.xToken())).balanceOf(address(alice));
            previousYBalance = IERC20(address(_pool1.yToken())).balanceOf(address(alice));
            previousPrice = _pool1.spotPrice();
        }
        vm.stopPrank();
    }

    function test_Liquidity_DepositOfZeroLiquidityReverts() public {
        vm.startPrank(admin);
        vm.expectRevert(abi.encodeWithSignature("ZeroValueNotAllowed()"));
        _pool1.depositLiquidity(2, 0, 0, 0, 0, getValidExpiration());
    }

    function test_Liquidity_RevenueWithdrawOfZeroCollateralReverts() public {
        vm.startPrank(admin);
        vm.expectRevert(abi.encodeWithSignature("ZeroValueNotAllowed()"));
        _pool1.withdrawRevenue(2, 0, address(alice));
    }

    function test_Liquidity_WithdrawRevenue_QToPackedFloat_CorrectExponent() public {
        // Get a 6 decimal Y Token pool
        PoolBase pool = _setupPool(true);

        // Generate some revenue for admin
        vm.startPrank(alice);
        pool.swap(pool.yToken(), (100 * fullToken), 10, address(0), getValidExpiration());

        // Previous implementation
        packedFloat _Q = (pool.revenueAvailable(2).toInt256()).toPackedFloat(-18);

        // Confirm the amount of revenue available is 6 digits, at least 1 full Y Token
        assertEq(pool.revenueAvailable(2).findNumberOfDigits(), 6);

        // Confirm the amount entered gets correctly truncated
        vm.startPrank(admin);
        uint256 amount = uint(_Q.convertpackedFloatToSpecificDecimals(18));
        pool.withdrawRevenue(2, amount, address(admin));
    }
}
