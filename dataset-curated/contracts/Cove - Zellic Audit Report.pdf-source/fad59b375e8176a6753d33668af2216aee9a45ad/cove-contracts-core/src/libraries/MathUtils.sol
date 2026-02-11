// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

/// @title MathUtils
/// @notice A library to perform math operations with optimizations.
/// @dev This library is based on the code snippet from the OpenZeppelin Contracts Math library.
// solhint-disable-next-line max-line-length
/// https://github.com/OpenZeppelin/openzeppelin-contracts/blob/05d4bf57ffed8c65256ff4ede5c3cf7a0b738e7d/contracts/utils/math/Math.sol
library MathUtils {
    /// @notice Calculates the absolute difference between two unsigned integers.
    /// @param a The first number.
    /// @param b The second number.
    /// @return The absolute difference between `a` and `b`.
    function diff(uint256 a, uint256 b) internal pure returns (uint256) {
        unchecked {
            // Safe from overflow/underflow: result is always less than larger input.
            return a > b ? a - b : b - a;
        }
    }
}
