// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {Test} from "forge-std/Test.sol";

import {
    FlashLoanRouter,
    IBorrower,
    ICowSettlement,
    IERC20,
    IFlashLoanRouter,
    Loan,
    LoansWithSettlement
} from "src/FlashLoanRouter.sol";

import {ArbitraryCallBackBorrower} from "./FlashLoanRouter/borrower/ArbitraryCallBack.sol";
import {ForwardCallBackBorrower} from "./FlashLoanRouter/borrower/ForwardCallBack.sol";
import {NoOpBorrower} from "./FlashLoanRouter/borrower/NoOp.sol";
import {SimpleCallBackBorrower} from "./FlashLoanRouter/borrower/SimpleCallBack.sol";
import {BaseForwarder} from "./FlashLoanRouter/forwarder/Base.sol";
import {BorrowerCallBackForwarder} from "./FlashLoanRouter/forwarder/BorrowerCallBack.sol";
import {FlashLoanAndSettleForwarder} from "./FlashLoanRouter/forwarder/FlashLoanAndSettle.sol";
import {Bytes} from "test/test-lib/Bytes.sol";
import {CowProtocolMock} from "test/test-lib/CowProtocolMock.sol";

/// @dev This contract extends FlashLoanRouter with some testing functions to
/// help read and manipulate the internal state of the contract.
contract FlashLoanRouterExposed is FlashLoanRouter {
    constructor(ICowSettlement _settlementContract) FlashLoanRouter(_settlementContract) {}

    function selectorExposed(bytes memory callData) external pure returns (bytes4) {
        return selector(callData);
    }

    function setPendingBorrower(IBorrower borrower) external {
        pendingBorrower = borrower;
    }

    function encodeLoansWithSettlement(Loan.Data[] calldata loans, bytes calldata settlement)
        external
        pure
        returns (bytes memory)
    {
        return LoansWithSettlement.encode(loans, settlement);
    }
}

/// @dev We use a separate contract to call functions in `FlashLoanRouter` for
/// two reasons:
/// 1. We need to call library functions that expect `calldata` input location.
/// 2. we expect all calls to happen in the same transaction. This is because
///    the base contract relies on transient storage, and we run tests with the
///    Foundry config `isolate = true` so that any top-level call is an actual
///    transaction and transient storage gets reset at the end.
contract FlashLoanRouterCaller {
    function flashLoanAndSettle(IFlashLoanRouter router, Loan.Data[] calldata loans, bytes calldata settlement)
        external
    {
        router.flashLoanAndSettle(loans, settlement);
    }
}

contract FlashLoanRouterTest is Test {
    using LoansWithSettlement for bytes;

    FlashLoanRouterExposed private router;
    FlashLoanRouterCaller private caller;
    CowProtocolMock private cowProtocolMock;

    function setUp() external {
        caller = new FlashLoanRouterCaller();
        cowProtocolMock = new CowProtocolMock(vm, makeAddr("mock settlement"), makeAddr("mock authenticator"));
        router = new FlashLoanRouterExposed(cowProtocolMock.SETTLEMENT());
        cowProtocolMock.mockIsSolver(address(caller), true);
    }

    function test_constructor_parameters() external view {
        assertEq(address(router.settlementContract()), address(cowProtocolMock.SETTLEMENT()));
        assertEq(address(router.settlementAuthentication()), address(cowProtocolMock.AUTHENTICATOR()));
    }

    function test_flashLoanAndSettle_revertsIfNotCalledBySolver() external {
        cowProtocolMock.mockIsSolver(address(caller), false);
        vm.expectRevert("Not a solver");
        caller.flashLoanAndSettle(router, new Loan.Data[](0), new bytes(0));
    }

    function test_flashLoanAndSettle_revertsIfNotCallingSettle() external {
        vm.expectRevert("Only settle() is allowed");
        caller.flashLoanAndSettle(router, new Loan.Data[](0), abi.encodeCall(ICowSettlement.authenticator, ()));
    }

    function test_flashLoanAndSettle_callsSettleIfNoLoansProvided() external {
        bytes memory settlement = abi.encodePacked(ICowSettlement.settle.selector);
        vm.expectCall(address(cowProtocolMock.SETTLEMENT()), settlement);
        caller.flashLoanAndSettle(router, new Loan.Data[](0), settlement);
    }

    function test_flashLoanAndSettle_revertsIfSettlementReverts() external {
        bytes memory settlement = abi.encodePacked(ICowSettlement.settle.selector);
        vm.mockCallRevert(address(cowProtocolMock.SETTLEMENT()), settlement, "test mock revert");
        vm.expectRevert("Settlement reverted");
        caller.flashLoanAndSettle(router, new Loan.Data[](0), settlement);
    }

    function testFuzz_flashLoanAndSettle_revertsIfBorrowerCallReverts(Loan.Data[] memory loans) external {
        vm.assume(loans.length > 0);
        bytes memory settlement = new bytes(0);
        vm.mockCallRevert(address(loans[0].borrower), new bytes(0), "test mock revert");
        vm.expectRevert("test mock revert");
        caller.flashLoanAndSettle(router, loans, settlement);
    }

    function test_flashLoanAndSettle_revertsIfBorrowerDoesNotCallBack() external {
        bytes memory settlement = new bytes(0);
        Loan.Data[] memory loans = new Loan.Data[](1);
        loans[0] = loanWithIndex(0);
        loans[0].borrower = new NoOpBorrower(router);
        vm.expectRevert("Terminated without settling");
        caller.flashLoanAndSettle(router, loans, settlement);
    }

    function test_flashLoanAndSettle_revertsIfBorrowerCallsBackWithInvalidData() external {
        bytes memory settlement = new bytes(0);
        Loan.Data[] memory loans = new Loan.Data[](1);
        loans[0] = loanWithIndex(0);
        ArbitraryCallBackBorrower borrower = new ArbitraryCallBackBorrower(router);
        loans[0].borrower = borrower;

        borrower.setCallBack(abi.encode(router.encodeLoansWithSettlement(new Loan.Data[](0), hex"1337")));
        vm.expectRevert("Data from borrower not matching");
        caller.flashLoanAndSettle(router, loans, settlement);
    }

    /// @param forwarder A contract that, when called, in turn calls a specific
    /// function (based on the implementation used) on the router contract.
    function flashLoanAndSettle_revertsIfReentrancyDuringSettlement(
        BaseForwarder forwarder,
        string memory expectedError
    ) private {
        bytes memory settlement = abi.encode(ICowSettlement.settle.selector);
        Loan.Data[] memory loans = new Loan.Data[](0);
        // For simplicity, change the code of the settlement contract so that it
        // always tries to forward the call to the function specified in the
        // forwarder.
        vm.etch(address(cowProtocolMock.SETTLEMENT()), address(forwarder).code);
        BaseForwarder(address(cowProtocolMock.SETTLEMENT())).setRouter(router);
        vm.expectEmit(true, true, true, true, address(cowProtocolMock.SETTLEMENT()));
        emit BaseForwarder.RevertReason(expectedError);
        caller.flashLoanAndSettle(router, loans, settlement);
    }

    function test_flashLoanAndSettle_revertsIfBorrowerCallBackIsCalledDuringSettlement() external {
        flashLoanAndSettle_revertsIfReentrancyDuringSettlement(
            new BorrowerCallBackForwarder(), "Not the pending borrower"
        );
    }

    function test_flashLoanAndSettle_revertsIfFlashLoanAndSettleIsCalledDuringSettlement() external {
        cowProtocolMock.mockIsSolver(address(cowProtocolMock.SETTLEMENT()), true);
        FlashLoanAndSettleForwarder forwarder = new FlashLoanAndSettleForwarder();
        flashLoanAndSettle_revertsIfReentrancyDuringSettlement(forwarder, "Another settlement in progress");
    }

    /// @param forwarder A contract that, when called, in turn calls a specific
    /// function (based on the implementation used) on the router contract.
    function flashLoanAndSettle_revertsIfReentrancyDuringFlashLoanAndCallBack(
        BaseForwarder forwarder,
        string memory expectedError
    ) private {
        bytes memory settlement = abi.encode(ICowSettlement.settle.selector);
        Loan.Data[] memory loans = new Loan.Data[](1);
        loans[0] = loanWithIndex(0);
        loans[0].borrower = new ForwardCallBackBorrower(router, forwarder);

        vm.expectEmit(true, true, true, true, address(forwarder));
        emit BaseForwarder.RevertReason(expectedError);
        // The call is expected to revert regardless. The actual error message
        // isn't relevant for this test.
        vm.expectRevert();
        caller.flashLoanAndSettle(router, loans, settlement);
    }

    function test_flashLoanAndSettle_revertsIfBorrowerCallBackIsCalledDuringFlashLoanAndCallBack() external {
        flashLoanAndSettle_revertsIfReentrancyDuringFlashLoanAndCallBack(
            new BorrowerCallBackForwarder(), "Not the pending borrower"
        );
    }

    function test_flashLoanAndSettle_revertsIfFlashLoanAndSettleIsCalledDuringFlashLoanAndCallBack() external {
        FlashLoanAndSettleForwarder forwarder = new FlashLoanAndSettleForwarder();
        cowProtocolMock.mockIsSolver(address(forwarder), true);
        flashLoanAndSettle_revertsIfReentrancyDuringFlashLoanAndCallBack(forwarder, "Another settlement in progress");
    }

    function testFuzz_flashLoanAndSettle_callsBorrowersWithPoppedLoan(uint256 loanCount, bytes calldata settlementTail)
        external
    {
        // We limit the amount of loans to avoid out-of-memory reverts.
        // Hint: reduce to 2 for simpler debugging.
        vm.assume(loanCount < 100);

        ICowSettlement settlementContract = cowProtocolMock.SETTLEMENT();
        bytes memory settlement = abi.encodePacked(ICowSettlement.settle.selector, settlementTail);

        Loan.Data[] memory loans = new Loan.Data[](loanCount);
        // Populate loans and set expectations for each.
        for (uint256 i = 0; i < loanCount; i++) {
            loans[i] = loanWithIndex(i);
            // The borrower needs to call back the router for the transaction to
            // work. We use a simple contract that does just that.
            loans[i].borrower = new SimpleCallBackBorrower(router);
            // The call data is for the pseudo-expression:
            // abi.encodeCall(flashLoanAndCallBack, (lender, token, amount, ???))
            // where the question marks (the forwarded data) isn't tested and so
            // the call is only partially matched.
            bytes memory callData = abi.encodePacked(
                IBorrower.flashLoanAndCallBack.selector, abi.encode(loans[i].lender, loans[i].token, loans[i].amount)
            );
            vm.expectCall(address(loans[i].borrower), callData);
        }

        vm.expectCall(address(settlementContract), settlement);
        caller.flashLoanAndSettle(router, loans, settlement);
    }

    function test_selector() external view {
        assertEq(router.selectorExposed(hex"42424242"), hex"42424242");
        assertEq(router.selectorExposed(hex"424242"), hex"00000000", "3-byte arrays should return zero");
        assertEq(router.selectorExposed(hex"4242"), hex"00000000", "2-byte arrays should return zero");
        assertEq(router.selectorExposed(hex"42"), hex"00000000", "1-byte arrays should return zero");
        assertEq(router.selectorExposed(hex""), hex"00000000", "0-byte arrays should return zero");
        assertEq(router.selectorExposed(hex"3133333333333333333333333333333337"), hex"31333333", "Should truncate data");
        bytes memory manyBytes = Bytes.sequentialByteArrayOfSize(1337);
        manyBytes[0] = hex"11";
        manyBytes[1] = hex"22";
        manyBytes[2] = hex"33";
        manyBytes[3] = hex"44";
        assertEq(router.selectorExposed(manyBytes), hex"11223344", "Should work for large array");
        assertEq(
            router.selectorExposed(
                abi.encodeCall(
                    ICowSettlement.settle,
                    (
                        new address[](0),
                        new uint256[](0),
                        new ICowSettlement.Trade[](0),
                        [
                            new ICowSettlement.Interaction[](0),
                            new ICowSettlement.Interaction[](0),
                            new ICowSettlement.Interaction[](0)
                        ]
                    )
                )
            ),
            ICowSettlement.settle.selector,
            "Should decode settle() selector"
        );
    }

    function loanWithIndex(uint256 i) private returns (Loan.Data memory) {
        return Loan.Data({
            amount: i,
            borrower: IBorrower(makeAddr(string.concat("borrower at index ", vm.toString(i)))),
            lender: makeAddr(string.concat("lender at index ", vm.toString(i))),
            token: IERC20(makeAddr(string.concat("token address at index ", vm.toString(i))))
        });
    }
}
