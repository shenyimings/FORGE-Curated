// SPDX-License-Identifier: ISC
pragma solidity 0.8.25;

interface IClaimable {
    /**
     * @notice Proves that the provided address has the provided initial balance, enabling claim and voting.
     * @dev The merkle proof is for a merkle tree for which leaves take the form
     * `abi.encode(address _address, uint256 _balance)`.
     *
     * This function will revert if the provided merkle proof is not valid UNLESS a balance for the account had previously
     * been proven via a successful invocation of this function, in which case this is a no-op that always returns 0.
     * @param _address The address of the account for which the initial balance is being proven.
     * @param _initialBalance The initial balance of the address, as proven by the provided merkle proof.
     * @param _proof The merkle proof that proves the initial balance for the address.
     * @return The amount that has been proven that was not previously proven (will be 0 after initial call for an address).
     */
    function proveInitialBalance(
        address _address,
        uint256 _initialBalance,
        bytes32[] calldata _proof
    ) external returns (uint256);
}
