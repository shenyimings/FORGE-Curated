// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {IFlashLoanRouter} from "src/interface/IFlashLoanRouter.sol";

import {IERC20, NoOpBorrower} from "./NoOp.sol";

/// @dev A minimal borrower contract that ignores all input value except for the
/// callback data, which is sent back to the router in a callback.
contract SimpleCallBackBorrower is NoOpBorrower {
    constructor(IFlashLoanRouter _router) NoOpBorrower(_router) {}

    function flashLoanAndCallBack(address, IERC20, uint256, bytes calldata callBackData) external override {
        router.borrowerCallBack(callBackData);
    }
}
