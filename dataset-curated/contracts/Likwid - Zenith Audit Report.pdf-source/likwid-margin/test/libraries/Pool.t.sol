// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Pool} from "../../src/libraries/Pool.sol";
import {BalanceDelta, toBalanceDelta} from "../../src/types/BalanceDelta.sol";
import {toReserves} from "../../src/types/Reserves.sol";
import {PairPosition} from "../../src/libraries/PairPosition.sol";
import {Math} from "../../src/libraries/Math.sol";

contract PoolTest is Test {
    using Pool for Pool.State;
    using PairPosition for mapping(bytes32 => PairPosition.State);

    Pool.State private pool;

    function setUp() public {
        pool.initialize(200); // 0.02% lpFee
    }

    function testModifyLiquidityAddInitialLiquidity() public {
        uint256 amount0 = 1e18;
        uint256 amount1 = 4e18;
        bytes32 salt = keccak256("salt");
        address owner = address(this);

        Pool.ModifyLiquidityParams memory params = Pool.ModifyLiquidityParams({
            owner: owner,
            amount0: amount0,
            amount1: amount1,
            liquidityDelta: 0, // Should be calculated from amounts
            salt: salt
        });

        // --- Action ---
        (BalanceDelta delta,) = pool.modifyLiquidity(params);

        // --- Assertions ---

        // 1. Check returned delta (ISSUE: This will fail, current implementation returns 0)
        int128 expectedAmount0 = -int128(int256(amount0));
        int128 expectedAmount1 = -int128(int256(amount1));
        assertEq(int256(delta.amount0()), int256(expectedAmount0), "Delta amount0 should be negative amount added");
        assertEq(int256(delta.amount1()), int256(expectedAmount1), "Delta amount1 should be negative amount added");

        // 2. Check pool state
        uint128 expectedLiquidity = uint128(Math.sqrt(amount0 * amount1));
        assertEq(
            uint256(pool.slot0.totalSupply()),
            uint256(expectedLiquidity),
            "Total supply should be sqrt(amount0 * amount1)"
        );

        // 3. Check position state
        PairPosition.State storage position = pool.positions.get(owner, salt);
        assertEq(uint256(position.liquidity), uint256(expectedLiquidity), "Position liquidity should be updated");
    }

    function testModifyLiquidityRemoveLiquidity() public {
        // --- Setup: Add initial liquidity first ---
        uint256 amount0Add = 1e18;
        uint256 amount1Add = 4e18;
        uint128 initialLiquidity = uint128(Math.sqrt(amount0Add * amount1Add));

        pool.slot0 = pool.slot0.setTotalSupply(initialLiquidity);
        pool.pairReserves = toReserves(uint128(amount0Add), uint128(amount1Add));
        pool.realReserves = toReserves(uint128(amount0Add), uint128(amount1Add));

        bytes32 salt = keccak256("salt");
        address owner = address(this);
        PairPosition.update(
            pool.positions.get(owner, salt),
            int128(initialLiquidity),
            toBalanceDelta(-int128(int256(amount0Add)), -int128(int256(amount1Add)))
        );

        // --- Action: Remove half of the liquidity ---
        int128 liquidityToRemove = -int128(initialLiquidity / 2);
        Pool.ModifyLiquidityParams memory params = Pool.ModifyLiquidityParams({
            owner: owner,
            amount0: 0, // Not used for removal
            amount1: 0, // Not used for removal
            liquidityDelta: liquidityToRemove,
            salt: salt
        });

        (BalanceDelta delta,) = pool.modifyLiquidity(params);

        // --- Assertions ---

        // 1. Check returned delta
        uint256 expectedAmount0Out = (amount0Add / 2);
        uint256 expectedAmount1Out = (amount1Add / 2);
        assertEq(uint256(int256(delta.amount0())), expectedAmount0Out, "Delta amount0 should be amount removed");
        assertEq(uint256(int256(delta.amount1())), expectedAmount1Out, "Delta amount1 should be amount removed");

        // 2. Check pool state
        uint128 expectedFinalSupply = initialLiquidity / 2;
        assertEq(uint256(pool.slot0.totalSupply()), uint256(expectedFinalSupply), "Total supply should be reduced");

        // 3. Check position state
        PairPosition.State storage position = pool.positions.get(owner, salt);
        uint128 expectedFinalLiquidity = initialLiquidity - (initialLiquidity / 2);
        assertEq(uint256(position.liquidity), uint256(expectedFinalLiquidity), "Position liquidity should be reduced");
    }
}
