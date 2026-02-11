// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {IBorrower} from "../interface/IBorrower.sol";
import {IERC20} from "../vendored/IERC20.sol";
import {Bytes} from "./Bytes.sol";
import {Loan} from "./Loan.sol";

/// @title Loans-with-settlement Library
/// @author CoW DAO developers
/// @notice A library describing a settlement execution through the flash-loan
/// router and providing related utility functions.
/// @dev This library is used to manage an encoded representation of a list of
/// loans with a settlement as a bytes array. An abstract representation of it
/// as a Solidity struct would be:
///
/// struct Data {
///     Loan.Data[] loans;
///     bytes settlement;
/// }
///
/// The encoding of the bytes array for n loans is as follows:
///
/// Content: |-- number of loans, n --||-- ABI-encoded settlement --||-- n-th Loan  --||-- (n-1)-th Loan --|...|-- 1-st Loan  --|
/// Length:  |<--     32 bytes     -->||<--    arbitrary size    -->||<--size(Loan)-->||<-- size(Loan)  -->|...|<--size(Loan)-->|
///
/// Loans are stored right to left so that it's easy to pop them in order
/// without having to shift all remaining loans in memory.
library LoansWithSettlement {
    using Bytes for bytes;
    using Loan for Loan.EncodedData;

    /// @notice The number of bytes reserved for the encoding of the loan count.
    uint256 private constant LOAN_COUNT_SIZE = 32;

    /// @notice The number of loans in the input.
    /// @param loansWithSettlement The list of loans with settlement.
    /// @return count Number of loans in the input.
    function loanCount(bytes memory loansWithSettlement) internal pure returns (uint256 count) {
        uint256 pointer = loansWithSettlement.memoryPointerToContent();
        assembly ("memory-safe") {
            count := mload(pointer)
        }
    }

    /// @notice A collision-resistent identifier for the input list of loans
    /// with settlement.
    /// @param loansWithSettlement The list of loans with settlement to hash.
    /// @return A collision-resistent identifier for the input.
    function hash(bytes memory loansWithSettlement) internal pure returns (bytes32) {
        return keccak256(loansWithSettlement);
    }

    /// @notice Store the list of loans and the settlement in a format
    /// expected by this library.
    /// @param loans List of requested loans.
    /// @param settlement ABI-encoded settlement call data.
    /// @return encodedLoansWithSettlement encoded representation of the input
    /// parameters.
    function encode(Loan.Data[] calldata loans, bytes calldata settlement)
        internal
        pure
        returns (bytes memory encodedLoansWithSettlement)
    {
        uint256 encodedLength;
        unchecked {
            // Unchecked: the input values are bounded by the gas cost of
            // including the data in a transaction.
            encodedLength = LOAN_COUNT_SIZE + settlement.length + loans.length * Loan.ENCODED_LOAN_BYTE_SIZE;
        }
        encodedLoansWithSettlement = Bytes.allocate(encodedLength);

        // Keep track of the fist yet-unwritten-to byte
        uint256 head = encodedLoansWithSettlement.memoryPointerToContent();
        assembly ("memory-safe") {
            mstore(head, loans.length)
        }

        unchecked {
            // Unchecked: `head` is bounded by `encodedLength`.
            head += LOAN_COUNT_SIZE;
        }
        assembly ("memory-safe") {
            calldatacopy(head, settlement.offset, settlement.length)
        }

        unchecked {
            // Unchecked: `head` is bounded by `encodedLength`.
            head += settlement.length;
        }
        for (uint256 i = loans.length; i > 0;) {
            unchecked {
                // Unchecked: loop condition prevents underflows.
                i--;
            }
            Loan.EncodedData encodedLoan = Loan.EncodedData.wrap(head);
            encodedLoan.store(loans[i]);
            unchecked {
                // Unchecked: `head` is bounded by `encodedLength`.
                head += Loan.ENCODED_LOAN_BYTE_SIZE;
            }
        }
    }

    /// @notice Remove the next loan that is to be processed from the encoded
    /// input data and return its parameter.
    /// @dev The element are popped from the first to the last in the order they
    /// were presented *before encoding*.
    /// @param loansWithSettlement The encoded data from which to remove the
    /// next loan. It must be a valid encoding of loans with settlement of
    /// length at least one.
    /// @return amount The amount to be borrowed (see `Loan.Data`).
    /// @return borrower The address of the borrower contract (see `Loan.Data`).
    /// @return lender The lender address (see `Loan.Data`).
    /// @return token The token to borrow (see `Loan.Data`).
    function popLoan(bytes memory loansWithSettlement)
        internal
        pure
        returns (uint256 amount, IBorrower borrower, address lender, IERC20 token)
    {
        uint256 count = loanCount(loansWithSettlement);
        require(count > 0, "No loans available");

        uint256 updatedLoansWithSettlementLength;
        unchecked {
            // Unchecked: there is at least a loan.
            count = count - 1;
            // Unchecked: loansWithSettlement is properly encoded and has a
            // loan, meaning that it has at least length
            // `Loan.ENCODED_LOAN_BYTE_SIZE`
            updatedLoansWithSettlementLength = loansWithSettlement.length - Loan.ENCODED_LOAN_BYTE_SIZE;
        }

        uint256 loansWithSettlementPointer = loansWithSettlement.memoryPointerToContent();
        uint256 loanPointer;
        unchecked {
            // Unchecked: the pointer refers to a memory location inside
            // loansWithSettlement, which is assumed to be a valid array.
            loanPointer = loansWithSettlementPointer + updatedLoansWithSettlementLength;
        }
        Loan.EncodedData encodedLoan = Loan.EncodedData.wrap(loanPointer);

        assembly ("memory-safe") {
            // Efficiently reduce the size of the bytes array.
            // The length of a dynamic array is stored at the first slot of the
            // array and followed by the array elements.
            // Memory is never freed, so the remaining unused memory won't
            // affect the compiler.
            // <https://docs.soliditylang.org/en/v0.8.28/internals/layout_in_memory.html>
            mstore(loansWithSettlement, updatedLoansWithSettlementLength)
            // Update first encoded element: the loan count.
            mstore(loansWithSettlementPointer, count)
        }

        return encodedLoan.decode();
    }

    /// @notice Takes an input value with no encoded loans, destroys its content
    /// in memory, and extracts the settlement stored as part of its encoding.
    /// @dev This function overwrites the low-level memory representation of
    /// the input value, meaning that trying to use the input after calling
    /// this function leads to broken code. This functon takes full ownership
    /// of the memory representing the input.
    /// @param loansWithSettlement The encoded data representing loans with a
    /// settlement. It must have valid encoding. This value will be destroyed
    /// by calling this function and must not be used anywhere else.
    /// @return settlement The settlement encoded in the input.
    function destroyToSettlement(bytes memory loansWithSettlement) internal pure returns (bytes memory settlement) {
        require(loanCount(loansWithSettlement) == 0, "Pending loans");
        // We assume that the input is loans with a settlement, encoded as
        // expected by this library. The settlement data is a subarray of the
        // input: if we accept to override the input data with arbitrary data,
        // we can carve out a valid ABI-encoded bytes array representing the
        // settlement.
        uint256 settlementLength;
        unchecked {
            // Unchecked: we assume `loansWithSettlement` to be valid encoded
            // loans with settlement. Since there are no loans, this means that
            // it comprises the loan count plus the settlement data, which is at
            // least zero.
            settlementLength = loansWithSettlement.length - LOAN_COUNT_SIZE;
        }

        // We rely on the fact that LOAN_COUNT_SIZE is 32, exactly the size
        // needed to store the length of a memory array.
        uint256 settlementPointer = loansWithSettlement.memoryPointerToContent();

        assembly ("memory-safe") {
            mstore(settlementPointer, settlementLength)
            settlement := settlementPointer
        }
    }
}
