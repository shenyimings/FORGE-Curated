// SPDX-License-Identifier: BUSL-1.1
// Likwid Contracts
pragma solidity ^0.8.26;

import {Math} from "./Math.sol";
import {SafeCast} from "./SafeCast.sol";
import {PerLibrary} from "./PerLibrary.sol";
import {Reserves, toReserves} from "../types/Reserves.sol";

library PriceMath {
    using SafeCast for *;
    using PerLibrary for *;

    function transferReserves(
        Reserves originReserves,
        Reserves destReserves,
        uint256 timeElapsed,
        uint24 maxPriceMovePerSecond
    ) internal pure returns (Reserves result) {
        if (destReserves.bothPositive()) {
            if (!originReserves.bothPositive()) {
                result = destReserves;
            } else {
                (uint256 truncatedReserve0, uint256 truncatedReserve1) = originReserves.reserves();
                uint256 priceMoved = maxPriceMovePerSecond * (timeElapsed ** 2);
                uint128 newTruncatedReserve0 = 0;
                uint128 newTruncatedReserve1 = destReserves.reserve1();
                uint256 _reserve0 = destReserves.reserve0();

                uint256 reserve0Min =
                    Math.mulDiv(newTruncatedReserve1, truncatedReserve0.lowerMillion(priceMoved), truncatedReserve1);
                uint256 reserve0Max =
                    Math.mulDiv(newTruncatedReserve1, truncatedReserve0.upperMillion(priceMoved), truncatedReserve1);
                if (_reserve0 < reserve0Min) {
                    newTruncatedReserve0 = reserve0Min.toUint128();
                } else if (_reserve0 > reserve0Max) {
                    newTruncatedReserve0 = reserve0Max.toUint128();
                } else {
                    newTruncatedReserve0 = _reserve0.toUint128();
                }
                result = toReserves(newTruncatedReserve0, newTruncatedReserve1);
            }
        } else {
            result = destReserves;
        }
    }
}
