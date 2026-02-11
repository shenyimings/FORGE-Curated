// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.28;

import {IOperator} from "src/interfaces/IOperator.sol";
import {ImTokenOperationTypes, ImToken} from "src/interfaces/ImToken.sol";

import {LiquidationHelper} from "src/utils/LiquidationHelper.sol";

// tests
import {mToken_Unit_Shared} from "../shared/mToken_Unit_Shared.t.sol";

contract mErc20_liquidateHelper is mToken_Unit_Shared {
    LiquidationHelper helper;

    address borrower = address(0x123);

    function setUp() public virtual override {
        super.setUp();

        helper = new LiquidationHelper();
        vm.label(address(helper), "LiquidationHelper");
    }

    function testBorrowerPosition_SkipsPausedMarket() public {
        vm.mockCall(
            address(operator),
            abi.encodeWithSelector(
                IOperator.isPaused.selector, address(mWeth), ImTokenOperationTypes.OperationType.Liquidate
            ),
            abi.encode(true)
        );

        (bool shouldLiquidate, uint256 repayAmount) = helper.getBorrowerPosition(borrower, address(mWeth));
        assertEq(shouldLiquidate, false);
        assertEq(repayAmount, 0);
    }

    function testBorrowerPosition_SkipsZeroDebt() public {
        vm.mockCall(
            address(mWeth), abi.encodeWithSelector(ImToken.borrowBalanceStored.selector, borrower), abi.encode(0)
        );

        (bool shouldLiquidate, uint256 repayAmount) = helper.getBorrowerPosition(borrower, address(mWeth));
        assertEq(shouldLiquidate, false);
        assertEq(repayAmount, 0);
    }

    function testBorrowerPosition_LiquidatesCorrectly() public {
        uint256 borrowBalance = 1 ether;
        uint256 closeFactor = 50 * 1e16; // 50%
        uint256 shortfall = 1 ether;

        vm.mockCall(
            address(mWeth),
            abi.encodeWithSelector(ImToken.borrowBalanceStored.selector, borrower),
            abi.encode(borrowBalance)
        );
        vm.mockCall(
            address(operator),
            abi.encodeWithSelector(IOperator.getHypotheticalAccountLiquidity.selector, borrower, address(0), 0, 0),
            abi.encode(0, shortfall)
        );
        vm.mockCall(
            address(operator), abi.encodeWithSelector(IOperator.closeFactorMantissa.selector), abi.encode(closeFactor)
        );

        (bool shouldLiquidate, uint256 repayAmount) = helper.getBorrowerPosition(borrower, address(mWeth));
        assertEq(shouldLiquidate, true);
        assertEq(repayAmount, borrowBalance * closeFactor / 1 ether);
    }
}
