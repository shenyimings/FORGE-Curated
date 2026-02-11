// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {IBorrower, IERC20} from "src/interface/IBorrower.sol";
import {ICowSettlement, IFlashLoanRouter} from "src/interface/IFlashLoanRouter.sol";

/// @dev A minimal borrower contract that does nothing on all calls.
contract NoOpBorrower is IBorrower {
    IFlashLoanRouter public router;

    constructor(IFlashLoanRouter _router) {
        router = _router;
    }

    function flashLoanAndCallBack(address, IERC20, uint256, bytes calldata) external virtual {}

    function approve(IERC20, address, uint256) external virtual {}

    function settlementContract() external view virtual returns (ICowSettlement) {}
}
