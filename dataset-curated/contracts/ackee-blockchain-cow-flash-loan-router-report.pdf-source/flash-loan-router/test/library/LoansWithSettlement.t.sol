// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {Test} from "forge-std/Test.sol";

import {IBorrower, IERC20, Loan, LoansWithSettlement} from "src/library/LoansWithSettlement.sol";

import {someLoan} from "./Loan.t.sol";
import {Bytes} from "test/test-lib/Bytes.sol";

// We use a separate encoder contract instead of doing library operations
// directly in the test to make sure that incorrect memory operations don't
// break the state of the tests in a way that still makes them pass.
contract LoanWithSettlementEncoder {
    using LoansWithSettlement for bytes;

    function encode(Loan.Data[] calldata loans, bytes calldata settlement) external pure returns (bytes memory) {
        return LoansWithSettlement.encode(loans, settlement);
    }

    function encodeAndCountLoans(Loan.Data[] calldata loans, bytes calldata settlement)
        external
        pure
        returns (uint256)
    {
        bytes memory encodedLoansWithSettlement = LoansWithSettlement.encode(loans, settlement);
        return encodedLoansWithSettlement.loanCount();
    }

    function encodeAndPopLoan(Loan.Data[] calldata loans, bytes calldata settlement)
        external
        pure
        returns (Loan.Data memory loan)
    {
        bytes memory encodedLoansWithSettlement = LoansWithSettlement.encode(loans, settlement);
        (uint256 amount, IBorrower borrower, address lender, IERC20 token) = encodedLoansWithSettlement.popLoan();
        loan = Loan.Data({amount: amount, borrower: borrower, lender: lender, token: token});
        require(encodedLoansWithSettlement.loanCount() == loans.length - 1, "popped length does not decrease by one");
    }

    function encodeAndExtractSettlement(Loan.Data[] calldata loans, bytes calldata settlement)
        external
        pure
        returns (bytes memory)
    {
        bytes memory encodedLoansWithSettlement = LoansWithSettlement.encode(loans, settlement);
        return encodedLoansWithSettlement.destroyToSettlement();
    }

    function encodePopLoanAndHash(Loan.Data[] calldata loans, bytes calldata settlement)
        external
        pure
        returns (bytes32)
    {
        bytes memory encodedLoansWithSettlement = LoansWithSettlement.encode(loans, settlement);
        encodedLoansWithSettlement.popLoan();
        return encodedLoansWithSettlement.hash();
    }

    function popLoan(bytes memory encodedLoansWithSettlement) external pure returns (bytes memory, Loan.Data memory) {
        (uint256 amount, IBorrower borrower, address lender, IERC20 token) = encodedLoansWithSettlement.popLoan();
        Loan.Data memory loan = Loan.Data({amount: amount, borrower: borrower, lender: lender, token: token});
        return (encodedLoansWithSettlement, loan);
    }

    function hash(bytes memory encodedLoansWithSettlement) external pure returns (bytes32) {
        return encodedLoansWithSettlement.hash();
    }

    function extractSettlement(bytes memory encodedLoansWithSettlement) external pure returns (bytes memory) {
        return encodedLoansWithSettlement.destroyToSettlement();
    }

    /// @dev An external call is the easiest way to copy a memory object by
    /// value in Solidity.
    function copy(Loan.Data[] calldata loans, bytes memory settlement)
        external
        pure
        returns (Loan.Data[] memory, bytes memory)
    {
        return (loans, settlement);
    }
}

contract LoansWithSettlementTest is Test {
    using LoansWithSettlement for bytes;

    // Fuzz test input size needs to be limited to avoid out-of-memory reverts
    // (MemoryOOG).
    uint256 private constant MAX_FUZZ_LOAN_COUNT = 100;
    uint256 private constant MAX_FUZZ_SETTLEMENT_SIZE = 100_000;

    LoanWithSettlementEncoder private loanWithSettlementEncoder;

    function setUp() external {
        loanWithSettlementEncoder = new LoanWithSettlementEncoder();
    }

    function testFuzz_encodedDataHasExpectedLoanCount(Loan.Data[] memory loans, bytes memory settlement)
        external
        view
    {
        uint256 loanCount = loanWithSettlementEncoder.encodeAndCountLoans(loans, settlement);
        assertEq(loanCount, loans.length);
    }

    function testFuzz_encodedDataPopsExpectedLoan(Loan.Data[] memory loans, bytes memory settlement) external view {
        // We want to replace the first loan, which needs to exist.
        vm.assume(loans.length > 0);
        Loan.Data memory expectedLoan = someLoan(0);
        loans[0] = expectedLoan;
        Loan.Data memory loan = loanWithSettlementEncoder.encodeAndPopLoan(loans, settlement);
        assertEq(expectedLoan, loan);
    }

    function testFuzz_revertsOnPoppingWithNoLoans(bytes memory settlement) external {
        Loan.Data[] memory loans = new Loan.Data[](0);
        vm.expectRevert("No loans available");
        loanWithSettlementEncoder.encodeAndPopLoan(loans, settlement);
    }

    function testFuzz_extractsSettlementFromInputWithNoLoans(bytes memory expectedSettlement) external view {
        bytes memory settlement =
            loanWithSettlementEncoder.encodeAndExtractSettlement(new Loan.Data[](0), expectedSettlement);
        assertEq(settlement, expectedSettlement);
    }

    function testFuzz_revertsIfExtractingSettlementWithPendingLoans(
        Loan.Data[] memory loans,
        bytes memory expectedSettlement
    ) external {
        vm.assume(loans.length > 0);
        vm.expectRevert("Pending loans");
        loanWithSettlementEncoder.encodeAndExtractSettlement(loans, expectedSettlement);
    }

    function testFuzz_hashingIsSensitiveToChanges(Loan.Data[] memory loans, bytes memory settlement) external {
        uint256 loanCount = loans.length;
        uint256 settlementSize = settlement.length;
        bytes memory data = loanWithSettlementEncoder.encode(loans, settlement);
        bytes32 originalHash = loanWithSettlementEncoder.hash(data);

        Loan.Data[] memory newLoans;
        bytes memory newSettlement;
        if (loanCount > 0) {
            (newLoans, newSettlement) = loanWithSettlementEncoder.copy(loans, settlement);
            newLoans[vm.randomUint(0, loanCount - 1)].amount = vm.randomUint(0, type(uint256).max);
            data = loanWithSettlementEncoder.encode(newLoans, newSettlement);
            assertNotEq(loanWithSettlementEncoder.hash(data), originalHash);

            (newLoans, newSettlement) = loanWithSettlementEncoder.copy(loans, settlement);
            newLoans[vm.randomUint(0, loanCount - 1)].borrower = IBorrower(vm.randomAddress());
            data = loanWithSettlementEncoder.encode(newLoans, newSettlement);
            assertNotEq(loanWithSettlementEncoder.hash(data), originalHash);

            (newLoans, newSettlement) = loanWithSettlementEncoder.copy(loans, settlement);
            newLoans[vm.randomUint(0, loanCount - 1)].lender = vm.randomAddress();
            data = loanWithSettlementEncoder.encode(newLoans, newSettlement);
            assertNotEq(loanWithSettlementEncoder.hash(data), originalHash);

            (newLoans, newSettlement) = loanWithSettlementEncoder.copy(loans, settlement);
            newLoans[vm.randomUint(0, loanCount - 1)].token = IERC20(vm.randomAddress());
            data = loanWithSettlementEncoder.encode(newLoans, newSettlement);
            assertNotEq(loanWithSettlementEncoder.hash(data), originalHash);
        }

        if (settlementSize > 0) {
            (newLoans, newSettlement) = loanWithSettlementEncoder.copy(loans, settlement);
            bytes1 randomByte = bytes1(uint8(vm.randomUint(0, type(uint8).max)));
            uint256 randomIndex = vm.randomUint(0, settlementSize - 1);

            if (randomByte == newSettlement[randomIndex]) {
                // We force the random byte to be different.
                unchecked {
                    randomByte = bytes1(uint8(randomByte) + 1);
                }
            }
            newSettlement[randomIndex] = randomByte;
            data = loanWithSettlementEncoder.encode(newLoans, newSettlement);
            assertNotEq(loanWithSettlementEncoder.hash(data), originalHash);
        }
    }

    function testFuzz_popAndHashHasSameHashAsDirectEncoding(
        Loan.Data[] memory loans,
        Loan.Data memory extraLoan,
        bytes memory settlement
    ) external view {
        bytes memory loanWithSettlement = loanWithSettlementEncoder.encode(loans, settlement);

        Loan.Data[] memory extendedLoans = new Loan.Data[](loans.length + 1);
        extendedLoans[0] = extraLoan;
        for (uint256 i = 0; i < loans.length; i++) {
            extendedLoans[i + 1] = loans[i];
        }

        assertEq(
            loanWithSettlementEncoder.encodePopLoanAndHash(extendedLoans, settlement),
            loanWithSettlementEncoder.hash(loanWithSettlement)
        );
    }

    function test_encodedBytestringMatches() external view {
        Loan.Data[] memory loans = new Loan.Data[](2);
        loans[0] = Loan.Data({
            amount: 0x0101010101010101010101010101010101010101010101010101010101010101, // 32 bytes
            borrower: IBorrower(0x0202020202020202020202020202020202020202),
            lender: address(0x0303030303030303030303030303030303030303),
            token: IERC20(address(0x0404040404040404040404040404040404040404))
        });
        loans[1] = Loan.Data({
            amount: 0x1111111111111111111111111111111111111111111111111111111111111111, // 32 bytes
            borrower: IBorrower(0x1212121212121212121212121212121212121212),
            lender: address(0x1313131313131313131313131313131313131313),
            token: IERC20(address(0x1414141414141414141414141414141414141414))
        });
        bytes memory settlement =
            hex"2021222324252627282920212223242526272829202122232425262728292021222324252627282920212223242526272829";

        bytes memory expectedEncodedBytestring = bytes.concat(
            hex"0000000000000000000000000000000000000000000000000000000000000002", // number of loans in 32 bytes
            // settlement
            hex"2021222324252627282920212223242526272829202122232425262728292021222324252627282920212223242526272829",
            // second loan
            hex"1111111111111111111111111111111111111111111111111111111111111111",
            hex"1212121212121212121212121212121212121212",
            hex"1313131313131313131313131313131313131313",
            hex"1414141414141414141414141414141414141414",
            // first loan
            hex"0101010101010101010101010101010101010101010101010101010101010101",
            hex"0202020202020202020202020202020202020202",
            hex"0303030303030303030303030303030303030303",
            hex"0404040404040404040404040404040404040404"
        );

        bytes memory encodedBytestring = loanWithSettlementEncoder.encode(loans, settlement);
        assertEq(encodedBytestring, expectedEncodedBytestring);
    }

    /// This tests populates the struct with arbitrary data and pops all
    /// loans out, checking that they match with the input.
    /// Unlike other tests, we actually want all memory operations to happen
    /// in the context of the test to see any impact that repeated bad memory
    /// encoding may have.
    function testFuzz_popAllInternallyAndCheckSettlement(uint256 loanCount, uint256 settlementSize) external view {
        vm.assume(loanCount < MAX_FUZZ_LOAN_COUNT);
        vm.assume(settlementSize < MAX_FUZZ_SETTLEMENT_SIZE);

        Loan.Data[] memory loans = new Loan.Data[](loanCount);
        for (uint256 i = 0; i < loanCount; i++) {
            loans[i] = someLoan(i);
        }
        bytes memory settlement = Bytes.sequentialByteArrayOfSize(settlementSize);
        // We need to use the encoder and not the library because `encode`
        // expects the data to be stored in `calldata`.
        bytes memory encodedLoansWithSettlement = loanWithSettlementEncoder.encode(loans, settlement);

        assertEq(encodedLoansWithSettlement.loanCount(), loans.length);

        Loan.Data memory poppedLoan;
        for (uint256 i = 0; i < loanCount; i++) {
            // Internal library operation
            (uint256 amount, IBorrower borrower, address lender, IERC20 token) = encodedLoansWithSettlement.popLoan();
            poppedLoan = Loan.Data({amount: amount, borrower: borrower, lender: lender, token: token});
            assertEq(poppedLoan, loans[i], string.concat("at index i=", vm.toString(i)));
            assertEq(
                encodedLoansWithSettlement.loanCount(),
                loans.length - i - 1,
                string.concat("loan count does not match at index i=", vm.toString(i))
            );
        }
        bytes memory extractedSettlement = loanWithSettlementEncoder.extractSettlement(encodedLoansWithSettlement);
        assertEq(extractedSettlement, settlement, "settlement does not match");
    }

    /// This test is identical to `testFuzz_popAllInternallyAndCheckSettlement`,
    /// except that popLoan and extractSettlement operations are performed
    /// externally by calling another contract that uses the memory in another
    /// context to perform all operations. Here, memory is internally
    /// reallocated (transparently by the compiler) after each operation, which
    /// decreases the chance that the test passes only because some
    /// theoretically inaccessible memory location has been accessed and still
    /// happens to store the right content.
    function testFuzz_popAllExternallyAndCheckSettlement(uint256 loanCount, uint256 settlementSize) external view {
        vm.assume(loanCount < MAX_FUZZ_LOAN_COUNT);
        vm.assume(settlementSize < MAX_FUZZ_SETTLEMENT_SIZE);

        Loan.Data[] memory loans = new Loan.Data[](loanCount);
        for (uint256 i = 0; i < loanCount; i++) {
            loans[i] = someLoan(i);
        }
        bytes memory settlement = Bytes.sequentialByteArrayOfSize(settlementSize);
        bytes memory encodedLoansWithSettlement = loanWithSettlementEncoder.encode(loans, settlement);

        assertEq(encodedLoansWithSettlement.loanCount(), loans.length);

        Loan.Data memory poppedLoan;
        for (uint256 i = 0; i < loanCount; i++) {
            // External call
            (encodedLoansWithSettlement, poppedLoan) = loanWithSettlementEncoder.popLoan(encodedLoansWithSettlement);
            assertEq(poppedLoan, loans[i], string.concat("at index i=", vm.toString(i)));
            assertEq(
                encodedLoansWithSettlement.loanCount(),
                loans.length - i - 1,
                string.concat("loan count does not match at index i=", vm.toString(i))
            );
        }
        // External call
        bytes memory extractedSettlement = loanWithSettlementEncoder.extractSettlement(encodedLoansWithSettlement);
        assertEq(extractedSettlement, settlement, "settlement does not match");
    }

    function assertEq(Loan.Data memory lhs, Loan.Data memory rhs, string memory extraString) internal pure {
        if (bytes(extraString).length > 0) {
            extraString = string.concat(", ", extraString);
        }
        assertEq(lhs.amount, rhs.amount, string.concat("amount not matching", extraString));
        assertEq(address(lhs.borrower), address(rhs.borrower), string.concat("solver not matching", extraString));
        assertEq(address(lhs.lender), address(rhs.lender), string.concat("lender not matching", extraString));
        assertEq(address(lhs.token), address(rhs.token), string.concat("token not matching", extraString));
    }

    function assertEq(Loan.Data memory lhs, Loan.Data memory rhs) internal pure {
        assertEq(lhs, rhs, "");
    }
}
