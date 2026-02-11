// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

/// @title Interface for mintable and burnable tokens that DOES NOT return success boolean
interface IMintBurnVoidReturn {
    /**
     * @notice Burns tokens from a specified account
     * @param from Address from which tokens will be burned
     * @param amount Amount of tokens to be burned
     */
    function burn(address from, uint256 amount) external;

    /**
     * @notice Mints tokens to a specified account
     * @param to Address to which tokens will be minted
     * @param amount Amount of tokens to be minted
     */
    function mint(address to, uint256 amount) external;
}