// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/Pausable.sol";
import "forge-std/console2.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import "src/common/IEvents.sol";
import {GenericERC20FixedSupply} from "src/example/ERC20/GenericERC20FixedSupply.sol";
import {NoZeroTransferERC20} from "src/example/ERC20/NoZeroTransferERC20.sol";
import {PoolBase} from "src/amm/base/PoolBase.sol";
import {packedFloat, MathLibs} from "src/amm/mathLibs/MathLibs.sol";
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

    function testLiquidity_Pool_checkActiveLiquidityNFTAmount() public view {
        uint256 ACTIVE_LIQUIDITY_NFT_ID = pool.activeLpId();
        (packedFloat wj, ) = lpToken.getLPToken(ACTIVE_LIQUIDITY_NFT_ID);
        uint256 w = pool.w();
        (packedFloat _wIanctive, ) = lpToken.getLPToken(pool.inactiveLpId());
        uint256 wInactive = uint256(_wIanctive.convertpackedFloatToWAD());
        assertEq(w - wInactive, uint256(wj.convertpackedFloatToWAD()), "Active Liquidity NFT wj should equal active liquidity");
    }

    function testLiquidity_Pool_setLPFee_Positive() public startAsAdmin {
        (uint16 initialFee, , , , ) = pool.getFeeInfo();
        uint16 feeUpdate = 500;
        uint16 updatedFee = feeUpdate + initialFee;
        vm.expectEmit(true, true, true, true, address(pool));
        emit CommonEvents.FeeSet(CommonEvents.FeeCollectionType.LP, updatedFee);
        pool.setLPFee(updatedFee);
        (uint16 fee, , , , ) = pool.getFeeInfo();
        assertTrue(fee == updatedFee, "Fee should equal updatedFee");
        assertTrue(initialFee != fee, "Fee should not equal initialFee");
    }

    function testLiquidity_Pool_setLPFee_PositiveMax() public startAsAdmin {
        (uint16 initialFee, , , , ) = pool.getFeeInfo();
        // Max Total Fee 50%: 4_980(LP) + 20(Protocol) = 5_000
        uint16 feeUpdate = 4_980;
        vm.expectEmit(true, true, true, true, address(pool));
        emit CommonEvents.FeeSet(CommonEvents.FeeCollectionType.LP, feeUpdate);
        pool.setLPFee(feeUpdate);
        (uint16 fee, , , , ) = pool.getFeeInfo();
        assertTrue(fee == feeUpdate, "Fee should equal updatedFee");
        assertTrue(initialFee != fee, "Fee should not equal initialFee");
    }

    function testLiquidity_Pool_setLPFee_NotOwner() public {
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", alice));
        vm.prank(alice);
        pool.setLPFee(10);
    }

    function testLiquidity_Pool_setLPFee_ExcessFee() public startAsAdmin {
        (, bytes memory result) = address(pool).call(abi.encodeWithSignature("getPoolConstants()"));
        (, , , , uint16 maxFee) = abi.decode(result, (uint256, uint256, uint256, uint16, uint16));
        uint16 excessFee = maxFee + 1;
        vm.expectRevert(abi.encodeWithSignature("LPFeeAboveMax(uint16,uint16)", excessFee, maxFee));
        pool.setLPFee(excessFee);
        assertTrue(excessFee == 4_981, "excess fee should be 4_980 + 1");
    }

    function testLiquidity_Pool_setProtocolFee_Positive(uint16 _fee) public {
        uint16 feeUpdate = uint16(bound(_fee, 0, 20));
        vm.startPrank(bob);
        vm.expectEmit(true, true, true, true, address(pool));
        emit CommonEvents.FeeSet(CommonEvents.FeeCollectionType.PROTOCOL, feeUpdate);
        pool.setProtocolFee(feeUpdate);
        (, uint16 protocolFee, , , ) = pool.getFeeInfo();
        assertTrue(protocolFee == feeUpdate, "Fee should equal updatedFee");
    }

    function testLiquidity_Pool_setProtocolFee_NotProtocolCollector() public {
        vm.expectRevert(abi.encodeWithSignature("NotProtocolFeeCollector()"));
        vm.prank(alice);
        pool.setProtocolFee(20);
    }

    function testLiquidity_Pool_setProtocolFee_OverMax() public {
        (, , address protocolFeeCollector, , ) = pool.getFeeInfo();
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
        (, , , address proposedProtocolFeeCollector, ) = pool.getFeeInfo();
        assertEq(proposedProtocolFeeCollector, address(0xbabe));
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
        (, , address protocolFeeCollector, , ) = pool.getFeeInfo();
        assertEq(protocolFeeCollector, address(0xbabe));
    }

    function testLiquidity_Pool_confirmNewProtocolFeeCollector_NotProposedProtocolFeeCollector(address confirmer) public {
        if (confirmer == address(0xbabe)) return;
        _build_proposeNewProtocolFeeCollector();
        vm.prank(confirmer);
        vm.expectRevert(abi.encodeWithSignature("NotProposedProtocolFeeCollector()"));
        pool.confirmProtocolFeeCollector();
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
        (uint expected, , ) = pool.simSwap(address(_yToken), (1 * fullToken) / 1e3);
        pool.swap(address(_yToken), (1 * fullToken) / 1e3, expected, msg.sender, getValidExpiration());

        uint256 originalBalance = IERC20(_yToken).balanceOf(address(admin));

        lpToken.getLPToken(2);
        uint256 amount = pool.withdrawRevenue(2, pool.revenueAvailable(2), address(admin));
        uint256 updatedBalance = IERC20(_yToken).balanceOf(address(admin));
        uint256 expectedBalance = originalBalance + amount;
        assertEq(updatedBalance, expectedBalance);
    }

    function testLiquidity_Pool_withdrawRevenue_NotAuthorized() public endWithStopPrank {
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(InvalidToken.selector));
        pool.withdrawRevenue(2, 1, address(alice));
    }

    function testLiquidity_Pool_buyGameToken_MaxSlippageReached() public startAsAdmin endWithStopPrank {
        uint16 maxSlippage = 300;
        uint pctDenom = 10_000;
        uint256 amountIn = 2 * 1e7 * (address(_yToken) == address(stableCoin) ? STABLECOIN_DEC : ERC20_DECIMALS);
        (uint expected, , ) = pool.simSwap(address(_yToken), amountIn);
        // we adjust expected to be higher than the actual amount expected inflated beyond slippage to force the reversion
        expected = (expected * pctDenom) / (pctDenom - uint(maxSlippage + 2)); // looks like + 1 didn't do the trick
        vm.expectRevert(abi.encodeWithSelector(MaxSlippageReached.selector));
        pool.swap(address(_yToken), amountIn, expected, msg.sender, getValidExpiration());
    }

    function testLiquidity_Pool_buyGameToken_Positive() public startAsAdmin endWithStopPrank {
        uint256 previous;
        uint256 amountIn = 2 * 1e7 * (address(_yToken) == address(stableCoin) ? STABLECOIN_DEC : ERC20_DECIMALS);
        uint256 startingLiquidity = IERC20(pool.xToken()).balanceOf(address(pool));
        uint256 totalOut;
        uint counter;
        uint minSwapCount = 844;

        while (totalOut < startingLiquidity) {
            try pool.simSwap(address(_yToken), amountIn) returns (uint expected, uint expectedFeeAmount, uint expectedProtocolFee) {
                expectedProtocolFee;
                transferFee = 300;
                vm.expectEmit(true, true, true, true, address(pool));
                emit IPoolEvents.Swap(address(_yToken), amountIn, expected, getAmountSubFee(expected), msg.sender);
                try pool.swap(address(_yToken), amountIn, getAmountSubFee(expected), msg.sender, getValidExpiration()) returns (
                    uint actual,
                    uint actualFeeAmount,
                    uint
                ) {
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
        uint256 startingLiquidity = IERC20(pool.xToken()).balanceOf(address(pool));
        uint256 totalOut;
        uint counter = 1;
        uint minimumSwapCount = 9;

        while (totalOut + amountIn < startingLiquidity) {
            amountIn = counter * counter * amountIn;
            try pool.simSwap(address(_yToken), amountIn) returns (uint expected, uint expectedFeeAmount, uint pFee) {
                pFee;
                transferFee = 300;
                vm.expectEmit(true, true, true, true, address(pool));
                emit IPoolEvents.Swap(address(_yToken), amountIn, expected, getAmountSubFee(expected), msg.sender);
                (uint actual, uint actualFeeAmount, ) = pool.swap(
                    address(_yToken),
                    amountIn,
                    getAmountSubFee(expected),
                    msg.sender,
                    getValidExpiration()
                );
                counter++;
                assertEq(actual, expected);
                assertEq(expectedFeeAmount, actualFeeAmount);
                previous = actual;
                totalOut += actual;
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
        (uint actual, , ) = pool.swap(_yTokenAddress, expected, minOut, msg.sender, getValidExpiration());
        assertEq(packedFloat.unwrap(pool.x()), packedFloat.unwrap(int(actual + xMin).toPackedFloat(-18)));
        uint outOfBoundAmount = maxX + 1 - xMin - actual;
        vm.expectRevert(abi.encodeWithSignature("XOutOfBounds(uint256)", 1)); // XOutOfBounds is impossible to be triggered in this scenario
        pool.simSwapReversed(_xToken, outOfBoundAmount);
    }

    function testLiquidity_Pool_buyGameToken_ExpiredTransaction() public startAsAdmin endWithStopPrank {
        address yTokenAddr = pool.yToken();
        vm.expectRevert(abi.encodeWithSignature("TransactionExpired()"));
        pool.swap(yTokenAddr, 1, 1, msg.sender, block.timestamp - 1);

        uint warpTarget = block.timestamp + 10000000000;
        vm.warp(warpTarget);

        vm.expectRevert(abi.encodeWithSignature("TransactionExpired()"));
        pool.swap(yTokenAddr, 1, 1, msg.sender, warpTarget - 1);

        vm.expectRevert(abi.encodeWithSignature("TransactionExpired()"));
        pool.swap(yTokenAddr, 1, 1, msg.sender, warpTarget - 100000);
    }

    function testLiquidity_Pool_LPFeesAccuracyInSimSwapReversed_BuyX(uint256 amount) public endWithStopPrank startAsAdmin {
        amount = bound(amount, 1 * ERC20_DECIMALS, 10_000 * ERC20_DECIMALS);
        (uint expectedIn, uint estimatedFees, ) = pool.simSwapReversed(address(pool.xToken()), amount);
        _yToken.approve(address(pool), expectedIn);
        (uint256 expectedOut, , uint256 protocolFeeAmount) = pool.simSwap(address(_yToken), expectedIn);
        vm.expectEmit(true, true, false, false, address(pool));
        emit IPoolEvents.FeesGenerated(estimatedFees, protocolFeeAmount);
        (, uint fees, ) = pool.swap(address(_yToken), expectedIn, expectedOut, msg.sender, getValidExpiration());
        assertLe(fees, estimatedFees + 1); // we add 1 to account for rounding issues
        assertGe(fees, estimatedFees - 1); // we subtract 1 to account for rounding issues
    }

    function testLiquidity_Pool_LPFeesAccuracyInSimSwapReversed_BuyY(uint256 amount) public endWithStopPrank startAsAdmin {
        amount = bound(amount, 1 * fullToken, 10_000 * fullToken);
        uint initialAmount = 1_000_000 * fullToken;
        address _xToken = pool.xToken();
        // Set initial X value to something above 0 before starting to swap for X
        (uint expected, , ) = pool.simSwap(address(_yToken), initialAmount);
        pool.swap(address(_yToken), initialAmount, expected, msg.sender, getValidExpiration());
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
        emit IPoolEvents.FeesGenerated(estimatedFees, 0);
        (, uint fees, ) = pool.swap(_xToken, expectedIn, getAmountSubFee(amount) - 2, msg.sender, getValidExpiration());
        assertLe(fees, estimatedFees);
        assertGe(fees, estimatedFees);
    }

    function testLiquidity_Pool_ProtocolFeesAccuracyInSimSwapReversed_BuyY(uint256 amount) public endWithStopPrank {
        _activateProtocolFeesInPool(pool);
        vm.startPrank(admin);
        amount = bound(amount, 1 * fullToken, 10_000 * fullToken);
        uint initialAmount = 1_000_000 * fullToken;
        address _xToken = pool.xToken();
        // Set initial X value to something above 0 before starting to swap for X
        (uint expected, , ) = pool.simSwap(address(_yToken), initialAmount);

        pool.swap(address(_yToken), initialAmount, getAmountSubFee(expected) - 2, bob, getValidExpiration());
        /// now we test
        (uint expectedIn, uint lpFees, uint protocolFees) = pool.simSwapReversed(address(_yToken), amount);
        IERC20(pool.xToken()).approve(address(pool), expectedIn);
        vm.expectEmit(false, false, false, false, address(pool)); // Fees generated might be off by 1 unit
        emit IPoolEvents.FeesGenerated(lpFees, protocolFees);
        (, uint realLPFees, uint realProtocolFees) = pool.swap(_xToken, expectedIn, getAmountSubFee(amount) - 2, bob, getValidExpiration());
        if (transferFee == 0) {
            assertLe(realLPFees, lpFees + 1); // we add 1 to account for rounding issues
            assertGe(realLPFees, lpFees - 1); // we subtract 1 to account for rounding issues
            assertLe(realProtocolFees, protocolFees + 1); // we add 1 to account for rounding issues
            assertGe(realProtocolFees, protocolFees - 1); // we subtract 1 to account for rounding issues
        }
        vm.startPrank(bob);
        uint yBalanceBefore = _yToken.balanceOf(bob);
        (, , , , uint protocolFeesCollected) = pool.getFeeInfo();
        pool.collectProtocolFees(bob);
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
        (, uint realLPFees, uint realProtocolFees) = pool.swap(address(_yToken), expectedIn, expectedOut, msg.sender, getValidExpiration());
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
            pool.swap(address(_yToken), amountIn, out, admin, getValidExpiration());
        }
        /// the sells the whole balance of x tokens at once
        uint adminXBalance = IERC20(pool.xToken()).balanceOf(address(admin)) - adminXBalanceInitial;
        console2.log("adminXBalance", adminXBalance);
        (uint expected, , ) = pool.simSwap(address(pool.xToken()), adminXBalance);
        console2.log("expected", expected);
        uint yBalance = IERC20(pool.yToken()).balanceOf(address(pool));
        console2.log("yBalance", yBalance);
        /// we check that the pool would have enough liquidity to buy back all the x tokens
        // assertLe(expected, yliq, "not enough liquidity to buy back x tokens");

        if (transferFee > 0) {
            adminXBalance = getAmountPlusFee(adminXBalance);
        }
        IERC20(pool.xToken()).approve(address(pool), adminXBalance);
        pool.swap(address(pool.xToken()), adminXBalance, getAmountSubFee(expected), msg.sender, getValidExpiration());
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
        (uint actual, , ) = pool.swap(address(_yToken), amountYIn, getAmountSubFee(expected), admin, getValidExpiration());
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
            pool.swap(address(pool.xToken()), adjustedAmountIn, getAmountSubFee(expected), admin, getValidExpiration());
        }
        if (lastAmountIn > 0) {
            (expected, , ) = pool.simSwap(address(pool.xToken()), lastAmountIn);
            if (transferFee > 0) {
                lastAmountIn = getAmountPlusFee(lastAmountIn);
            }

            IERC20(pool.xToken()).approve(address(pool), lastAmountIn);

            if (expected > 0) pool.swap(address(pool.xToken()), lastAmountIn, getAmountSubFee(expected), msg.sender, getValidExpiration());
        }
        uint yBalance = IERC20(pool.yToken()).balanceOf(address(pool));
        console2.log("yBalance", yBalance);
        _checkRevenueState();
    }

    function testLiquidity_Pool_backAndForthSwaps() public startAsAdmin endWithStopPrank {
        for (uint i = 0; i < 100; i++) {
            // 10 swaps in each direction back and forth
            for (uint j = 0; j < 10; j++) {
                uint256 previous = 0;

                (uint expected, uint expectedFeeAmount, ) = pool.simSwap(address(_yToken), (1 * fullToken));
                (uint actual, uint actualFeeAmount, ) = pool.swap(
                    address(_yToken),
                    (1 * fullToken),
                    expected,
                    msg.sender,
                    getValidExpiration()
                );
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
                (uint actual, uint actualFeeAmount, ) = pool.swap(
                    address(pool.xToken()),
                    amountIn,
                    getAmountSubFee(expected),
                    msg.sender,
                    getValidExpiration()
                );
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
        _checkRevenueState();
    }

    function testLiquidity_Pool_buyCollateralToken_Positive() public endWithStopPrank {
        _approvePool(pool, false);
        vm.startPrank(admin);
        // Set initial X value to something above 0 before starting to swap for X
        (uint expected, uint feeAmount, ) = pool.simSwap(address(_yToken), 1_000 * fullToken);

        // we test that no disguised negative amount in can be traded.
        _yToken.approve(address(pool), type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSignature(
                "ERC20InsufficientBalance(address,uint256,uint256)",
                admin,
                1e12 * fullToken,
                address(_yToken) == address(stableCoin)
                    ? 115792089237316195423570985008687907853269984665640564039457584007912129639936
                    : 115792089237316195423570985008687907853269984665640564038457584007913129639936
            )
        );
        pool.swap(address(_yToken), uint(-int(1_000 * fullToken)), expected, address(0), getValidExpiration());

        // now we carry out the valid swap
        pool.swap(address(_yToken), 1_000 * fullToken, expected, msg.sender, getValidExpiration());
        uint256 previous = 0;

        for (uint i = 0; i < 100; i++) {
            uint amountIn = (1 * ERC20_DECIMALS) / 10;
            (expected, feeAmount, ) = pool.simSwap(address(pool.xToken()), amountIn);
            if (transferFee > 0) {
                amountIn = getAmountPlusFee(amountIn);
            }
            (uint actual, uint actualFeeAmount, ) = pool.swap(
                address(pool.xToken()),
                amountIn,
                getAmountSubFee(expected),
                msg.sender,
                getValidExpiration()
            );
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
            (uint256 actual, , ) = pool.swap(address(_yToken), needed, getAmountSubFee(expected), msg.sender, getValidExpiration());
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
        pool.swap(address(_yToken), initialAmount, expected, msg.sender, getValidExpiration());
        for (uint i = 0; i < 100; i++) {
            uint amountOut = (1 * fullToken);
            (uint expectedIn, , ) = pool.simSwapReversed(address(_yToken), amountOut);
            if (transferFee > 0) {
                expectedIn = getAmountPlusFee(expectedIn);
            }
            (uint256 actual, , ) = pool.swap(address(pool.xToken()), expectedIn, amountOut - 300, msg.sender, getValidExpiration());
            uint256 difference = amountOut > actual ? amountOut - actual : actual - amountOut;
            assertLe(difference, 1);
        }
    }

    function testLiquidity_Pool_buyGameToken_Paused() public endWithStopPrank {
        (uint expected, , ) = pool.simSwap(address(_yToken), 1 * fullToken);
        _deenableSwaps();
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        pool.swap(address(_yToken), 1 * fullToken, expected, msg.sender, getValidExpiration());
    }

    function testLiquidity_recordCurveStateForSmallYTokenSales() public {
        uint256 amount = address(_yToken) == address(stableCoin) ? amountMinBound : 10;
        vm.startPrank(admin);
        uint initial_x = ((1 * fullToken));
        _yToken.approve(address(pool), initial_x);
        (uint256 toutOp, , ) = pool.simSwap(address(_yToken), initial_x);
        pool.swap(address(_yToken), initial_x, toutOp, msg.sender, getValidExpiration());

        uint256 priceBefore = pool.spotPrice();
        for (uint i; i < 1000; i++) {
            _yToken.approve(address(pool), amount);
            (toutOp, , ) = pool.simSwap(address(_yToken), amount);
            pool.swap(address(_yToken), amount, toutOp, msg.sender, getValidExpiration());
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
        pool.withdrawRevenue(2, 1, address(alice));
    }

    function testLiquidity_Pool_WithdrawRevenueAccrued_NegativeAmount() public startAsAdmin endWithStopPrank {
        _pool_BackAndForthSwaps();
        vm.expectRevert(
            abi.encodeWithSignature(
                "SafeCastOverflowedUintToInt(uint256)",
                115792089237316195423570985008687907853269984665640564039457584007913129539936
            )
        );
        pool.withdrawRevenue(2, uint(int(-100000)), address(0));
    }

    function testLiquidity_Pool_NotEnoughCollateral() public {
        vm.startPrank(admin);
        vm.expectRevert(abi.encodeWithSignature("NotEnoughCollateral()"));
        pool.simSwapReversed(address(_yToken), X_TOKEN_MAX_SUPPLY);
    }

    function _pool_BackAndForthSwaps() internal {
        vm.stopPrank();
        uint amountIn = 1_000_000 * fullToken;
        for (uint i = 0; i < 100; i++) {
            // 10 swaps in each direction back and forth
            _approvePool(pool, false);
            vm.startPrank(admin);

            (uint expected, uint expectedFeeAmount, ) = pool.simSwap(address(_yToken), amountIn);
            (uint actual, uint actualFeeAmount, ) = pool.swap(
                address(_yToken),
                amountIn,
                getAmountSubFee(expected),
                msg.sender,
                getValidExpiration()
            );
            (uint256 expectedBack, uint256 expectedFeeAmountBack, ) = pool.simSwap(address(pool.xToken()), actual);
            (uint actualBack, uint actualFeeAmountBack, ) = pool.swap(
                address(pool.xToken()),
                actual,
                getAmountSubFee(expectedBack),
                msg.sender,
                getValidExpiration()
            );
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
