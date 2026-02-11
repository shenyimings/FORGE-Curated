// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// Vendored from Aave DAO contracts with minor modifications:
// - Removed view functions `ADDRESSES_PROVIDER` and `POOL` (and related import)
// - Changed contract name to make it specific to Aave
// - Updated imports
// - Formatted code
// <https://github.com/aave-dao/aave-v3-origin/blob/v3.1.0/src/core/contracts/flashloan/interfaces/IFlashLoanReceiver.sol>
// Note: v3.1.0 points to commit e627c7428cbb358b9c84b601a009a86b4b871c08.

/**
 * @title IFlashLoanReceiver
 * @author Aave
 * @notice Defines the basic interface of a flashloan-receiver contract.
 * @dev Implement this interface to develop a flashloan-compatible flashLoanReceiver contract
 */
interface IAaveFlashLoanReceiver {
    /**
     * @notice Executes an operation after receiving the flash-borrowed assets
     * @dev Ensure that the contract can return the debt + premium, e.g., has
     *      enough funds to repay and has approved the Pool to pull the total amount
     * @param assets The addresses of the flash-borrowed assets
     * @param amounts The amounts of the flash-borrowed assets
     * @param premiums The fee of each flash-borrowed asset
     * @param initiator The address of the flashloan initiator
     * @param params The byte-encoded params passed when initiating the flashloan
     * @return True if the execution of the operation succeeds, false otherwise
     */
    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external returns (bool);
}
