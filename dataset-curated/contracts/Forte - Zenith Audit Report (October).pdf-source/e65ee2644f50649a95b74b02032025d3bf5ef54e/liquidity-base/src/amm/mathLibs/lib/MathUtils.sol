// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

/**
 * @title Utility function for equations
 * @author  @oscarsernarosero @mpetersoCode55 @cirsteve
 */
library MathUtils {
    uint256 constant WAD = 1e18;

    /**
     * @dev This function converts a raw number to a WAD number
     * @param value The number to be converted
     * @return result resulting WAD number
     */
    function convertToWAD(uint256 value) internal pure returns (uint256 result) {
        result = value * WAD;
    }

    /**
     * @dev This function converts a WAD number to a raw number
     * @param value The number to be converted
     * @return result resulting raw number
     */
    function convertToRaw(uint256 value) internal pure returns (uint256 result) {
        result = value / WAD;
    }

    /**
     * @dev this function tells how many WADs a number needs to be divided by to get to 0
     * @param x the number to be divided
     * @return precisionSlashingFactor the number of WADs needed to be divided to get to 0
     */
    function findWADsToSlashTo0(uint256 x) internal pure returns (uint256 precisionSlashingFactor) {
        // this loop could be possibly run only 5 times since a 256-bit number can only shift 59 bits
        // 5 times to cover the totality of the bits.
        while (x > 0) {
            // we shift enough bits to the right to emulate a division by WAD
            x = x >> 59; // shifting 59 bits to the right is the same as dividing by 0.57e18
            unchecked {
                ++precisionSlashingFactor;
            }
        }
    }
}
