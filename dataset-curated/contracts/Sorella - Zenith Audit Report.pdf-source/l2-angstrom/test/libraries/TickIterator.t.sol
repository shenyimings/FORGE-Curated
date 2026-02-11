// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {
    TickIteratorLib, TickIteratorUp, TickIteratorDown
} from "../../src/libraries/TickIterator.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {IUniV4} from "../../src/interfaces/IUniV4.sol";
import {BaseTest} from "../_helpers/BaseTest.sol";
import {RouterActor} from "../_mocks/RouterActor.sol";
import {UniV4Inspector} from "../_mocks/UniV4Inspector.sol";
import {MockERC20} from "super-sol/mocks/MockERC20.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {DynamicArrayLib, DynamicArray} from "solady/src/utils/g/DynamicArrayLib.sol";
import {TickLib} from "src/libraries/TickLib.sol";
import {LibSort} from "solady/src/utils/LibSort.sol";
import {console} from "forge-std/console.sol";
import {FormatLib} from "super-sol/libraries/FormatLib.sol";

contract TickIteratorTest is BaseTest {
    using PoolIdLibrary for PoolKey;
    using TickLib for int24;
    using IUniV4 for IPoolManager;
    using DynamicArrayLib for *;
    using FormatLib for *;

    UniV4Inspector manager;
    RouterActor router;
    PoolId pid;
    PoolKey key;

    MockERC20 token0;
    MockERC20 token1;

    int24 constant TICK_SPACING = 10;
    uint160 constant INIT_SQRT_PRICE = 79228162514264337593543950336; // 1:1 price

    function setUp() public {
        // Deploy UniV4Inspector (which is a PoolManager with view functions)
        manager = new UniV4Inspector();
        router = new RouterActor(manager);

        // Deploy and sort tokens
        token0 = new MockERC20();
        token1 = new MockERC20();

        if (address(token1) < address(token0)) {
            (token0, token1) = (token1, token0);
        }

        // Set up pool key
        key = PoolKey({
            currency0: Currency.wrap(address(token0)),
            currency1: Currency.wrap(address(token1)),
            fee: 3000,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(address(0))
        });

        pid = key.toId();

        // Initialize pool
        manager.initialize(key, INIT_SQRT_PRICE);

        // Fund the router with tokens for liquidity operations
        token0.mint(address(router), 1e30);
        token1.mint(address(router), 1e30);
    }

    // Helper to add liquidity at specific tick range
    function addLiquidityAtTicks(int24 tickLower, int24 tickUpper) internal {
        require(tickLower % TICK_SPACING == 0, "Lower tick not aligned");
        require(tickUpper % TICK_SPACING == 0, "Upper tick not aligned");
        require(tickLower < tickUpper, "Invalid range");

        // Calculate liquidity amount (simplified - just use a fixed amount)
        uint128 liquidity = 1e18;

        // Use RouterActor to add liquidity
        router.modifyLiquidity(key, tickLower, tickUpper, int256(uint256(liquidity)), bytes32(0));
    }

    // ============ Upward Iteration Tests ============

    function test_iterateUp_simple() public {
        // Add liquidity at specific ticks: -100, -50, 0, 50, 100
        addLiquidityAtTicks(-100, -50);
        addLiquidityAtTicks(-50, 0);
        addLiquidityAtTicks(0, 50);
        addLiquidityAtTicks(50, 100);
        addLiquidityAtTicks(100, 150);

        // Start is exclusive (-100 not included), end is inclusive (100 included)
        // Should get: -50, 0, 50, 100
        TickIteratorUp memory iter = TickIteratorLib.initUp(manager, pid, TICK_SPACING, -100, 100);

        // Should iterate through initialized ticks
        assertTrue(iter.hasNext(), "Should have first tick");
        assertEq(iter.getNext(), -50, "First tick should be -50");

        assertTrue(iter.hasNext(), "Should have second tick");
        assertEq(iter.getNext(), 0, "Second tick should be 0");

        assertTrue(iter.hasNext(), "Should have third tick");
        assertEq(iter.getNext(), 50, "Third tick should be 50");

        assertTrue(iter.hasNext(), "Should have fourth tick");
        assertEq(iter.getNext(), 100, "Fourth tick should be 100");

        assertFalse(iter.hasNext(), "Should have no more ticks");
    }

    function test_iterateUp_exclusiveBoundaries() public {
        // Test that boundaries are exclusive
        addLiquidityAtTicks(-200, -100);
        addLiquidityAtTicks(-100, 0);
        addLiquidityAtTicks(0, 100);
        addLiquidityAtTicks(100, 200);

        // Start is exclusive (-100 not included), end is inclusive (100 included)
        TickIteratorUp memory iter = TickIteratorLib.initUp(manager, pid, TICK_SPACING, -100, 100);

        assertTrue(iter.hasNext());
        assertEq(iter.getNext(), 0, "Should exclude start boundary -100");

        assertTrue(iter.hasNext());
        assertEq(iter.getNext(), 100, "Should include end boundary 100");

        assertFalse(iter.hasNext());
    }

    function test_fuzzing_iterateUp(bytes32 seed) public {
        Random memory r = Random(seed);
        int256[] memory ticks = new int256[](10);
        uint256 length = 0;
        while (length < 10) {
            int24 tick = randomTick(r);
            uint256 j = 0;
            for (; j < length; j++) {
                if (ticks[j] == tick) break;
            }
            if (j == length) ticks[length++] = tick;
        }
        for (uint256 i = 0; i < length / 2; i++) {
            (int24 tickLower, int24 tickUpper) =
                sortTicks(int24(ticks[i * 2]), int24(ticks[i * 2 + 1]));
            addLiquidityAtTicks(tickLower, tickUpper);
        }
        LibSort.insertionSort(ticks);
        (int24 start, int24 end) = sortTicks(randomTick(r), randomTick(r));
        TickIteratorUp memory iter = TickIteratorLib.initUp(manager, pid, TICK_SPACING, start, end);
        for (uint256 i = 0; i < length; i++) {
            int24 tick = int24(ticks[i]);
            if (end < tick) break;
            if (tick <= start) continue;

            assertTrue(
                iter.hasNext(),
                iter.hasNext() ? "" : logTicks("iterator ended early", start, end, ticks, i)
            );
            int24 nextTick = iter.peekNext();
            assertEq(
                nextTick,
                tick,
                nextTick != tick ? logTicks("tick mismatch", start, end, ticks, i) : ""
            );
            iter.getNext();
        }

        assertFalse(
            iter.hasNext(),
            iter.hasNext()
                ? logTicks(
                    string.concat("iterator not depleted (next: ", iter.peekNext().toStr(), ")"),
                    start,
                    end,
                    ticks,
                    999
                )
                : ""
        );
    }

    function test_iterateUp_acrossWords() public {
        // Test iteration across word boundaries (256 ticks per word when compressed)
        // Word boundary is at compressed tick 256, which is tick 2560 with spacing 10
        addLiquidityAtTicks(-2570, -2560);
        addLiquidityAtTicks(-2560, -2550);
        addLiquidityAtTicks(-10, 0);
        addLiquidityAtTicks(0, 10);
        addLiquidityAtTicks(2550, 2560);
        addLiquidityAtTicks(2560, 2570);
        addLiquidityAtTicks(2570, 2580);

        // Exclusive bounds: (-3000, 3000)
        TickIteratorUp memory iter = TickIteratorLib.initUp(manager, pid, TICK_SPACING, -3000, 3000);

        assertTrue(iter.hasNext());
        assertEq(iter.getNext(), -2570);

        assertTrue(iter.hasNext());
        assertEq(iter.getNext(), -2560);

        assertTrue(iter.hasNext());
        assertEq(iter.getNext(), -2550);

        assertTrue(iter.hasNext());
        assertEq(iter.getNext(), -10);

        assertTrue(iter.hasNext());
        assertEq(iter.getNext(), 0);

        assertTrue(iter.hasNext());
        assertEq(iter.getNext(), 10);

        assertTrue(iter.hasNext());
        assertEq(iter.getNext(), 2550);

        assertTrue(iter.hasNext());
        assertEq(iter.getNext(), 2560);

        assertTrue(iter.hasNext());
        assertEq(iter.getNext(), 2570);

        assertTrue(iter.hasNext());
        assertEq(iter.getNext(), 2580);

        assertFalse(iter.hasNext());
    }

    function test_iterateUp_noInitializedTicks() public view {
        // No liquidity added, so no initialized ticks
        TickIteratorUp memory iter = TickIteratorLib.initUp(manager, pid, TICK_SPACING, -100, 100);

        assertFalse(iter.hasNext(), "Should have no ticks in empty range");
    }

    function test_iterateUp_singleTick() public {
        addLiquidityAtTicks(40, 60);

        // Test iteration over position boundaries with exclusive bounds
        // When adding liquidity from 40 to 60, ticks 40 and 60 are initialized
        // Start is exclusive (40 not included), end is inclusive (60 included)
        TickIteratorUp memory iter = TickIteratorLib.initUp(manager, pid, TICK_SPACING, 40, 60);

        // Should have tick 60 (end boundary is included)
        assertTrue(iter.hasNext());
        assertEq(iter.getNext(), 60, "Should include end boundary 60");

        assertFalse(iter.hasNext());

        // To get the boundary ticks, need to expand range
        TickIteratorUp memory iter2 = TickIteratorLib.initUp(manager, pid, TICK_SPACING, 30, 70);

        assertTrue(iter2.hasNext());
        assertEq(iter2.getNext(), 40, "First tick should be 40");

        assertTrue(iter2.hasNext());
        assertEq(iter2.getNext(), 60, "Second tick should be 60");

        assertFalse(iter2.hasNext());
    }

    function test_iterateUp_maxTick() public view {
        // Test near maximum tick (must be aligned to tick spacing)
        /// forge-lint: disable-next-line(divide-before-multiply)
        int24 maxAlignedTick = (TickMath.MAX_TICK / TICK_SPACING) * TICK_SPACING;
        int24 nearMaxTick = maxAlignedTick - TICK_SPACING;

        // Can't actually add liquidity at MAX_TICK, so test iteration behavior
        TickIteratorUp memory iter =
            TickIteratorLib.initUp(manager, pid, TICK_SPACING, nearMaxTick, maxAlignedTick);

        // No liquidity there, so should have no ticks
        assertFalse(iter.hasNext());
    }

    // ============ Downward Iteration Tests ============

    function test_iterateDown_simple() public {
        // Add liquidity at specific ticks
        addLiquidityAtTicks(-100, -50);
        addLiquidityAtTicks(-50, 0);
        addLiquidityAtTicks(0, 50);
        addLiquidityAtTicks(50, 100);
        addLiquidityAtTicks(100, 150);

        // With exclusive bounds (100, -100) means we exclude both 100 and -100
        TickIteratorDown memory iter =
            TickIteratorLib.initDown(manager, pid, TICK_SPACING, 100, -100);

        // Should iterate through ticks in reverse (excluding boundaries)
        assertTrue(iter.hasNext(), "Should have first tick");
        assertEq(iter.getNext(), 50, "First tick should be 50");

        assertTrue(iter.hasNext(), "Should have second tick");
        assertEq(iter.getNext(), 0, "Second tick should be 0");

        assertTrue(iter.hasNext(), "Should have third tick");
        assertEq(iter.getNext(), -50, "Third tick should be -50");

        assertFalse(iter.hasNext(), "Should have no more ticks");
    }

    function test_iterateDown_exclusiveBoundaries() public {
        // Test that boundaries are exclusive
        addLiquidityAtTicks(-200, -100);
        addLiquidityAtTicks(-100, 0);
        addLiquidityAtTicks(0, 100);
        addLiquidityAtTicks(100, 200);

        // With exclusive bounds (100, -100)
        TickIteratorDown memory iter =
            TickIteratorLib.initDown(manager, pid, TICK_SPACING, 100, -100);

        assertTrue(iter.hasNext());
        assertEq(iter.getNext(), 0, "Should exclude start boundary 100");

        assertFalse(iter.hasNext(), "Should exclude end boundary -100");
    }

    function test_iterateDown_acrossWords() public {
        // Test iteration across word boundaries
        addLiquidityAtTicks(-2570, -2560);
        addLiquidityAtTicks(-2560, -2550);
        addLiquidityAtTicks(-10, 0);
        addLiquidityAtTicks(0, 10);
        addLiquidityAtTicks(2550, 2560);
        addLiquidityAtTicks(2560, 2570);
        addLiquidityAtTicks(2570, 2580);

        // Exclusive bounds (3000, -3000)
        TickIteratorDown memory iter =
            TickIteratorLib.initDown(manager, pid, TICK_SPACING, 3000, -3000);

        assertTrue(iter.hasNext());
        assertEq(iter.getNext(), 2580);

        assertTrue(iter.hasNext());
        assertEq(iter.getNext(), 2570);

        assertTrue(iter.hasNext());
        assertEq(iter.getNext(), 2560);

        assertTrue(iter.hasNext());
        assertEq(iter.getNext(), 2550);

        assertTrue(iter.hasNext());
        assertEq(iter.getNext(), 10);

        assertTrue(iter.hasNext());
        assertEq(iter.getNext(), 0);

        assertTrue(iter.hasNext());
        assertEq(iter.getNext(), -10);

        assertTrue(iter.hasNext());
        assertEq(iter.getNext(), -2550);

        assertTrue(iter.hasNext());
        assertEq(iter.getNext(), -2560);

        assertTrue(iter.hasNext());
        assertEq(iter.getNext(), -2570);

        assertFalse(iter.hasNext());
    }

    function test_iterateDown_noInitializedTicks() public view {
        // No liquidity added
        TickIteratorDown memory iter =
            TickIteratorLib.initDown(manager, pid, TICK_SPACING, 100, -100);

        assertFalse(iter.hasNext(), "Should have no ticks in empty range");
    }

    function test_iterateDown_singleTick() public {
        addLiquidityAtTicks(40, 60);

        // With exclusive bounds (60, 40), both boundaries are excluded
        TickIteratorDown memory iter = TickIteratorLib.initDown(manager, pid, TICK_SPACING, 60, 40);

        assertFalse(iter.hasNext(), "Should have no ticks with exclusive boundaries");

        // To get the boundary ticks, need to expand range
        TickIteratorDown memory iter2 = TickIteratorLib.initDown(manager, pid, TICK_SPACING, 70, 30);

        assertTrue(iter2.hasNext());
        assertEq(iter2.getNext(), 60, "First tick should be 60");

        assertTrue(iter2.hasNext());
        assertEq(iter2.getNext(), 40, "Second tick should be 40");

        assertFalse(iter2.hasNext());
    }

    function test_iterateDown_minTick() public view {
        // Test near minimum tick (must be aligned to tick spacing)
        /// forge-lint: disable-next-line(divide-before-multiply)
        int24 minAlignedTick = (TickMath.MIN_TICK / TICK_SPACING) * TICK_SPACING;
        int24 nearMinTick = minAlignedTick + TICK_SPACING;

        TickIteratorDown memory iter =
            TickIteratorLib.initDown(manager, pid, TICK_SPACING, nearMinTick, minAlignedTick);

        // No liquidity there, so should have no ticks
        assertFalse(iter.hasNext());
    }

    // ============ Edge Cases ============

    function test_iterateUp_emptyRange() public view {
        // When start == end, the range includes just that point
        // Since no liquidity at tick 100, should have no ticks
        TickIteratorUp memory iter = TickIteratorLib.initUp(manager, pid, TICK_SPACING, 100, 100);
        assertFalse(iter.hasNext(), "No initialized tick at position 100");
    }

    function test_iterateDown_emptyRange() public view {
        // Empty range: start == end should have no ticks
        TickIteratorDown memory iter =
            TickIteratorLib.initDown(manager, pid, TICK_SPACING, 100, 100);
        assertFalse(iter.hasNext(), "Empty range should have no ticks");
    }

    function test_iterateUp_partialRange() public {
        addLiquidityAtTicks(-200, -100);
        addLiquidityAtTicks(-100, 0);
        addLiquidityAtTicks(0, 100);
        addLiquidityAtTicks(100, 200);

        // Only iterate middle portion with exclusive bounds (-50, 50)
        TickIteratorUp memory iter = TickIteratorLib.initUp(manager, pid, TICK_SPACING, -50, 50);

        assertTrue(iter.hasNext());
        assertEq(iter.getNext(), 0, "Should only get tick within range");

        assertFalse(iter.hasNext());
    }

    function test_iterateUp_unalignedBounds() public {
        // Test with unaligned start/end ticks
        addLiquidityAtTicks(-100, 0);
        addLiquidityAtTicks(0, 100);
        addLiquidityAtTicks(100, 200);

        // Start at -99 (unaligned), end at 101 (unaligned)
        // Exclusive bounds mean we get ticks in range (-99, 101)
        TickIteratorUp memory iter = TickIteratorLib.initUp(manager, pid, TICK_SPACING, -99, 101);

        assertTrue(iter.hasNext());
        assertEq(iter.getNext(), 0, "Should get tick 0");

        assertTrue(iter.hasNext());
        assertEq(iter.getNext(), 100, "Should get tick 100");

        assertFalse(iter.hasNext());
    }

    function test_iterateUp_unalignedTickSpacing60() public {
        // Change to tick spacing 60 for this test
        key = PoolKey({
            currency0: Currency.wrap(address(token0)),
            currency1: Currency.wrap(address(token1)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });
        pid = key.toId();
        manager.initialize(key, INIT_SQRT_PRICE);

        // Add liquidity at aligned ticks for spacing 60
        router.modifyLiquidity(key, -120, 0, int256(1e18), bytes32(0));
        router.modifyLiquidity(key, 0, 120, int256(1e18), bytes32(0));
        router.modifyLiquidity(key, 120, 240, int256(1e18), bytes32(0));

        // Test with unaligned start tick 39 (not divisible by 60)
        // With exclusive bounds (39, 180):
        // - Start is 39, so we begin searching from tick 60 (next aligned tick after 39)
        // - End is 180, so we stop before 180
        // - Initialized ticks in range: 120 (tick 60 is not initialized, only 0 and 120 are)
        TickIteratorUp memory iter = TickIteratorLib.initUp(manager, pid, 60, 39, 180);

        assertTrue(iter.hasNext());
        assertEq(iter.getNext(), 120, "Should get tick 120");

        assertFalse(iter.hasNext(), "Should not have more ticks");
    }

    function test_iterateDown_partialRange() public {
        addLiquidityAtTicks(-200, -100);
        addLiquidityAtTicks(-100, 0);
        addLiquidityAtTicks(0, 100);
        addLiquidityAtTicks(100, 200);

        // Only iterate middle portion with exclusive bounds (50, -50)
        TickIteratorDown memory iter = TickIteratorLib.initDown(manager, pid, TICK_SPACING, 50, -50);

        assertTrue(iter.hasNext());
        assertEq(iter.getNext(), 0, "Should only get tick within range");

        assertFalse(iter.hasNext());
    }

    function test_iterateDown_unalignedBounds() public {
        // Test with unaligned start/end ticks
        addLiquidityAtTicks(-200, -100);
        addLiquidityAtTicks(-100, 0);
        addLiquidityAtTicks(0, 100);

        // Start at 101 (unaligned), end at -99 (unaligned)
        // Exclusive bounds mean we get ticks in range (101, -99) which excludes both boundaries
        // So we should get ticks 100, 0, -100 but stop before -99, so only 100 and 0
        TickIteratorDown memory iter =
            TickIteratorLib.initDown(manager, pid, TICK_SPACING, 101, -99);

        assertTrue(iter.hasNext());
        assertEq(iter.getNext(), 100);
        assertTrue(iter.hasNext());
        assertEq(iter.getNext(), 0);

        assertFalse(iter.hasNext());
    }

    function test_iterateDown_unalignedTickSpacing60() public {
        // Change to tick spacing 60 for this test
        key = PoolKey({
            currency0: Currency.wrap(address(token0)),
            currency1: Currency.wrap(address(token1)),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(0))
        });
        pid = key.toId();
        manager.initialize(key, INIT_SQRT_PRICE);

        // Add liquidity at aligned ticks for spacing 60
        router.modifyLiquidity(key, -240, -120, int256(1e18), bytes32(0));
        router.modifyLiquidity(key, -120, 0, int256(1e18), bytes32(0));
        router.modifyLiquidity(key, 0, 120, int256(1e18), bytes32(0));

        // Test with unaligned start tick 39 (not divisible by 60)
        // With exclusive bounds (39, -180):
        // - Start is 39, so we begin searching from tick 0 (prev aligned tick before 39)
        // - End is -180, so we stop after -180
        // - Initialized ticks in range: 0, -120
        TickIteratorDown memory iter = TickIteratorLib.initDown(manager, pid, 60, 39, -180);

        assertTrue(iter.hasNext());
        assertEq(iter.getNext(), 0, "Should get tick 0 first");

        assertTrue(iter.hasNext());
        assertEq(iter.getNext(), -120, "Should get tick -120");

        assertFalse(iter.hasNext(), "Should not have more ticks");
    }

    function test_iterateUp_boundaryExclusion() public {
        // Test that exact boundary ticks are excluded
        addLiquidityAtTicks(-100, 0);
        addLiquidityAtTicks(0, 100);
        addLiquidityAtTicks(100, 200);

        // Start is exclusive (-100 not included), end is inclusive (100 included)
        TickIteratorUp memory iter = TickIteratorLib.initUp(manager, pid, TICK_SPACING, -100, 100);

        assertTrue(iter.hasNext());
        assertEq(iter.getNext(), 0, "First tick should be 0");

        assertTrue(iter.hasNext());
        assertEq(iter.getNext(), 100, "Should include end boundary 100");

        assertFalse(iter.hasNext());
    }

    function test_iterateDown_boundaryExclusion() public {
        // Test that exact boundary ticks are excluded
        addLiquidityAtTicks(-200, -100);
        addLiquidityAtTicks(-100, 0);
        addLiquidityAtTicks(0, 100);

        // With exclusive bounds (100, -100), should not include 100 or -100
        TickIteratorDown memory iter =
            TickIteratorLib.initDown(manager, pid, TICK_SPACING, 100, -100);

        assertTrue(iter.hasNext());
        assertEq(iter.getNext(), 0, "Should only get tick 0");

        assertFalse(iter.hasNext(), "Should not include boundary ticks");
    }

    function test_iterateUp_adjacentTicks() public {
        // Test iteration with adjacent initialized ticks
        addLiquidityAtTicks(0, 10);
        addLiquidityAtTicks(10, 20);
        addLiquidityAtTicks(20, 30);

        // Exclusive bounds (-5, 25) should give us 0, 10, 20
        TickIteratorUp memory iter = TickIteratorLib.initUp(manager, pid, TICK_SPACING, -5, 25);

        assertTrue(iter.hasNext());
        assertEq(iter.getNext(), 0);

        assertTrue(iter.hasNext());
        assertEq(iter.getNext(), 10);

        assertTrue(iter.hasNext());
        assertEq(iter.getNext(), 20);

        assertFalse(iter.hasNext());
    }

    function test_iterateDown_adjacentTicks() public {
        // Test iteration with adjacent initialized ticks
        addLiquidityAtTicks(0, 10);
        addLiquidityAtTicks(10, 20);
        addLiquidityAtTicks(20, 30);

        // When adding liquidity: tick 0, 10, 20, 30 are initialized
        // Exclusive bounds (25, -5) excludes both 25 and -5
        // Based on the iterator implementation, it should iterate from 20 down to 0
        TickIteratorDown memory iter = TickIteratorLib.initDown(manager, pid, TICK_SPACING, 25, -5);

        assertTrue(iter.hasNext());
        assertEq(iter.getNext(), 20, "first");
        assertTrue(iter.hasNext());
        assertEq(iter.getNext(), 10);
        assertTrue(iter.hasNext());
        assertEq(iter.getNext(), 0);

        assertFalse(iter.hasNext());

        // Use a wider range to get all ticks
        TickIteratorDown memory iter2 =
            TickIteratorLib.initDown(manager, pid, TICK_SPACING, 35, -10);

        assertTrue(iter2.hasNext());
        assertEq(iter2.getNext(), 30);
        assertTrue(iter2.hasNext());
        assertEq(iter2.getNext(), 20, "second");
        assertTrue(iter2.hasNext());
        assertEq(iter2.getNext(), 10);
        assertTrue(iter2.hasNext());
        assertEq(iter2.getNext(), 0);

        assertFalse(iter2.hasNext());
    }

    // ============ Additional Unaligned Tick Tests ============

    function test_iterateUp_variousUnalignedCases() public {
        // Test various unaligned tick scenarios with tick spacing 10
        addLiquidityAtTicks(-100, -50);
        addLiquidityAtTicks(-50, 0);
        addLiquidityAtTicks(0, 50);
        addLiquidityAtTicks(50, 100);

        // Case 1: Start at 3 (unaligned), end at 47 (unaligned)
        // Should iterate through ticks in range (3, 47): none in this case since next is 50
        TickIteratorUp memory iter1 = TickIteratorLib.initUp(manager, pid, TICK_SPACING, 3, 47);
        assertFalse(iter1.hasNext(), "No ticks between 3 and 47");

        // Case 2: Start at -53 (unaligned), end at 53 (unaligned)
        // Should iterate through ticks in range (-53, 53): -50, 0, 50
        TickIteratorUp memory iter2 = TickIteratorLib.initUp(manager, pid, TICK_SPACING, -53, 53);
        assertTrue(iter2.hasNext());
        assertEq(iter2.getNext(), -50);
        assertTrue(iter2.hasNext());
        assertEq(iter2.getNext(), 0);
        assertTrue(iter2.hasNext());
        assertEq(iter2.getNext(), 50);
        assertFalse(iter2.hasNext());

        // Case 3: Start at -51 (unaligned), end at 1 (unaligned)
        // Should iterate through ticks in range (-51, 1): -50, 0
        TickIteratorUp memory iter3 = TickIteratorLib.initUp(manager, pid, TICK_SPACING, -51, 1);
        assertTrue(iter3.hasNext());
        assertEq(iter3.getNext(), -50);
        assertTrue(iter3.hasNext());
        assertEq(iter3.getNext(), 0);
        assertFalse(iter3.hasNext());
    }

    function test_iterateDown_variousUnalignedCases() public {
        // Test various unaligned tick scenarios with tick spacing 10
        addLiquidityAtTicks(-100, -50);
        addLiquidityAtTicks(-50, 0);
        addLiquidityAtTicks(0, 50);
        addLiquidityAtTicks(50, 100);

        // Case 1: Start at 47 (unaligned), end at 3 (unaligned)
        // Should iterate through ticks in range (47, 3): none
        TickIteratorDown memory iter1 = TickIteratorLib.initDown(manager, pid, TICK_SPACING, 47, 3);
        assertFalse(iter1.hasNext(), "No ticks between 47 and 3");

        // Case 2: Start at 53 (unaligned), end at -53 (unaligned)
        // Should iterate through ticks in range (53, -53): 50, 0, -50
        TickIteratorDown memory iter2 =
            TickIteratorLib.initDown(manager, pid, TICK_SPACING, 53, -53);
        assertTrue(iter2.hasNext());
        assertEq(iter2.getNext(), 50);
        assertTrue(iter2.hasNext());
        assertEq(iter2.getNext(), 0);
        assertTrue(iter2.hasNext());
        assertEq(iter2.getNext(), -50);
        assertFalse(iter2.hasNext());

        // Case 3: Start at 1 (unaligned), end at -51 (unaligned)
        // Should iterate through ticks in range (1, -51): 0, -50
        TickIteratorDown memory iter3 = TickIteratorLib.initDown(manager, pid, TICK_SPACING, 1, -51);
        assertTrue(iter3.hasNext());
        assertEq(iter3.getNext(), 0);
        assertTrue(iter3.hasNext());
        assertEq(iter3.getNext(), -50);
        assertFalse(iter3.hasNext());
    }

    function test_iterateUp_unalignedWithLargeSpacing() public {
        // Test with tick spacing 200 and various unaligned positions
        key = PoolKey({
            currency0: Currency.wrap(address(token0)),
            currency1: Currency.wrap(address(token1)),
            fee: 10000,
            tickSpacing: 200,
            hooks: IHooks(address(0))
        });
        pid = key.toId();
        manager.initialize(key, INIT_SQRT_PRICE);

        // Add liquidity at aligned ticks for spacing 200
        router.modifyLiquidity(key, -600, -400, int256(1e18), bytes32(0));
        router.modifyLiquidity(key, -400, -200, int256(1e18), bytes32(0));
        router.modifyLiquidity(key, -200, 0, int256(1e18), bytes32(0));
        router.modifyLiquidity(key, 0, 200, int256(1e18), bytes32(0));
        router.modifyLiquidity(key, 200, 400, int256(1e18), bytes32(0));

        // Test with start tick 39 (39 % 200 = 39, heavily unaligned)
        // Exclusive bounds (39, 350)
        // Next aligned tick after 39 is 200, before 350 is 200
        // So we should only get tick 200
        TickIteratorUp memory iter = TickIteratorLib.initUp(manager, pid, 200, 39, 350);
        assertTrue(iter.hasNext());
        assertEq(iter.getNext(), 200);
        assertFalse(iter.hasNext());

        // Test with start tick -199 (just after -200)
        // Exclusive bounds (-199, 201)
        // Should get 0, 200
        TickIteratorUp memory iter2 = TickIteratorLib.initUp(manager, pid, 200, -199, 201);
        assertTrue(iter2.hasNext());
        assertEq(iter2.getNext(), 0);
        assertTrue(iter2.hasNext());
        assertEq(iter2.getNext(), 200);
        assertFalse(iter2.hasNext());
    }

    function test_iterateDown_unalignedWithLargeSpacing() public {
        // Test with tick spacing 200 and various unaligned positions
        key = PoolKey({
            currency0: Currency.wrap(address(token0)),
            currency1: Currency.wrap(address(token1)),
            fee: 10000,
            tickSpacing: 200,
            hooks: IHooks(address(0))
        });
        pid = key.toId();
        manager.initialize(key, INIT_SQRT_PRICE);

        // Add liquidity at aligned ticks for spacing 200
        router.modifyLiquidity(key, -400, -200, int256(1e18), bytes32(0));
        router.modifyLiquidity(key, -200, 0, int256(1e18), bytes32(0));
        router.modifyLiquidity(key, 0, 200, int256(1e18), bytes32(0));
        router.modifyLiquidity(key, 200, 400, int256(1e18), bytes32(0));

        // Test with start tick 350 (unaligned)
        // Exclusive bounds (350, 39)
        // Previous aligned tick before 350 is 200
        // Next aligned tick after 39 is 200
        // So we should only get tick 200
        TickIteratorDown memory iter = TickIteratorLib.initDown(manager, pid, 200, 350, 39);
        assertTrue(iter.hasNext());
        assertEq(iter.getNext(), 200);
        assertFalse(iter.hasNext());

        // Test with start tick 201 (just after 200)
        // Exclusive bounds (201, -199)
        // Should get 200, 0
        TickIteratorDown memory iter2 = TickIteratorLib.initDown(manager, pid, 200, 201, -199);
        assertTrue(iter2.hasNext());
        assertEq(iter2.getNext(), 200);
        assertTrue(iter2.hasNext());
        assertEq(iter2.getNext(), 0);
        assertFalse(iter2.hasNext());
    }

    function randomTick(Random memory r) internal pure returns (int24) {
        r.state = keccak256(abi.encode(r.state));
        uint256 rawValue =
            uint256(r.state) % uint256(int256(TickMath.MAX_TICK) - int256(TickMath.MIN_TICK) + 1);
        int24 tick = int24(int256(rawValue) + TickMath.MIN_TICK).normalizeUnchecked(TICK_SPACING);
        if (tick < TickMath.MIN_TICK) tick += TICK_SPACING;
        if (tick > TickMath.MAX_TICK) tick -= TICK_SPACING;
        require(TickMath.MIN_TICK <= tick && tick <= TickMath.MAX_TICK, "Tick out of bounds");
        return tick;
    }

    function sortTicks(int24 tickLower, int24 tickUpper) internal pure returns (int24, int24) {
        if (tickLower > tickUpper) (tickLower, tickUpper) = (tickUpper, tickLower);
        return (tickLower, tickUpper);
    }

    function logTicks(
        string memory message,
        int24 start,
        int24 end,
        int256[] memory ticks,
        uint256 wrongIndex
    ) internal pure returns (string memory) {
        string memory result =
            string.concat(message, ", start: ", start.toStr(), ", end: ", end.toStr(), ", ticks: [");

        for (uint256 i = 0; i < ticks.length; i++) {
            if (i > 0) result = string.concat(result, ", ");
            if (i == wrongIndex) result = string.concat(result, "(", ticks[i].toStr(), ")");
            else result = string.concat(result, ticks[i].toStr());
        }
        result = string.concat(result, "]");
        return result;
    }
}
