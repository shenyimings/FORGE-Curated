// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Hooks} from "v4-core/src/libraries/Hooks.sol";

bool constant POOLS_MUST_HAVE_DYNAMIC_FEE = false;

function getRequiredHookPermissions() pure returns (Hooks.Permissions memory permissions) {
    permissions.beforeInitialize = true; // To constrain that this is an ETH pool

    permissions.afterAddLiquidity = true; // To tax liquidity additions that may be JIT
    permissions.afterAddLiquidityReturnDelta = true; // To charge the JIT liquidity MEV tax.

    permissions.afterRemoveLiquidity = true; // To tax liquidity removals that may be JIT
    permissions.afterRemoveLiquidityReturnDelta = true; // To charge the JIT liquidity MEV tax.

    permissions.beforeSwap = true; // To tax ToB
    permissions.afterSwap = true; // Also to tax with ToB (after swap contains reward dist. calculations)
    permissions.beforeSwapReturnDelta = true; // To charge the ToB MEV tax.
}
