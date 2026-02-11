// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {LibBit} from "solady/src/utils/LibBit.sol";
import {FixedPointMathLib} from "solady/src/utils/FixedPointMathLib.sol";

/// @author philogy <https://github.com/philogy>
library Math512Lib {
    error Overflow();
    error Underflow();
    error DivisorZero();

    function fullMul(uint256 x, uint256 y) internal pure returns (uint256 z1, uint256 z0) {
        assembly {
            z0 := mul(x, y) // Lower 256 bits of `x * y`.
            let mm := mulmod(x, y, not(0))
            z1 := sub(mm, add(z0, lt(mm, z0))) // Upper 256 bits of `x * y`.
        }
    }

    /// @dev Computes `[z1 z0] = [x1 x0] + [y1 y0]`, reverts on overflow.
    function checkedAdd(uint256 x1, uint256 x0, uint256 y1, uint256 y0)
        internal
        pure
        returns (uint256 z1, uint256 z0)
    {
        bool overflowed;
        assembly {
            z0 := add(x0, y0)
            // Add upper limbs and carry
            z1 := add(add(x1, y1), lt(z0, x0))
            overflowed := or(lt(z1, x1), lt(z1, lt(z0, x0)))
        }
        if (overflowed) revert Overflow();
    }

    /// @dev Computes `[z1 z0] = [x1 x0] - [y1 y0]`, reverts on underflow.
    function checkedSub(uint256 x1, uint256 x0, uint256 y1, uint256 y0)
        internal
        pure
        returns (uint256 z1, uint256 z0)
    {
        bool underflowed;
        assembly {
            z0 := sub(x0, y0)
            // Subtract upper limbs and carry
            z1 := sub(sub(x1, y1), gt(y0, x0))
            underflowed := or(gt(z1, x1), and(eq(x1, y1), gt(y0, x0)))
        }
        if (underflowed) revert Underflow();
    }

    function checkedMul2Pow192(uint256 x1, uint256 x0)
        internal
        pure
        returns (uint256 y1, uint256 y0)
    {
        if (!((x1 << 192) >> 192 == x1)) revert Overflow();
        return ((x1 << 192) | (x0 >> 64), x0 << 192);
    }

    function checkedMul2Pow96(uint256 x1, uint256 x0)
        internal
        pure
        returns (uint256 y1, uint256 y0)
    {
        if (!((x1 << 96) >> 96 == x1)) revert Overflow();
        return ((x1 << 96) | (x0 >> 160), x0 << 96);
    }

    function sqrt512(uint256 x1, uint256 x0) internal pure returns (uint256 root) {
        if (x1 == 0) {
            return FixedPointMathLib.sqrt(x0);
        }

        unchecked {
            // There are two edge cases where intermediate guess values will cause the
            // `[x1 x0] / guess` division to result in a value larger than 256 bits. Specifically:
            // sqrt([2^256-1, _]) => 2^256-1
            // sqrt([2^256-2, 0]) => 2^256-2
            // We can handle these explicitly to ensure the remaining logic can use the invariant that
            // `[x1 x0] / guess` fits within 256 bits. For all `x in range([2^256-2, 1], MAX_UINT512)
            // sqrt(x) => 2^256-1; x = [2^256-2, 0] sqrt(x) => 2^256-2`.
            if (x1 + 2 < 2) {
                assembly {
                    root := or(x1, gt(x0, 0))
                }
                return root;
            }
            root = 1 << (129 + (LibBit.fls(x1) >> 1));
            root -= 1;
        }
        uint256 last;
        do {
            last = root;
            // The above invariant lets us safely discard the upper bits of the result. This is
            // because our guess always starts at or above the correct result and monotonically
            //1 decreases towards the correct result.
            (, root) = div512by256(x1, x0, root);
            root = FixedPointMathLib.avg(root, last);
        } while (root < last);
        return last;
    }

    /// @dev Computes `[x1 x0] / d`
    function div512by256(uint256 x1, uint256 x0, uint256 d)
        internal
        pure
        returns (uint256 y1, uint256 y0)
    {
        if (d == 0) revert DivisorZero();
        assembly {
            // Compute first "digit" of long division result
            y1 := div(x1, d)
            // We take the remainder to continue the long division
            let r1 := mod(x1, d)
            // We complete the long division by computing `y0 = [r1 x0] / d`. We use the "512 by
            // 256 division" logic from Solady's `fullMulDiv` (Credit under MIT license:
            // https://github.com/Vectorized/solady/blob/main/src/utils/FixedPointMathLib.sol)

            // We need to compute `[r1 x0] mod d = r1 * 2^256 + x0 = r1 * (2^256 - 1 + 1) + x0 =
            // r1 * (2^256 - 1) + r1 + x0`.
            let r := addmod(addmod(mulmod(r1, not(0), d), r1, d), x0, d)

            // Same math from Solady, reference `fullMulDiv` for explanation.
            let t := and(d, sub(0, d))
            d := div(d, t)
            let inv := xor(2, mul(3, d)) // inverse mod 2**4
            inv := mul(inv, sub(2, mul(d, inv))) // inverse mod 2**8
            inv := mul(inv, sub(2, mul(d, inv))) // inverse mod 2**16
            inv := mul(inv, sub(2, mul(d, inv))) // inverse mod 2**32
            inv := mul(inv, sub(2, mul(d, inv))) // inverse mod 2**64
            inv := mul(inv, sub(2, mul(d, inv))) // inverse mod 2**128
            // Edits vs Solady: `x0` replaces `z`, `r1` replaces `p1`, final 256-bit result stored in `y0`
            y0 :=
                mul(
                    or(mul(sub(r1, gt(r, x0)), add(div(sub(0, t), t), 1)), div(sub(x0, r), t)),
                    mul(sub(2, mul(d, inv)), inv) // inverse mod 2**256
                )
        }
    }
}
