/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/Pausable.sol";
import "forge-std/console2.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import "src/common/IEvents.sol";
import {GenericERC20FixedSupply} from "src/example/ERC20/GenericERC20FixedSupply.sol";
import {NoZeroTransferERC20} from "src/example/ERC20/NoZeroTransferERC20.sol";
import {SimplePriceOracle} from "src/example/SimplePriceOracle.sol";
import {PoolBase} from "src/amm/base/PoolBase.sol";
import {packedFloat, MathLibs} from "src/amm/mathLibs/MathLibs.sol";
import {CumulativePrice} from "src/amm/base/CumulativePrice.sol";
import {TestCommonSetup, TestCommonSetupAbs} from "test/util/TestCommonSetup.sol";
import {TBCInputOption} from "test/util/TestConstants.sol";
import {PoolCommonAbs} from "test/amm/common/PoolCommonAbs.sol";
import "src/common/IErrors.sol";
/**
 * @title Test Pool functionality
 * @dev unit test
 * @author @oscarsernarosero @mpetersoCode55 @cirsteve
 */
abstract contract PoolCommonTest is TestCommonSetup, PoolCommonAbs {
    using MathLibs for packedFloat;
    using MathLibs for int256;

    function testLiquidity_Pool_version() public view {
        assertEq(pool.VERSION(), "v0.2.0");
    }

    function testLiquidity_Pool_TokensMustNotBeTheSame() public {
        vm.expectRevert(abi.encodeWithSignature("XandYTokensAreTheSame()"));
        _deployPool(address(yToken), address(yToken), 0, X_TOKEN_MAX_SUPPLY, TBCInputOption.BASE);
    }

    function testLiquidity_Pool_enableSwaps_Positive() public startAsAdmin {
        bool isPaused = pool.paused();
        assertFalse(isPaused, "setup function should've already activated trading");
        vm.expectEmit(true, true, true, true, address(pool));
        emit Pausable.Paused(admin);
        pool.enableSwaps(false);
        isPaused = pool.paused();
        assertTrue(isPaused, "Pool should be paused after deactivation");
        vm.expectEmit(true, true, true, true, address(pool));
        emit Pausable.Unpaused(admin);
        pool.enableSwaps(true);
        isPaused = pool.paused();
        assertFalse(isPaused, "Pool should not be paused after activation");
    }

    function testLiquidity_Pool_enableSwaps_NotOwner() public startAsAdmin endWithStopPrank {
        bool isPaused = pool.paused();
        assertFalse(isPaused, "Pool should not be initially paused");
        pool.enableSwaps(false);
        isPaused = pool.paused();
        assertTrue(isPaused, "Pool should be paused after deactivation");
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", alice));
        vm.startPrank(alice);
        pool.enableSwaps(true);
    }

    function _deenableSwaps() internal startAsAdmin {
        vm.expectEmit(true, true, true, true, address(pool));
        emit Pausable.Paused(admin);
        pool.enableSwaps(false);
    }

    function testLiquidity_Pool_deenableSwaps_Positive() public {
        _deenableSwaps();
        bool isPaused = pool.paused();
        assertTrue(isPaused, "Pool should be paused after deactivation");
    }

    function testLiquidity_Pool_deenableSwaps_NotOwner() public {
        bool isPaused = pool.paused();
        assertFalse(isPaused, "Pool should not be initially paused");
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", alice));
        pool.enableSwaps(false);
    }

    function testLiquidity_Pool_setLPFee_Positive() public startAsAdmin {
        uint16 initialFee = pool.lpFee();
        uint16 feeUpdate = 500;
        uint16 updatedFee = feeUpdate + initialFee;
        vm.expectEmit(true, true, true, true, address(pool));
        emit IPoolEvents.LPFeeSet(updatedFee);
        pool.setLPFee(updatedFee);
        uint16 fee = pool.lpFee();
        assertTrue(fee == updatedFee, "Fee should equal updatedFee");
        assertTrue(initialFee != fee, "Fee should not equal initialFee");
    }

    function testLiquidity_Pool_setLPFee_PositiveMax() public startAsAdmin {
        uint16 initialFee = pool.lpFee();
        // Max Total Fee 50%: 4_980(LP) + 20(Protocol) = 5_000
        uint16 feeUpdate = 4_980;
        vm.expectEmit(true, true, true, true, address(pool));
        emit IPoolEvents.LPFeeSet(feeUpdate);
        pool.setLPFee(feeUpdate);
        uint16 fee = pool.lpFee();
        assertTrue(fee == feeUpdate, "Fee should equal updatedFee");
        assertTrue(initialFee != fee, "Fee should not equal initialFee");
    }

    function testLiquidity_Pool_setLPFee_NotOwner() public {
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", alice));
        vm.prank(alice);
        pool.setLPFee(10);
    }

    function testLiquidity_Pool_setLPFee_ExcessFee() public startAsAdmin {
        (, bytes memory result) = address(pool).call(abi.encodeWithSignature("MAX_LP_FEE()"));
        uint16 maxFee = abi.decode(result, (uint16));
        uint16 excessFee = maxFee + 1;
        vm.expectRevert(abi.encodeWithSignature("LPFeeAboveMax(uint16,uint16)", excessFee, maxFee));
        pool.setLPFee(excessFee);
        assertTrue(excessFee == 4_981, "excess fee should be 4_980 + 1");
    }

    function testLiquidity_Pool_setProtocolFee_Positive(uint16 _fee) public {
        uint16 feeUpdate = uint16(bound(_fee, 0, 20));
        vm.startPrank(bob);
        vm.expectEmit(true, true, true, true, address(pool));
        emit CommonEvents.ProtocolFeeSet(feeUpdate);
        pool.setProtocolFee(feeUpdate);
        assertTrue(pool.protocolFee() == feeUpdate, "Fee should equal updatedFee");
    }

    function testLiquidity_Pool_setProtocolFee_NotProtocolCollector() public {
        vm.expectRevert(abi.encodeWithSignature("NotProtocolFeeCollector()"));
        vm.prank(alice);
        pool.setProtocolFee(20);
    }

    function testLiquidity_Pool_setProtocolFee_OverMax() public {
        address protocolFeeCollector = pool.protocolFeeCollector();
        console2.log(protocolFeeCollector);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSignature("ProtocolFeeAboveMax(uint16,uint16)", 21, 20));
        pool.setProtocolFee(21);
    }

    function _build_proposeNewProtocolFeeCollector() public {
        vm.prank(bob);
        vm.expectEmit(true, false, false, false, address(pool));
        emit CommonEvents.ProtocolFeeCollectorProposed(address(0xbabe));
        pool.proposeProtocolFeeCollector(address(0xbabe));
    }

    function testLiquidity_Pool_proposeNewProtocolFeeCollector_Positive() public {
        _build_proposeNewProtocolFeeCollector();
        assertEq(pool.proposedProtocolFeeCollector(), address(0xbabe));
    }

    function testLiquidity_Pool_proposeNewProtocolFeeCollector_NotProtocolFeeCollector(address proposer) public {
        if (proposer == bob) return;
        vm.prank(proposer);
        vm.expectRevert(abi.encodeWithSignature("NotProtocolFeeCollector()"));
        pool.proposeProtocolFeeCollector(address(0xbabe));
    }

    function testLiquidity_Pool_confirmNewProtocolFeeCollector_Positive() public {
        _build_proposeNewProtocolFeeCollector();
        vm.prank(address(0xbabe));
        vm.expectEmit(true, false, false, false, address(pool));
        emit CommonEvents.ProtocolFeeCollectorConfirmed(address(0xbabe));
        pool.confirmProtocolFeeCollector();
        assertEq(pool.protocolFeeCollector(), address(0xbabe));
    }

    function testLiquidity_Pool_confirmNewProtocolFeeCollector_NotProposedProtocolFeeCollector(address confirmer) public {
        if (confirmer == address(0xbabe)) return;
        _build_proposeNewProtocolFeeCollector();
        vm.prank(confirmer);
        vm.expectRevert(abi.encodeWithSignature("NotProposedProtocolFeeCollector()"));
        pool.confirmProtocolFeeCollector();
    }

    function _buildAddLiquidityGameToken() internal startAsAdmin endWithStopPrank returns (uint256 initialBalance, uint updatedBalance) {
        GenericERC20FixedSupply _xToken = new GenericERC20FixedSupply("X token", "X", X_TOKEN_MAX_SUPPLY);
        vm.stopPrank();
        PoolBase _pool = PoolBase(_deployPool(address(_xToken), address(_yToken), 30, X_TOKEN_MAX_SUPPLY, TBCInputOption.BASE));
        _approvePool(_pool, false);
        vm.startPrank(admin);
        uint amount = X_TOKEN_MAX_SUPPLY;
        initialBalance = _xToken.balanceOf(address(_pool));
        vm.expectEmit(true, true, true, true, address(_pool));
        emit IPoolEvents.LiquidityXTokenAdded(address(_xToken), amount);
        PoolBase(address(_pool)).addXSupply(amount);
        updatedBalance = _xToken.balanceOf(address(_pool));
    }

    function _buildLiquidityRemovalNotAllowed() internal returns (PoolBase _pool) {
        GenericERC20FixedSupply _xToken = new GenericERC20FixedSupply("X token", "X", X_TOKEN_MAX_SUPPLY);
        _pool = _deployPool(address(_xToken), address(_yToken), 30, X_TOKEN_MAX_SUPPLY, TBCInputOption.BASE);
        _approvePool(_pool, false);
        vm.startPrank(admin);
        _pool.enableSwaps(true);
    }

    function testLiquidity_PoolwithNoZeroTransferToken_transfer_amountZero() public {
        NoZeroTransferERC20 _xToken = new NoZeroTransferERC20("X token", "X");
        vm.expectRevert("cannot send 0 amount");
        _xToken.transfer(address(alice), 0);
    }

    function testLiquidity_Pool_withdrawRevenue_Positive() public startAsAdmin endWithStopPrank {
        // TODO Investigate this test. Silencing the slither warning
        //uint collectedLPFees = (3 * fullToken) / 1e6 + 1;
        (uint expected, , ) = pool.simSwap(address(_yToken), (1 * fullToken) / 1e3);
        pool.swap(address(_yToken), (1 * fullToken) / 1e3, expected);

        uint256 originalBalance = IERC20(_yToken).balanceOf(address(admin));


        ( , packedFloat rj) = pool.getLPToken(admin, 2);
        uint256 amount = pool.withdrawRevenue(2, uint(rj.convertpackedFloatToWAD()));
        uint256 updatedBalance = IERC20(_yToken).balanceOf(address(admin));
        uint256 expectedBalance = originalBalance + amount;
        assertEq(updatedBalance, expectedBalance);
    }

    function testLiquidity_Pool_withdrawRevenue_NotAuthorized() public endWithStopPrank {
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(InvalidToken.selector));
        pool.withdrawRevenue(2, 1);
    }

    function testLiquidity_Pool_buyGameToken_MaxSlippageReached() public startAsAdmin endWithStopPrank {
        uint16 maxSlippage = 300;
        uint pctDenom = 10_000;
        uint256 amountIn = 2 * 1e7 * (address(_yToken) == address(stableCoin) ? STABLECOIN_DEC : ERC20_DECIMALS);
        (uint expected, , ) = pool.simSwap(address(_yToken), amountIn);
        // we adjust expected to be higher than the actual amount expected inflated beyond slippage to force the reversion
        expected = (expected * pctDenom) / (pctDenom - uint(maxSlippage + 2)); // looks like + 1 didn't do the trick
        vm.expectRevert("max slippage reached");
        pool.swap(address(_yToken), amountIn, expected);
    }

    function testLiquidity_Pool_buyGameToken_Positive() public startAsAdmin endWithStopPrank {
        uint256 previous;
        uint256 amountIn = 2 * 1e7 * (address(_yToken) == address(stableCoin) ? STABLECOIN_DEC : ERC20_DECIMALS);
        uint256 startingLiquidity = pool.xTokenLiquidity();
        uint256 totalOut;
        uint counter;
        uint minSwapCount = 844;

        while (totalOut < startingLiquidity) {
            try pool.simSwap(address(_yToken), amountIn) returns (uint expected, uint expectedFeeAmount, uint expectedProtocolFee) {
                expectedProtocolFee;
                transferFee = 300;
                vm.expectEmit(true, true, true, true, address(pool));
                emit IPoolEvents.Swap(address(_yToken), amountIn, expected, getAmountSubFee(expected));
                try pool.swap(address(_yToken), amountIn, getAmountSubFee(expected)) returns (uint actual, uint actualFeeAmount, uint) {
                    counter++;
                    assertEq(actual, expected);
                    assertEq(expectedFeeAmount, actualFeeAmount);
                    previous = actual;
                    totalOut += actual;
                } catch {
                    break;
                }
            } catch {
                break;
            }
        }
        console2.log(counter);
        assertTrue(counter > minSwapCount, "Minimum swap count not reached");
    }

    function testLiquidity_Pool_buyGameToken_MinimumPositive() public startAsAdmin endWithStopPrank {
        uint256 previous;

        // get the price of a single token
        uint256 amountIn = pool.spotPrice();
        uint256 startingLiquidity = pool.xTokenLiquidity();
        uint256 totalOut;
        uint counter = 1;
        uint minimumSwapCount = 9;
        uint previousCollectedFees;

        while (totalOut + amountIn < startingLiquidity) {
            amountIn = counter * counter * amountIn;
            try pool.simSwap(address(_yToken), amountIn) returns (uint expected, uint expectedFeeAmount, uint pFee) {
                pFee;
                transferFee = 300;
                vm.expectEmit(true, true, true, true, address(pool));
                emit IPoolEvents.Swap(address(_yToken), amountIn, expected, getAmountSubFee(expected));
                (uint actual, uint actualFeeAmount, ) = pool.swap(address(_yToken), amountIn, getAmountSubFee(expected));
                counter++;
                assertEq(actual, expected);
                assertEq(expectedFeeAmount, actualFeeAmount);
                assertLt(previousCollectedFees, pool.collectedLPFees());
                previous = actual;
                totalOut += actual;
                previousCollectedFees = pool.collectedLPFees();
            } catch {
                break;
            }
        }
        assertTrue(counter >= minimumSwapCount, "Minimum swap count not reached");
    }

    function testLiquidity_Pool_buyGameToken_ExcessX() public startAsAdmin endWithStopPrank {
        (uint xMin, uint maxX) = _getMinMaxX(); // to avoid stack too deep
        address _yTokenAddress = address(pool.yToken());
        uint targetAmount = 1e18;
        address _xToken = pool.xToken();
        (uint expected, , ) = pool.simSwapReversed(_xToken, targetAmount);
        transferFee = 30;
        uint minOut = getAmountSubFee(targetAmount);
        (uint actual, , ) = pool.swap(_yTokenAddress, expected, minOut);
        assertEq(packedFloat.unwrap(pool.x()), packedFloat.unwrap(int(actual + xMin).toPackedFloat(-18)));
        uint outOfBoundAmount = maxX + 1 - xMin - actual;
        vm.expectRevert(abi.encodeWithSignature("XOutOfBounds(uint256)", 1)); // XOutOfBounds is impossible to be triggered in this scenario
        pool.simSwapReversed(_xToken, outOfBoundAmount);
    }

    function testLiquidity_Pool_LPFeesAccuracyInSimSwapReversed_BuyX(uint256 amount) public endWithStopPrank startAsAdmin {
        amount = bound(amount, 1 * ERC20_DECIMALS, 10_000 * ERC20_DECIMALS);
        (uint expectedIn, uint estimatedFees, ) = pool.simSwapReversed(address(pool.xToken()), amount);
        _yToken.approve(address(pool), expectedIn);
        vm.expectEmit(true, false, false, false, address(pool));
        emit IPoolEvents.LPFeeGenerated(estimatedFees);
        vm.expectEmit(true, false, false, false, address(pool));
        (uint256 expectedOut, , uint256 protocolFeeAmount) = pool.simSwap(address(_yToken), expectedIn);
        emit IPoolEvents.ProtocolFeeGenerated(protocolFeeAmount);
        (, uint fees, ) = pool.swap(address(_yToken), expectedIn, expectedOut);
        assertLe(fees, estimatedFees + 1); // we add 1 to account for rounding issues
        assertGe(fees, estimatedFees - 1); // we subtract 1 to account for rounding issues
    }

    function testLiquidity_Pool_LPFeesAccuracyInSimSwapReversed_BuyY(uint256 amount) public endWithStopPrank startAsAdmin {
        amount = bound(amount, 1 * fullToken, 10_000 * fullToken);
        uint initialAmount = 1_000_000 * fullToken;
        address _xToken = pool.xToken();
        // Set initial X value to something above 0 before starting to swap for X
        (uint expected, , ) = pool.simSwap(address(_yToken), initialAmount);
        pool.swap(address(_yToken), initialAmount, expected);
        /// now we test
        (uint expectedIn, uint estimatedFees, ) = pool.simSwapReversed(address(_yToken), amount);
        console2.log("expectedIn  ", expectedIn);
        if (transferFee > 0) {
            expectedIn = getAmountPlusFee(expectedIn);
            console2.log("expectedInU ", expectedIn);
        }
        console2.log("expected fees LP", estimatedFees);
        IERC20(pool.xToken()).approve(address(pool), expectedIn);
        vm.expectEmit(address(_yToken) == address(stableCoin), false, false, false, address(pool)); // Fees generated might be off by 1 unit in WETH case
        emit IPoolEvents.LPFeeGenerated(estimatedFees);
        vm.expectEmit(false, false, false, false, address(pool));
        emit IPoolEvents.ProtocolFeeGenerated(0);
        (, uint fees, ) = pool.swap(_xToken, expectedIn, getAmountSubFee(amount) - 1); // TODO look into the - 1 with fees
        assertLe(fees, estimatedFees + 1); // we add 1 to account for rounding issues
        assertGe(fees, estimatedFees - 1); // we subtract 1 to account for rounding issues
    }

    function testLiquidity_Pool_ProtocolFeesAccuracyInSimSwapReversed_BuyY(uint256 amount) public endWithStopPrank {
        _activateProtocolFeesInPool(pool);
        vm.startPrank(admin);
        amount = bound(amount, 1 * fullToken, 10_000 * fullToken);
        uint initialAmount = 1_000_000 * fullToken;
        address _xToken = pool.xToken();
        // Set initial X value to something above 0 before starting to swap for X
        (uint expected, , ) = pool.simSwap(address(_yToken), initialAmount);

        pool.swap(address(_yToken), initialAmount, getAmountSubFee(expected));
        /// now we test
        (uint expectedIn, uint lpFees, uint protocolFees) = pool.simSwapReversed(address(_yToken), amount);
        // todo: this looks fishy for FOT, we should investigate this
        IERC20(pool.xToken()).approve(address(pool), expectedIn);
        vm.expectEmit(false, false, false, false, address(pool)); // Fees generated might be off by 1 unit
        emit IPoolEvents.LPFeeGenerated(lpFees);
        vm.expectEmit(false, false, false, false, address(pool)); // Fees generated might be off by 1 unit
        emit IPoolEvents.ProtocolFeeGenerated(protocolFees);
        (, uint realLPFees, uint realProtocolFees) = pool.swap(_xToken, expectedIn, getAmountSubFee(amount - 1));
        if (transferFee == 0) {
            assertLe(realLPFees, lpFees + 1); // we add 1 to account for rounding issues
            assertGe(realLPFees, lpFees - 1); // we subtract 1 to account for rounding issues
            assertLe(realProtocolFees, protocolFees + 1); // we add 1 to account for rounding issues
            assertGe(realProtocolFees, protocolFees - 1); // we subtract 1 to account for rounding issues
        }
        vm.startPrank(bob);
        uint yBalanceBefore = _yToken.balanceOf(bob);
        uint protocolFeesCollected = pool.collectedProtocolFees();
        pool.collectProtocolFees();
        assertEq(protocolFeesCollected, (_yToken.balanceOf(bob) - yBalanceBefore));
    }

    function testLiquidity_Pool_FeesAreNeverZero_Reversed() public endWithStopPrank {
        _activateProtocolFeesInPool(pool);
        vm.startPrank(admin);
        uint minimumAmountTradeable = 13; // minimum amount tradeable
        uint amount = address(_yToken) == address(stableCoin) ? minimumAmountTradeable * (1e18 / 1e6) : minimumAmountTradeable; // minimum amount tradeable
        (uint expectedIn, uint lpFees, uint protocolFees) = pool.simSwapReversed(address(pool.xToken()), amount);
        if (transferFee > 0) expectedIn = getAmountPlusFee(expectedIn) + 1; // we add 1 for rounding issues
        assertGt(lpFees, 0);
        assertGt(protocolFees, 0);
        _yToken.approve(address(pool), expectedIn);
        (uint256 expectedOut, , ) = pool.simSwap(address(_yToken), expectedIn);
        (, uint realLPFees, uint realProtocolFees) = pool.swap(address(_yToken), expectedIn, expectedOut);
        assertEq(realLPFees, lpFees);
        assertEq(realProtocolFees, protocolFees);
    }

    function testLiquidity_Pool_LiquidityPreservation() public startAsAdmin endWithStopPrank {
        uint adminXBalanceInitial = IERC20(pool.xToken()).balanceOf(address(admin));
        /// buys x tokens in 7000 swaps of the same amount of y tokens
        uint256 amountIn = 1 * (address(_yToken) == address(stableCoin) ? STABLECOIN_DEC / 10 : ERC20_DECIMALS / 10);
        uint256 maxIterations = 7000;
        for (uint i; i < maxIterations; i++) {
            (uint out, , ) = pool.simSwap(address(_yToken), amountIn);
            pool.swap(address(_yToken), amountIn, out);
        }
        /// the sells the whole balance of x tokens at once
        uint adminXBalance = IERC20(pool.xToken()).balanceOf(address(admin)) - adminXBalanceInitial;
        console2.log("adminXBalance", adminXBalance);
        (uint expected, , ) = pool.simSwap(address(pool.xToken()), adminXBalance);
        console2.log("expected", expected);
        uint yBalance = IERC20(pool.yToken()).balanceOf(address(pool));
        console2.log("yBalance", yBalance);
        uint fees = pool.collectedLPFees();
        console2.log("fees", fees);
        uint yliq = pool.yTokenLiquidity();
        console2.log("yliq", yliq);
        console2.log("yBalance - fees", yBalance - fees);
        /// we check that the pool would have enough liquidity to buy back all the x tokens
        assertLe(expected, yliq, "not enough liquidity to buy back x tokens");

        if (transferFee > 0) {
            adminXBalance = getAmountPlusFee(adminXBalance);
        }
        IERC20(pool.xToken()).approve(address(pool), adminXBalance);
        pool.swap(address(pool.xToken()), adminXBalance, getAmountSubFee(expected));
        yliq = pool.yTokenLiquidity();
        console2.log("yliq", yliq);
    }

    function testLiquidity_Pool_LiquidityExcess(uint initialAmount) public virtual startAsAdmin endWithStopPrank {
        /// buys a large amount of x tokens at once
        uint256 maxIterations = 1000;
        initialAmount = bound(initialAmount, 100_000_000, 1_000_000_000);
        IERC20(pool.xToken()).transfer(alice, 1);
        uint256 xBalanceInitial = IERC20(pool.xToken()).balanceOf(admin);
        uint256 amountYIn = initialAmount * (address(_yToken) == address(stableCoin) ? STABLECOIN_DEC / 10 : ERC20_DECIMALS / 10);
        IERC20(pool.yToken()).approve(address(pool), amountYIn);
        (uint expected, , ) = pool.simSwap(address(_yToken), amountYIn);
        console2.log("init swap ", expected, amountYIn);
        (uint actual, , ) = pool.swap(address(_yToken), amountYIn, getAmountSubFee(expected));
        /// then sells it back in <maxIterations> trades of the same amount of y tokens
        uint256 xBalance = IERC20(pool.xToken()).balanceOf(admin);
        assertEq(getAmountSubFee(actual) + xBalanceInitial, xBalance);
        uint256 amountIn = (xBalance - xBalanceInitial) / maxIterations;
        uint256 lastAmountIn = (xBalance - xBalanceInitial) % maxIterations;
        for (uint i; i < maxIterations; i++) {
            uint adjustedAmountIn = amountIn;
            (expected, , ) = pool.simSwap(address(pool.xToken()), amountIn);
            if (transferFee > 0) {
                adjustedAmountIn = getAmountPlusFee(amountIn);
            }
            IERC20(pool.xToken()).approve(address(pool), adjustedAmountIn);
            pool.swap(address(pool.xToken()), adjustedAmountIn, getAmountSubFee(expected));
        }
        if (lastAmountIn > 0) {
            (expected, , ) = pool.simSwap(address(pool.xToken()), lastAmountIn);
            if (transferFee > 0) {
                lastAmountIn = getAmountPlusFee(lastAmountIn);
            }

            IERC20(pool.xToken()).approve(address(pool), lastAmountIn);

            if (expected > 0) pool.swap(address(pool.xToken()), lastAmountIn, getAmountSubFee(expected));
        }
        uint yBalance = IERC20(pool.yToken()).balanceOf(address(pool));
        console2.log("yBalance", yBalance);
        uint fees = pool.collectedLPFees();
        console2.log("fees", fees);
        uint yliq = pool.yTokenLiquidity();
        console2.log("yliq", yliq);
        console2.log("yBalance - fees:", yBalance - fees);
        _checkLiquidityExcessState();
    }

    function testLiquidity_Pool_backAndForthSwaps() public startAsAdmin endWithStopPrank {
        for (uint i = 0; i < 100; i++) {
            // 10 swaps in each direction back and forth
            for (uint j = 0; j < 10; j++) {
                uint256 previous = 0;
                (uint expected, uint expectedFeeAmount, ) = pool.simSwap(address(_yToken), (1 * fullToken));
                (uint actual, uint actualFeeAmount, ) = pool.swap(address(_yToken), (1 * fullToken), expected);
                if (previous > 0) {
                    assertLe(actual, previous);
                }
                assertEq(actual, expected);
                assertEq(expectedFeeAmount, actualFeeAmount);
                previous = actual;
            }

            _approvePool(pool, false);
            vm.startPrank(admin);
            for (uint j = 0; j < 10; j++) {
                uint256 previous = 0;
                uint256 amountIn = (1 * ERC20_DECIMALS) / 10;

                (uint256 expected, uint256 expectedFeeAmount, ) = pool.simSwap(address(pool.xToken()), amountIn);
                if (transferFee > 0) {
                    amountIn = getAmountPlusFee(amountIn);
                }
                (uint actual, uint actualFeeAmount, ) = pool.swap(address(pool.xToken()), amountIn, getAmountSubFee(expected));
                if (previous > 0) {
                    assertLe(actual, previous);
                }
                assertEq(actual, expected);
                assertEq(expectedFeeAmount, actualFeeAmount);
                previous = actual;
            }
        }
        uint yBalance = IERC20(pool.yToken()).balanceOf(address(pool));
        console2.log("yBalance", yBalance);
        uint fees = pool.collectedLPFees();
        console2.log("fees", fees);
        uint yliq = pool.yTokenLiquidity();
        console2.log("yliq", yliq);
        console2.log("yBalance - fees", yBalance - fees);
        _checkBackAndForthSwapsState();
    }

    function testLiquidity_Pool_buyCollateralToken_Positive() public endWithStopPrank {
        _approvePool(pool, false);
        vm.startPrank(admin);
        // Set initial X value to something above 0 before starting to swap for X
        (uint expected, uint feeAmount, ) = pool.simSwap(address(_yToken), 1_000 * fullToken);
        pool.swap(address(_yToken), 1_000 * fullToken, expected);
        uint256 previous = 0;

        for (uint i = 0; i < 100; i++) {
            uint amountIn = (1 * ERC20_DECIMALS) / 10;
            (expected, feeAmount, ) = pool.simSwap(address(pool.xToken()), amountIn);
            if (transferFee > 0) {
                amountIn = getAmountPlusFee(amountIn);
            }
            (uint actual, uint actualFeeAmount, ) = pool.swap(address(pool.xToken()), amountIn, getAmountSubFee(expected));
            if (previous > 0) {
                assertLe(actual, previous);
            }
            assertEq(actual, expected);
            assertEq(feeAmount, actualFeeAmount);
            previous = actual;
        }
    }

    function testLiquidity_Pool_buyGameTokenReversed_Positive() public endWithStopPrank {
        for (uint i; i < 100; i++) {
            _approvePool(pool, false);
            vm.startPrank(admin);
            uint expected = 1000 * ERC20_DECIMALS;
            (uint needed, , ) = pool.simSwapReversed(address(pool.xToken()), expected);
            transferFee = 30;
            (uint256 actual, , ) = pool.swap(address(_yToken), needed, getAmountSubFee(expected));
            uint256 difference;
            difference = expected > actual ? expected - actual : actual - expected;
            assertLe(difference, (expected * 30) / 10_000);
        }
    }

    function testLiquidity_Pool_buyCollateralTokenReversed_Positive() public endWithStopPrank {
        _approvePool(pool, false);
        vm.startPrank(admin);
        uint initialAmount = 1_000 * fullToken;
        // Set initial X value to something above 0 before starting to swap for X
        (uint expected, , ) = pool.simSwap(address(_yToken), initialAmount);
        pool.swap(address(_yToken), initialAmount, expected);
        for (uint i = 0; i < 100; i++) {
            uint amountOut = (1 * fullToken);
            (uint expectedIn, , ) = pool.simSwapReversed(address(_yToken), amountOut);
            if (transferFee > 0) {
                expectedIn = getAmountPlusFee(expectedIn);
            }
            (uint256 actual, , ) = pool.swap(address(pool.xToken()), expectedIn, amountOut - 300);
            uint256 difference = amountOut > actual ? amountOut - actual : actual - amountOut;
            assertLe(difference, 1);
        }
    }

    function testLiquidity_Pool_buyGameToken_Paused() public endWithStopPrank {
        (uint expected, , ) = pool.simSwap(address(_yToken), 1 * fullToken);
        _deenableSwaps();
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        pool.swap(address(_yToken), 1 * fullToken, expected);
    }

    function testLiquidity_recordCurveStateForSmallYTokenSales() public {
        uint256 amount = address(_yToken) == address(stableCoin) ? amountMinBound : 10;
        vm.startPrank(admin);
        uint initial_x = ((1 * fullToken));
        _yToken.approve(address(pool), initial_x);
        (uint256 toutOp, , ) = pool.simSwap(address(_yToken), initial_x);
        pool.swap(address(_yToken), initial_x, toutOp);

        uint256 priceBefore = pool.spotPrice();
        for (uint i; i < 1000; i++) {
            _yToken.approve(address(pool), amount);
            (toutOp, , ) = pool.simSwap(address(_yToken), amount);
            pool.swap(address(_yToken), amount, toutOp);
            uint256 priceAfter = pool.spotPrice();
            // assert(priceAfter >= priceBefore); /// PRICE VALLEY FOR URQTBC WETH
            priceBefore = priceAfter;
            /// example of how to write curve to csv. Enable if needed.
            // string[] memory inputs = _buildWriteCurveToCSV(
            //     i,
            //     Pool(address(pool)).x(),
            //     Pool(address(pool)).b(),
            //     Pool(address(pool)).c(),
            //     amount
            // );
            // vm.ffi(inputs);
        }
    }

    function testLiquidity_Pool_WithdrawRevenueAccrued_NotOwner() public startAsAdmin endWithStopPrank {
        _pool_BackAndForthSwaps();
        vm.stopPrank();
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSignature("InvalidToken()"));
        pool.withdrawRevenue(2, 0);
    }

    function testLiquidity_Pool_WithdrawRevenueAccrued_Positive() public startAsAdmin endWithStopPrank {
        //TODO determine how to test new revenue withdrawal mechanism
        vm.skip(true);
        _pool_BackAndForthSwaps();
        _checkWithdrawRevenueState();
    }

    function testLiquidity_Pool_CumulativePrice() public startAsAdmin endWithStopPrank {
        uint warpSeconds = 1000;
        uint cumulativePrice = CumulativePrice(address(pool)).cumulativePrice();
        uint lastBlockTimestamp = CumulativePrice(address(pool)).lastBlockTimestamp();
        uint spotPrice = pool.spotPrice();

        assertEq(cumulativePrice, 0, "cumulativePrice should initially be 0");
        assertEq(lastBlockTimestamp, 0, "lastBlockTimestamp should initially be 0");
        assertGt(spotPrice, 0, "spotPrice should initially be 0");

        (uint expected, , ) = pool.simSwap(address(_yToken), fullToken);
        vm.expectEmit(true, true, true, true, address(pool));
        emit IPoolEvents.CumulativePriceUpdated(vm.getBlockTimestamp(), spotPrice * vm.getBlockTimestamp());
        pool.swap(address(_yToken), fullToken, getAmountSubFee(expected));

        uint cumulativePrice1 = CumulativePrice(address(pool)).cumulativePrice();
        uint lastBlockTimestamp1 = CumulativePrice(address(pool)).lastBlockTimestamp();

        assertEq(
            cumulativePrice1,
            vm.getBlockTimestamp() * spotPrice,
            "cumulativePrice should equal spotPrice * block.timestamp after first trade"
        );
        assertEq(lastBlockTimestamp1, vm.getBlockTimestamp(), "lastBlockTimestamp should equal block.timestamp after first trade");
        vm.warp(warpSeconds);
        spotPrice = pool.spotPrice();
        (expected, , ) = pool.simSwap(address(_yToken), fullToken);

        vm.expectEmit(true, true, true, true, address(pool));
        emit IPoolEvents.CumulativePriceUpdated(
            vm.getBlockTimestamp(),
            spotPrice * (vm.getBlockTimestamp() - lastBlockTimestamp1) + cumulativePrice1
        );
        pool.swap(address(_yToken), fullToken, getAmountSubFee(expected));

        uint cumulativePrice2 = CumulativePrice(address(pool)).cumulativePrice();
        uint lastBlockTimestamp2 = CumulativePrice(address(pool)).lastBlockTimestamp();

        assertEq(
            cumulativePrice2,
            (vm.getBlockTimestamp() - lastBlockTimestamp1) * spotPrice + cumulativePrice1,
            "cumulativePrice should equal spotPrice * block.timestamp after second trade"
        );
        assertEq(lastBlockTimestamp2, vm.getBlockTimestamp(), "lastBlockTimestamp should equal block.timestamp after second trade");

        vm.warp(warpSeconds);
        spotPrice = pool.spotPrice();
        (expected, , ) = pool.simSwap(address(_yToken), fullToken);

        vm.expectEmit(true, true, true, true, address(pool));
        emit IPoolEvents.CumulativePriceUpdated(
            vm.getBlockTimestamp(),
            spotPrice * (vm.getBlockTimestamp() - lastBlockTimestamp2) + cumulativePrice2
        );
        pool.swap(address(_yToken), fullToken, getAmountSubFee(expected));

        uint cumulativePrice3 = CumulativePrice(address(pool)).cumulativePrice();
        uint lastBlockTimestamp3 = CumulativePrice(address(pool)).lastBlockTimestamp();

        assertEq(
            cumulativePrice3,
            (vm.getBlockTimestamp() - lastBlockTimestamp2) * spotPrice + cumulativePrice2,
            "cumulativePrice should equal spotPrice * block.timestamp after third trade"
        );
        assertEq(lastBlockTimestamp3, vm.getBlockTimestamp(), "lastBlockTimestamp should equal block.timestamp after third trade");
    }

    function testLiquidity_Pool_CumulativePriceExternalOracle() public startAsAdmin endWithStopPrank {
        uint baseWarp = 10;
        vm.warp(baseWarp);
        uint swapAmount = address(_yToken) == address(stableCoin) ? 40_000 * fullToken : fullToken;
        // Deploy oracle, 2 updates are required for the oracle to function
        SimplePriceOracle priceOracle = new SimplePriceOracle(address(pool));
        uint oraclePeriod = priceOracle.PERIOD();

        // Advance the block time, make a swap, update the oracle
        vm.warp(oraclePeriod + baseWarp);
        (uint expected, , ) = pool.simSwap(address(_yToken), swapAmount);
        pool.swap(address(_yToken), swapAmount, getAmountSubFee(expected));
        priceOracle.update();

        // Make the 2nd swap, update the oracle
        vm.warp(2 * oraclePeriod + baseWarp);
        (expected, , ) = pool.simSwap(address(_yToken), swapAmount);
        pool.swap(address(_yToken), swapAmount, getAmountSubFee(expected));
        priceOracle.update();

        // get the initial price values
        uint lastBlockTimestamp = CumulativePrice(address(pool)).lastBlockTimestamp();
        uint spotPrice = pool.spotPrice();
        uint priceAverage = priceOracle.priceAverage();

        // Make the 3rd swap, update the oracle
        vm.warp(3 * oraclePeriod + baseWarp);
        (expected, , ) = pool.simSwap(address(_yToken), swapAmount);
        pool.swap(address(_yToken), swapAmount, getAmountSubFee(expected));
        priceOracle.update();

        // get updated prices
        uint lastBlockTimestamp1 = CumulativePrice(address(pool)).lastBlockTimestamp();
        uint spotPrice1 = pool.spotPrice();
        uint priceAverage1 = priceOracle.priceAverage();

        assertGt(priceAverage1, priceAverage, "priceAverage should increase after initial swap and update");
        assertGt(lastBlockTimestamp1, lastBlockTimestamp, "lastBlockTimestamp should increase after initial swap and update");
        assertGt(spotPrice1, spotPrice, "spotPrice should increase after initial swap and update");

        // Make the 4th swap, update the oracle
        vm.warp(4 * oraclePeriod + baseWarp);
        (expected, , ) = pool.simSwap(address(_yToken), swapAmount);
        pool.swap(address(_yToken), swapAmount, getAmountSubFee(expected));
        priceOracle.update();

        // get the upodated price values
        lastBlockTimestamp = CumulativePrice(address(pool)).lastBlockTimestamp();
        spotPrice = pool.spotPrice();
        priceAverage = priceOracle.priceAverage();

        assertLt(priceAverage1, priceAverage, "priceAverage should increase after swap and update");
        assertLt(lastBlockTimestamp1, lastBlockTimestamp, "lastBlockTimestamp should increase after swap and update");
        assertLt(spotPrice1, spotPrice, "spotPrice should increase after swap and update");
    }

    function _pool_BackAndForthSwaps() internal {
        vm.stopPrank();
        uint amountIn = 1_000_000 * fullToken;
        for (uint i = 0; i < 100; i++) {
            // 10 swaps in each direction back and forth
            _approvePool(pool, false);
            vm.startPrank(admin);
            (uint expected, uint expectedFeeAmount, ) = pool.simSwap(address(_yToken), amountIn);
            (uint actual, uint actualFeeAmount, ) = pool.swap(address(_yToken), amountIn, getAmountSubFee(expected));
            (uint256 expectedBack, uint256 expectedFeeAmountBack, ) = pool.simSwap(address(pool.xToken()), actual);
            (uint actualBack, uint actualFeeAmountBack, ) = pool.swap(address(pool.xToken()), actual, getAmountSubFee(expectedBack));
            actualBack; // silence warnings
            actualFeeAmountBack; // silence warnings
            actualFeeAmount; // silence warnings
            expectedFeeAmount; // silence warnings
            expectedFeeAmountBack; // silence warnings
            vm.stopPrank();
        }
        vm.startPrank(admin);
    }
}
