/// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/Pausable.sol";
import "forge-std/console2.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";
import "src/common/IEvents.sol";
import {GenericERC20FixedSupply} from "src/example/ERC20/GenericERC20FixedSupply.sol";
import {PoolBase} from "src/amm/base/PoolBase.sol";
import {TestCommonSetup} from "test/util/TestCommonSetup.sol";

/**
 * @title Test Pool functionality
 * @dev unit test
 * @author @oscarsernarosero @mpetersoCode55 @cirsteve
 */
abstract contract PoolFeeComparisonTest is TestCommonSetup {
    PoolBase poolWFee;
    PoolBase poolWOutFee;
    GenericERC20FixedSupply xTokenWithFee;
    GenericERC20FixedSupply xTokenWoutFee;

    function _setUp() internal {
        (xTokenWithFee, xTokenWoutFee, poolWFee, poolWOutFee) = _setupParallelTokensAndPoolsForFees();
    }

    function testLiquidity_Pool_Fees_SellingTokenY() public endWithStopPrank {
        vm.startPrank(admin);
        for (uint j = 0; j < 100; j++) {
            (uint expected, uint expectedFeeAmount, ) = poolWFee.simSwap(address(_yToken), (1 * fullToken) / 1_000);
            vm.expectEmit(true, false, false, false, address(poolWFee));
            emit IPoolEvents.LPFeeGenerated(expectedFeeAmount);
            vm.expectEmit(true, false, false, false, address(poolWFee));
            emit IPoolEvents.ProtocolFeeGenerated(0);
            (uint actual, uint actualFeeAmount, ) = poolWFee.swap(address(_yToken), (1 * fullToken) / 1_000, expected);
            assertEq(actual, expected);
            assertEq(expectedFeeAmount, actualFeeAmount);

            (uint expectedNoFee, uint expectedFeeAmountNoFee, ) = poolWOutFee.simSwap(address(_yToken), (1 * fullToken) / 1_000);
            (uint actualNoFee, uint actualFeeAmountNoFee, ) = poolWOutFee.swap(address(_yToken), (1 * fullToken) / 1_000, expected);
            assertEq(actualNoFee, expectedNoFee);
            assertEq(expectedFeeAmountNoFee, 0);
            assertEq(actualFeeAmountNoFee, 0);
            assertLt(actual, actualNoFee);
        }
    }

    function testLiquidity_Pool_ProtocolFees_SellingTokenY() public endWithStopPrank {
        _activateProtocolFeesInPool(poolWFee);
        vm.startPrank(admin);
        for (uint j = 0; j < 100; j++) {
            (uint expected, uint expectedFeeAmount, uint expectedProtocolFee) = poolWFee.simSwap(address(_yToken), (1 * fullToken) / 1_000);
            vm.expectEmit(true, false, false, false, address(poolWFee));
            emit IPoolEvents.LPFeeGenerated(expectedFeeAmount);
            vm.expectEmit(true, false, false, false, address(poolWFee));
            emit IPoolEvents.ProtocolFeeGenerated(expectedProtocolFee);
            (uint actual, uint actualFeeAmount, uint actualProtocolFee) = poolWFee.swap(
                address(_yToken),
                (1 * fullToken) / 1_000,
                expected
            );
            assertEq(actual, expected);
            assertEq(expectedFeeAmount, actualFeeAmount);
            assertEq(expectedProtocolFee, actualProtocolFee);

            (uint expectedNoFee, uint expectedFeeAmountNoFee, uint expectedProtocolNoFee) = poolWOutFee.simSwap(
                address(_yToken),
                (1 * fullToken) / 1_000
            );
            (uint actualNoFee, uint actualFeeAmountNoFee, uint actualProtocolNoFee) = poolWOutFee.swap(
                address(_yToken),
                (1 * fullToken) / 1_000,
                expected
            );
            assertEq(actualNoFee, expectedNoFee);
            assertEq(expectedFeeAmountNoFee, 0);
            assertEq(actualFeeAmountNoFee, 0);
            assertEq(expectedProtocolNoFee, 0);
            assertEq(actualProtocolNoFee, 0);
            assertLt(actual, actualNoFee);
        }
        vm.startPrank(bob);
        uint yBalanceBefore = _yToken.balanceOf(bob);
        uint protocolFeesCollected = poolWFee.collectedProtocolFees();
        console2.log("protocolFeesCollected", protocolFeesCollected);
        poolWFee.collectProtocolFees();
        assertEq(protocolFeesCollected, (_yToken.balanceOf(bob) - yBalanceBefore));
    }

    function testLiquidity_Pool_ProtocolFeesAccuracyInSimSwapReversed_BuyX(uint256 amount) public endWithStopPrank {
        _activateProtocolFeesInPool(pool);
        vm.startPrank(admin);
        amount = bound(amount, 1 * ERC20_DECIMALS, 10_000 * ERC20_DECIMALS);
        (uint expectedIn, uint lpFees, uint protocolFees) = pool.simSwapReversed(address(pool.xToken()), amount);
        _yToken.approve(address(pool), expectedIn);
        (uint256 expectedAmount, uint256 lpFeeAmount, uint256 protocolFeeAmount) = pool.simSwap(address(_yToken), expectedIn);
        vm.expectEmit(false, false, false, false, address(pool)); // Fees generated might be off by 1 unit
        emit IPoolEvents.LPFeeGenerated(lpFeeAmount);
        vm.expectEmit(false, false, false, false, address(pool)); // Fees generated might be off by 1 unit
        emit IPoolEvents.ProtocolFeeGenerated(protocolFeeAmount);
        (, uint realLPFees, uint realProtocolFees) = pool.swap(address(_yToken), expectedIn, expectedAmount);
        assertLe(realLPFees, lpFees + 1); // we add 1 to account for rounding issues
        assertGe(realLPFees, lpFees - 1); // we add 1 to account for rounding issues
        assertLe(realProtocolFees, protocolFees + 1); // we add 1 to account for rounding issues
        assertGe(realProtocolFees, protocolFees - 1); // we add 1 to account for rounding issues
        vm.startPrank(bob);
        uint yBalanceBefore = _yToken.balanceOf(bob);
        uint protocolFeesCollected = pool.collectedProtocolFees();
        console2.log("protocolFeesCollected", protocolFeesCollected);
        vm.expectEmit(true, true, false, false, address(pool)); // Fees generated might be off by 1 unit
        emit IPoolEvents.ProtocolFeesCollected(bob, protocolFeesCollected);
        pool.collectProtocolFees();
        assertEq(protocolFeesCollected, (_yToken.balanceOf(bob) - yBalanceBefore));
    }

    function testLiquidity_Pool_Fees_SellingTokenX() public endWithStopPrank {
        vm.startPrank(admin);
        // Set initial X value to something above 0 before starting to swap for X
        (uint _expected, , ) = poolWFee.simSwap(address(_yToken), 1 * fullToken);
        poolWFee.swap(address(_yToken), 1 * fullToken, _expected);

        (uint _expectedNoFee, , ) = poolWOutFee.simSwap(address(_yToken), 1 * fullToken);
        poolWOutFee.swap(address(_yToken), 1 * fullToken, _expectedNoFee);

        for (uint j = 0; j < 100; j++) {
            _approvePool(poolWFee, false);
            _approvePool(poolWOutFee, false);
            vm.startPrank(admin);

            (uint expected, uint expectedFeeAmount, ) = poolWFee.simSwap(address(xTokenWithFee), 1_000_000_000_000_000);
            (uint actual, uint actualFeeAmount, ) = poolWFee.swap(address(xTokenWithFee), 1_000_000_000_000_000, expected);

            assertEq(actual, expected);
            assertEq(expectedFeeAmount, actualFeeAmount);

            (uint expectedNoFee, uint expectedFeeAmountNoFee, ) = poolWOutFee.simSwap(address(xTokenWoutFee), 1_000_000_000_000_000);
            (uint actualNoFee, uint actualFeeAmountNoFee, ) = poolWOutFee.swap(address(xTokenWoutFee), 1_000_000_000_000_000, expected);

            assertEq(actualNoFee, expectedNoFee);
            assertEq(expectedFeeAmountNoFee, 0);
            assertEq(actualFeeAmountNoFee, 0);

            uint256 feeAmount = (actualNoFee * 30) / 10_000 + 1;
            assertLt(feeAmount - actualFeeAmount, 1e6);
        }
    }
}
