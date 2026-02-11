// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {Test} from "forge-std/Test.sol";

import {AaveBorrower, IAavePool, IERC20, IFlashLoanRouter} from "src/AaveBorrower.sol";

contract AaveBorrowerTest is Test {
    IFlashLoanRouter private router;
    AaveBorrower private borrower;

    function setUp() external {
        router = IFlashLoanRouter(makeAddr("AaveBorrowerTest: router"));
        vm.mockCall(
            address(router),
            abi.encodeCall(IFlashLoanRouter.settlementContract, ()),
            abi.encode(makeAddr("AaveBorrowerTest: settlementContract"))
        );
        borrower = new AaveBorrower(router);
    }

    function test_constructor_parameters() external view {
        assertEq(address(borrower.router()), address(router));
    }

    function test_flashLoanAndCallBack_callsFlashLoan() external {
        address lender = makeAddr("lender");
        IERC20 token = IERC20(makeAddr("token"));
        uint256 amount = 42;
        bytes memory callBackData = hex"1337";

        bytes memory lenderCallData = lenderCallDataWithDefaultParams(borrower, token, amount, callBackData);
        vm.expectCall(lender, lenderCallData);
        vm.mockCall(lender, lenderCallData, abi.encode(true));
        vm.prank(address(router));
        borrower.flashLoanAndCallBack(lender, token, amount, callBackData);
    }

    function test_flashLoanAndCallBack_revertsIfFlashLoanReverts() external {
        address lender = makeAddr("lender");
        IERC20 token = IERC20(makeAddr("token"));
        uint256 amount = 42;
        bytes memory callBackData = hex"1337";

        bytes memory lenderCallData = lenderCallDataWithDefaultParams(borrower, token, amount, callBackData);
        vm.mockCallRevert(lender, lenderCallData, "mock revert");
        vm.prank(address(router));
        vm.expectRevert("mock revert");
        borrower.flashLoanAndCallBack(lender, token, amount, callBackData);
    }

    function test_onFlashLoan_callsRouter() external {
        bytes memory callBackData = hex"1337";
        bytes memory routerCallData = abi.encodeCall(IFlashLoanRouter.borrowerCallBack, (callBackData));
        vm.expectCall(address(router), routerCallData);
        borrower.executeOperation(new address[](0), new uint256[](0), new uint256[](0), address(0), callBackData);
    }

    function test_onFlashLoan_returnsTrue() external {
        bytes memory callBackData = hex"1337";
        bool output =
            borrower.executeOperation(new address[](0), new uint256[](0), new uint256[](0), address(0), callBackData);
        assertTrue(output);
    }

    function test_onFlashLoan_revertsIfRouterCallReverts() external {
        bytes memory callBackData = hex"1337";
        vm.mockCallRevert(address(router), new bytes(0), "mock revert");
        vm.expectRevert("mock revert");
        borrower.executeOperation(new address[](0), new uint256[](0), new uint256[](0), address(0), callBackData);
    }

    function lenderCallDataWithDefaultParams(
        AaveBorrower _borrower,
        IERC20 token,
        uint256 amount,
        bytes memory callBackData
    ) private pure returns (bytes memory) {
        address receiverAddress = address(_borrower);
        address[] memory assets = new address[](1);
        assets[0] = address(token);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        uint256[] memory interestRateModes = new uint256[](1);
        interestRateModes[0] = 0;
        address onBehalfOf = address(_borrower);
        bytes memory params = callBackData;
        uint16 referralCode = 0;

        return abi.encodeCall(
            IAavePool.flashLoan, (receiverAddress, assets, amounts, interestRateModes, onBehalfOf, params, referralCode)
        );
    }
}
