// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {IFlashLoanRouter} from "src/interface/IFlashLoanRouter.sol";

import {BaseForwarder} from "../forwarder/Base.sol";
import {IERC20, NoOpBorrower} from "./NoOp.sol";

/// @dev A borrower contract that calls a forwarder contract, that is, a
/// specialized in only calling a single function. It's used to test reentrancy
/// guards.
contract ForwardCallBackBorrower is NoOpBorrower {
    BaseForwarder public forwarder;

    constructor(IFlashLoanRouter _router, BaseForwarder _forwarder) NoOpBorrower(_router) {
        forwarder = _forwarder;
        forwarder.setRouter(_router);
    }

    function flashLoanAndCallBack(address, IERC20, uint256, bytes calldata) external override {
        (bool success, bytes memory data) = address(forwarder).call(hex"");
        // Forward error message
        if (success == false) {
            assembly ("memory-safe") {
                revert(add(data, 32), mload(data))
            }
        }
    }
}
