// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {IBorrower} from "../interface/IBorrower.sol";
import {IERC20} from "../vendored/IERC20.sol";

/// @title Loan Library
/// @author CoW DAO developers
/// @notice A library describing a flash-loan request by the flash-loan router
/// and providing related utility functions.
library Loan {
    /// @notice The representation of a flash-loan request by the flash-loan
    /// router.
    struct Data {
        /// @notice The amount of funds requested from the lender.
        uint256 amount;
        /// @notice The contract that directly requests the flash loan from the
        /// lender and eventually calls back the router.
        IBorrower borrower;
        /// @notice The contract that loans out the funds to the borrower.
        address lender;
        /// @notice The token that is requested in the flash loan.
        IERC20 token;
    }

    /// @notice A type that wraps a pointer to raw data in memory.
    /// @dev A loan is expected to be encoded in memory as follows:
    ///
    /// Content: |--  amount  --||-- borrower --||--  lender  --||--  token   --|
    /// Length:  |<--32 bytes-->||<--20 bytes-->||<--20 bytes-->||<--20 bytes-->|
    type EncodedData is uint256;

    // This is a list of offsets to add to the memory pointer to get the memory
    // location of the respective loan parameter. Note: -12 because addresses
    // are zero-padded to the left and mload/mstore work on groups of 32 bytes.
    uint256 private constant OFFSET_BORROWER = 32 - 12;
    uint256 private constant OFFSET_LENDER = 32 + 1 * 20 - 12;
    uint256 private constant OFFSET_TOKEN = 32 + 2 * 20 - 12;

    /// @notice The number of sequential bytes required to encode a loan in
    /// memory.
    uint256 internal constant ENCODED_LOAN_BYTE_SIZE = 32 + 3 * 20;

    /// @notice Write the input loan to the memory location pointed to by the
    /// input encodedLoan.
    /// @param encodedLoan The memory location from which to start writing the
    /// byte representation of the loan. It is assumed to have at least
    /// `ENCODED_LOAN_BYTE_SIZE` available from that point it in memory.
    /// @param loan The loan to store.
    function store(EncodedData encodedLoan, Data calldata loan) internal pure {
        uint256 amount = loan.amount;
        IBorrower borrower = loan.borrower;
        address lender = loan.lender;
        IERC20 token = loan.token;

        // Note: addresses are right-aligned, memory is written to starting
        // from the end and overwriting the address left-side padding.
        assembly ("memory-safe") {
            // Unchecked: we assume that the input value isn't at the end of the
            // memory array. This does not happen with Solidity standard memory
            // allocation.
            mstore(add(encodedLoan, OFFSET_TOKEN), token)
            mstore(add(encodedLoan, OFFSET_LENDER), lender)
            mstore(add(encodedLoan, OFFSET_BORROWER), borrower)
            // offset is zero
            mstore(encodedLoan, amount)
        }
    }

    /// @notice Reads the loan parameter from the input location in memory.
    /// @param loan The memory location from which to read the loan.
    /// @return amount The amount to be borrowed (see `Loan.Data`).
    /// @return borrower The address of the borrower contract (see `Loan.Data`).
    /// @return lender The lender address (see `Loan.Data`).
    /// @return token The token to borrow (see `Loan.Data`).
    function decode(EncodedData loan)
        internal
        pure
        returns (uint256 amount, IBorrower borrower, address lender, IERC20 token)
    {
        assembly ("memory-safe") {
            // Note: the values don't need to be masked since masking occurs
            // when the value is accessed and not when stored.
            // <https://docs.soliditylang.org/en/v0.8.28/assembly.html#access-to-external-variables-functions-and-libraries>
            amount := mload(loan)
            borrower := mload(add(loan, OFFSET_BORROWER))
            lender := mload(add(loan, OFFSET_LENDER))
            token := mload(add(loan, OFFSET_TOKEN))
        }
    }
}
