// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.0;

/**
 * @title IDaiUsdsConverter
 * @notice Interface for converting between DAI and USDS tokens
 * @dev This interface defines the standard for bi-directional conversion
 * between DAI and USDS. Implementations handle the actual conversion
 * logic and rates.
 */
interface IDaiUsdsConverter {
    /**
     * @notice Converts DAI tokens to USDS tokens
     * @dev Converts the specified amount of DAI to USDS for the given user.
     * The conversion rate and mechanism depend on the implementation.
     * @param usr The address of the user receiving the converted USDS tokens
     * @param wad The amount of DAI tokens to convert (in wei/wad units)
     */
    function daiToUsds(address usr, uint256 wad) external;

    /**
     * @notice Converts USDS tokens to DAI tokens
     * @dev Converts the specified amount of USDS to DAI for the given user.
     * The conversion rate and mechanism depend on the implementation.
     * @param usr The address of the user receiving the converted DAI tokens
     * @param wad The amount of USDS tokens to convert (in wei/wad units)
     */
    function usdsToDai(address usr, uint256 wad) external;
}
