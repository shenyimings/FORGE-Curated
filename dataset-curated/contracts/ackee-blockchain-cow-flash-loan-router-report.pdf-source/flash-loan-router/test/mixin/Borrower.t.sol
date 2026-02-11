// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {Test} from "forge-std/Test.sol";

import {Borrower, ICowSettlement, IERC20, IFlashLoanRouter, SafeERC20} from "src/mixin/Borrower.sol";

contract BorrowerImplementation is Borrower {
    event FlashLoanTriggered(address, IERC20, uint256, bytes);

    constructor(IFlashLoanRouter _router) Borrower(_router) {}

    function triggerFlashLoan(address lender, IERC20 token, uint256 amount, bytes calldata callBackData)
        internal
        override
    {
        emit FlashLoanTriggered(lender, token, amount, callBackData);
    }

    function flashLoanCallBackExposed(bytes calldata callBackData) external {
        flashLoanCallBack(callBackData);
    }
}

contract BorrowerTest is Test {
    IFlashLoanRouter private router;
    ICowSettlement private settlementContract;
    BorrowerImplementation private borrower;

    function setUp() external {
        router = IFlashLoanRouter(makeAddr("BorrowerTest: router"));
        settlementContract = ICowSettlement(makeAddr("BorrowerTest: settlementContract"));
        vm.mockCall(
            address(router), abi.encodeCall(IFlashLoanRouter.settlementContract, ()), abi.encode(settlementContract)
        );
        borrower = new BorrowerImplementation(router);
    }

    function test_constructor_parameters() external view {
        assertEq(address(borrower.router()), address(router));
        assertEq(address(borrower.settlementContract()), address(settlementContract));
    }

    function test_flashLoanAndCallBack_revertsIfNotCalledByRouter() external {
        vm.prank(address(makeAddr("not the router")));
        vm.expectRevert("Not the router");
        borrower.flashLoanAndCallBack(makeAddr("lender"), IERC20(makeAddr("token")), 42, hex"313337");
    }

    function test_flashLoanAndCallBack_triggersFlashLoan() external {
        address lender = makeAddr("lender");
        IERC20 token = IERC20(makeAddr("token"));
        uint256 amount = 42;
        bytes memory callBackData = hex"313337";
        vm.expectEmit(address(borrower));
        emit BorrowerImplementation.FlashLoanTriggered(lender, token, amount, callBackData);
        vm.prank(address(router));
        borrower.flashLoanAndCallBack(lender, token, amount, callBackData);
    }

    function test_approve_revertsIfNotCalledBySettlementContract() external {
        vm.prank(makeAddr("not the settlement contract"));
        vm.expectRevert("Only callable in a settlement");
        borrower.approve(IERC20(makeAddr("token")), makeAddr("target"), 42);
    }

    function test_approve_callsApproveOnToken() external {
        IERC20 token = IERC20(makeAddr("token"));
        address target = makeAddr("target");
        uint256 amount = 42;

        bytes memory approveCallData = abi.encodeCall(IERC20.approve, (target, amount));
        vm.expectCall(address(token), approveCallData);
        vm.mockCall(address(token), approveCallData, abi.encode(true));
        vm.prank(address(settlementContract));
        borrower.approve(token, target, amount);
    }

    function test_approve_supportsNoReturnValue() external {
        IERC20 token = IERC20(makeAddr("token"));
        address target = makeAddr("target");
        uint256 amount = 42;

        bytes memory approveCallData = abi.encodeCall(IERC20.approve, (target, amount));
        vm.mockCall(address(token), approveCallData, hex"");
        vm.prank(address(settlementContract));
        borrower.approve(token, target, amount);
    }

    function test_approve_revertsIfApprovalReverts() external {
        IERC20 token = IERC20(makeAddr("token"));
        address target = makeAddr("target");
        uint256 amount = 42;

        bytes memory approveCallData = abi.encodeCall(IERC20.approve, (target, amount));
        vm.mockCallRevert(address(token), approveCallData, "mock revert");
        vm.prank(address(settlementContract));
        vm.expectRevert("mock revert");
        borrower.approve(token, target, amount);
    }

    function test_approve_revertsIfApprovalReturnsFalse() external {
        IERC20 token = IERC20(makeAddr("token"));
        address target = makeAddr("target");
        uint256 amount = 42;

        bytes memory approveCallData = abi.encodeCall(IERC20.approve, (target, amount));
        vm.mockCall(address(token), approveCallData, abi.encode(false));
        vm.prank(address(settlementContract));
        vm.expectRevert(abi.encodeWithSelector(SafeERC20.SafeERC20FailedOperation.selector, (token)));
        borrower.approve(token, target, amount);
    }

    function test_flashLoanCallBack_callsRouterForwardingData() external {
        bytes memory callBackData = hex"1337";
        vm.expectCall(address(router), abi.encodeCall(IFlashLoanRouter.borrowerCallBack, (callBackData)));
        borrower.flashLoanCallBackExposed(callBackData);
    }

    function test_flashLoanCallBack_revertsIfRouterCallReverts() external {
        bytes memory callBackData = hex"1337";
        vm.mockCallRevert(
            address(router), abi.encodeCall(IFlashLoanRouter.borrowerCallBack, (callBackData)), "mock revert"
        );
        vm.expectRevert("mock revert");
        borrower.flashLoanCallBackExposed(callBackData);
    }
}
