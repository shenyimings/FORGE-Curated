// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {Test} from "forge-std/Test.sol";

import {IBorrower, IERC20, Loan} from "src/library/Loan.sol";

import {Bytes} from "src/library/Bytes.sol";

function someLoan(uint256 salt) pure returns (Loan.Data memory) {
    return Loan.Data({
        amount: uint256(keccak256(bytes.concat("any large number", bytes32(salt)))),
        borrower: IBorrower(address(uint160(bytes20(keccak256("some borrower address"))))),
        lender: address(uint160(bytes20(keccak256("some lender address")))),
        token: IERC20(address(uint160(bytes20(keccak256("some token address")))))
    });
}

/// @dev We use a separate contract for encoding and decoding instead of
/// direcly using the library in the test to avoid corrupting memory in the
/// execution of the test itself.
contract RoundTripEncoder {
    using Bytes for bytes;
    using Loan for Loan.EncodedData;

    function allocateToBytes() private pure returns (bytes memory) {
        return new bytes(Loan.ENCODED_LOAN_BYTE_SIZE);
    }

    function allocate() private pure returns (Loan.EncodedData) {
        bytes memory encodedData = allocateToBytes();
        return Loan.EncodedData.wrap(encodedData.memoryPointerToContent());
    }

    function encode(Loan.Data calldata loanRequest) public pure returns (bytes memory encodedData) {
        encodedData = allocateToBytes();
        Loan.EncodedData.wrap(encodedData.memoryPointerToContent()).store(loanRequest);
    }

    function storeAndDecode(Loan.Data calldata loanRequest) external pure returns (Loan.Data memory) {
        Loan.EncodedData encodedLoan = allocate();
        encodedLoan.store(loanRequest);
        (uint256 amount, IBorrower borrower, address lender, IERC20 token) = encodedLoan.decode();
        return Loan.Data({amount: amount, borrower: borrower, lender: lender, token: token});
    }
}

contract LoanTest is Test {
    RoundTripEncoder private encoder;

    function setUp() external {
        encoder = new RoundTripEncoder();
    }

    function test_encodeToExpectedBytestring() external view {
        Loan.Data memory loan = Loan.Data({
            amount: 0x0101010101010101010101010101010101010101010101010101010101010101, // 32 bytes
            borrower: IBorrower(0x0202020202020202020202020202020202020202),
            lender: address(0x0303030303030303030303030303030303030303),
            token: IERC20(address(0x0404040404040404040404040404040404040404))
        });
        bytes memory expectedEncodedBytestring = bytes.concat(
            hex"0101010101010101010101010101010101010101010101010101010101010101",
            hex"0202020202020202020202020202020202020202",
            hex"0303030303030303030303030303030303030303",
            hex"0404040404040404040404040404040404040404"
        );
        assertEq(encoder.encode(loan), expectedEncodedBytestring);
    }

    function testFuzz_encodeToAbiEncodePackedInput(Loan.Data memory loan) external view {
        bytes memory expectedEncodedBytestring = abi.encodePacked(loan.amount, loan.borrower, loan.lender, loan.token);
        assertEq(encoder.encode(loan), expectedEncodedBytestring);
    }

    function testFuzz_encodeRoundtrip(Loan.Data memory loan) external view {
        assertEq(loan, encoder.storeAndDecode(loan));
    }

    function assertEq(Loan.Data memory lhs, Loan.Data memory rhs) private pure {
        assertEq(lhs.amount, rhs.amount);
        assertEq(address(lhs.borrower), address(rhs.borrower));
        assertEq(address(lhs.lender), address(rhs.lender));
        assertEq(address(lhs.token), address(rhs.token));
    }
}
