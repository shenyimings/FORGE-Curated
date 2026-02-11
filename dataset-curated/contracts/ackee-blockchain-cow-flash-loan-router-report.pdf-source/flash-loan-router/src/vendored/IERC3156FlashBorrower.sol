// SPDX-License-Identifier: CC0-1.0

pragma solidity ^0.7.0 || ^0.8.0;

// Vendored from the same contract in the ERC 3156 specifications with minor
// modifications:
// - Formatted code
// - Explicit licensing from <https://github.com/ethereum/EIPs/blob/f27ddf2b0af7e862a967ee38ceeaa7d980786ca1/LICENSE.md>
// <https://eips.ethereum.org/EIPS/eip-3156#receiver-specification>

interface IERC3156FlashBorrower {
    /**
     * @dev Receive a flash loan.
     * @param initiator The initiator of the loan.
     * @param token The loan currency.
     * @param amount The amount of tokens lent.
     * @param fee The additional amount of tokens to repay.
     * @param data Arbitrary data structure, intended to contain user-defined parameters.
     * @return The keccak256 hash of "ERC3156FlashBorrower.onFlashLoan"
     */
    function onFlashLoan(address initiator, address token, uint256 amount, uint256 fee, bytes calldata data)
        external
        returns (bytes32);
}
