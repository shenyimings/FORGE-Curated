// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;

import {PoolId} from "../../src/types/PoolId.sol";
import {PoolKey} from "../../src/types/PoolKey.sol";
import {Reserves} from "../../src/types/Reserves.sol";
import {StateLibrary} from "../../src/libraries/StateLibrary.sol";
import {IVault} from "../../src/interfaces/IVault.sol";

library LikwidChecker {
    function checkPoolReserves(IVault vault, PoolKey memory key) internal view {
        PoolId poolId = key.toId();
        Reserves realReserves = StateLibrary.getRealReserves(vault, poolId);
        Reserves mirrorReserves = StateLibrary.getMirrorReserves(vault, poolId);
        Reserves pairReserves = StateLibrary.getPairReserves(vault, poolId);
        Reserves lendReserves = StateLibrary.getLendReserves(vault, poolId);
        (uint128 realReserve0, uint128 realReserve1) = realReserves.reserves();
        (uint128 mirrorReserve0, uint128 mirrorReserve1) = mirrorReserves.reserves();
        (uint128 pairReserve0, uint128 pairReserve1) = pairReserves.reserves();
        (uint128 lendReserve0, uint128 lendReserve1) = lendReserves.reserves();
        require(realReserve0 + mirrorReserve0 == pairReserve0 + lendReserve0, "reserve0 should equal pair + lend");
        require(realReserve1 + mirrorReserve1 == pairReserve1 + lendReserve1, "reserve1 should equal pair + lend");
    }
}
