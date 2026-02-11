// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {Test} from "forge-std/Test.sol";

import {ERC3156Borrower, IERC20, IERC3156FlashLender, IFlashLoanRouter} from "src/ERC3156Borrower.sol";

contract ERC3156BorrowerTest is Test {
    IFlashLoanRouter private router;
    ERC3156Borrower private borrower;

    function setUp() external {
        router = IFlashLoanRouter(makeAddr("ERC3156BorrowerTest: router"));
        vm.mockCall(
            address(router),
            abi.encodeCall(IFlashLoanRouter.settlementContract, ()),
            abi.encode(makeAddr("ERC3156BorrowerTest: settlementContract"))
        );
        borrower = new ERC3156Borrower(router);
    }

    function test_constructor_parameters() external view {
        assertEq(address(borrower.router()), address(router));
    }

    function test_flashLoanAndCallBack_callsFlashLoan() external {
        address lender = makeAddr("lender");
        IERC20 token = IERC20(makeAddr("token"));
        uint256 amount = 42;
        bytes memory callBackData = hex"1337";

        bytes memory lenderCallData =
            abi.encodeCall(IERC3156FlashLender.flashLoan, (borrower, address(token), amount, callBackData));
        vm.expectCall(lender, lenderCallData);
        vm.mockCall(lender, lenderCallData, abi.encode(true));
        vm.prank(address(router));
        borrower.flashLoanAndCallBack(lender, token, amount, callBackData);
    }

    function test_flashLoanAndCallBack_revertsIfFlashLoanReturnsFalse() external {
        address lender = makeAddr("lender");
        IERC20 token = IERC20(makeAddr("token"));
        uint256 amount = 42;
        bytes memory callBackData = hex"1337";

        bytes memory lenderCallData =
            abi.encodeCall(IERC3156FlashLender.flashLoan, (borrower, address(token), amount, callBackData));
        vm.mockCall(lender, lenderCallData, abi.encode(false));
        vm.prank(address(router));
        vm.expectRevert("Flash loan was unsuccessful");
        borrower.flashLoanAndCallBack(lender, token, amount, callBackData);
    }

    function test_flashLoanAndCallBack_revertsIfFlashLoanReverts() external {
        address lender = makeAddr("lender");
        IERC20 token = IERC20(makeAddr("token"));
        uint256 amount = 42;
        bytes memory callBackData = hex"1337";

        bytes memory lenderCallData =
            abi.encodeCall(IERC3156FlashLender.flashLoan, (borrower, address(token), amount, callBackData));
        vm.mockCallRevert(lender, lenderCallData, "mock revert");
        vm.prank(address(router));
        vm.expectRevert("mock revert");
        borrower.flashLoanAndCallBack(lender, token, amount, callBackData);
    }

    function test_onFlashLoan_callsRouter() external {
        bytes memory callBackData = hex"1337";
        bytes memory routerCallData = abi.encodeCall(IFlashLoanRouter.borrowerCallBack, (callBackData));
        vm.expectCall(address(router), routerCallData);
        borrower.onFlashLoan(address(0), address(0), 0, 0, callBackData);
    }

    function test_onFlashLoan_returnsErc3156Success() external {
        bytes memory callBackData = hex"1337";
        bytes32 output = borrower.onFlashLoan(address(0), address(0), 0, 0, callBackData);
        assertEq(output, keccak256("ERC3156FlashBorrower.onFlashLoan"));
    }

    function test_onFlashLoan_revertsIfRouterCallReverts() external {
        bytes memory callBackData = hex"1337";
        vm.mockCallRevert(address(router), new bytes(0), "mock revert");
        vm.expectRevert("mock revert");
        borrower.onFlashLoan(address(0), address(0), 0, 0, callBackData);
    }
}
