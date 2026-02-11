// SPDX-License-Identifier: BUSL-1.1
// Likwid Contracts
pragma solidity 0.8.28;

import {Currency} from "../types/Currency.sol";

library CurrencyGuard {
    /// @dev uint256 internal constant CURRENCY_DELTA = uint256(keccak256("CURRENCY_DELTA")) - 1;
    uint256 internal constant CURRENCY_DELTA = 0xd9bd4e389ed8cbf1cf078cf6e39b899ba664e27ad65dbc00c572373981e91d5e;

    /// @dev ref: https://docs.soliditylang.org/en/v0.8.24/internals/layout_in_storage.html#mappings-and-dynamic-arrays
    /// simulating mapping index but with a single hash
    /// save one keccak256 hash compared to built-in nested mapping
    function _currencyDeltaSlot(Currency currency, address target) internal pure returns (bytes32 hashSlot) {
        hashSlot = keccak256(abi.encode(currency, target, CURRENCY_DELTA));
    }

    function currentDelta(Currency currency, address target) internal view returns (int256 delta) {
        bytes32 hashSlot = _currencyDeltaSlot(currency, target);
        assembly ("memory-safe") {
            delta := tload(hashSlot)
        }
    }

    function appendDelta(Currency currency, address target, int128 delta)
        internal
        returns (int256 previous, int256 current)
    {
        bytes32 hashSlot = _currencyDeltaSlot(currency, target);

        assembly ("memory-safe") {
            previous := tload(hashSlot)
        }
        current = previous + delta;
        assembly ("memory-safe") {
            tstore(hashSlot, current)
        }
    }
}
