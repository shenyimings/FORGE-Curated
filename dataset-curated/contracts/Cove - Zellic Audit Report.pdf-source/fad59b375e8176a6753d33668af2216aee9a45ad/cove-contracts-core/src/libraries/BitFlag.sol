// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

library BitFlag {
    // Bit masks used in the popCount algorithm
    // Binary: ...0101 0101 0101 0101
    uint256 private constant MASK_ODD_BITS = 0x5555555555555555555555555555555555555555555555555555555555555555;
    // Binary: ...0011 0011 0011 0011
    uint256 private constant MASK_EVEN_PAIRS = 0x3333333333333333333333333333333333333333333333333333333333333333;
    // Binary: ...0000 1111 0000 1111
    uint256 private constant MASK_NIBBLES = 0x0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F;
    // Binary: ...0000 0001 0000 0001
    uint256 private constant BYTE_MULTIPLIER = 0x0101010101010101010101010101010101010101010101010101010101010101;

    /// @dev Counts the number of set bits in a bit flag using parallel counting.
    /// This algorithm is based on the "Counting bits set, in parallel" technique from:
    /// https://graphics.stanford.edu/~seander/bithacks.html#CountBitsSetParallel
    /// @param bitFlag The bit flag to count the number of set bits.
    /// @return count The number of set bits in the bit flag.
    function popCount(uint256 bitFlag) internal pure returns (uint256) {
        // The unchecked block is safe from overflow/underflow because:
        // 1. Each step only involves bitwise operations and additions, which can't overflow uint256.
        // 2. The maximum possible value of bitFlag is 2^256-1, which can be safely multiplied by BYTE_MULTIPLIER.
        // 3. The final result is always in the range [0, 256], so the right shift by 248 bits can't underflow.
        unchecked {
            // Optimization: If all bits are set, return 256 immediately
            if (bitFlag == type(uint256).max) {
                return 256;
            }

            // Step 1: Count bits in pairs
            // This step counts the number of set bits in each pair of bits
            // by subtracting the number of odd bits from the original count
            // Each result is stored in 2-bit chunks within the uint256
            bitFlag -= ((bitFlag >> 1) & MASK_ODD_BITS);

            // Step 2: Count bits in groups of 4
            // This step sums the counts of set bits in each group of 4 bits
            // Each result is stored in 4-bit chunks within the uint256
            bitFlag = (bitFlag & MASK_EVEN_PAIRS) + ((bitFlag >> 2) & MASK_EVEN_PAIRS);

            // Step 3: Sum nibbles (4-bit groups)
            // This step sums the counts from step 2 for each byte (8 bits)
            // Each result is stored in 8-bit chunks within the uint256
            bitFlag = (bitFlag + (bitFlag >> 4)) & MASK_NIBBLES;

            // Step 4: Sum all bytes and return final count
            // Multiply by BYTE_MULTIPLIER to sum all byte counts
            // Shift right by 248 (256 - 8) to get the final sum in the least significant byte
            return (bitFlag * BYTE_MULTIPLIER) >> 248;
        }
    }
}
