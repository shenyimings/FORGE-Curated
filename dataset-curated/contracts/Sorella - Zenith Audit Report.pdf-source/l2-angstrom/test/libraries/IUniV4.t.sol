// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {IUniV4} from "../../src/interfaces/IUniV4.sol";
import {BaseTest} from "../_helpers/BaseTest.sol";
import {RouterActor} from "../_mocks/RouterActor.sol";
import {UniV4Inspector} from "../_mocks/UniV4Inspector.sol";
import {MockERC20} from "super-sol/mocks/MockERC20.sol";
import {console} from "forge-std/console.sol";
import {FormatLib} from "super-sol/libraries/FormatLib.sol";

contract IUniV4Test is BaseTest {
    using FormatLib for *;
    using PoolIdLibrary for PoolKey;
    using IUniV4 for UniV4Inspector;

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

    function test_nextTickLt() public {
        addLiquidityAtTicks(10, 20);

        (bool initialized, int24 nextTick) = manager.getNextTickLt(pid, 25, TICK_SPACING);
        console.log("initialized: %s", initialized);
        console.log("nextTick: %s", nextTick.toStr());
    }
}
