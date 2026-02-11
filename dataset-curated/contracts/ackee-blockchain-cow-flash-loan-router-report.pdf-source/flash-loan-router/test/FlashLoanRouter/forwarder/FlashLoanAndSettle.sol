// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {Loan} from "src/library/Loan.sol";

import {BaseForwarder} from "./Base.sol";

/// @dev Every time this contract is called, it calls the `flashLoanAndSettle`
/// function of the router with fixed parameters.
contract FlashLoanAndSettleForwarder is BaseForwarder {
    fallback() external {
        try router.flashLoanAndSettle(new Loan.Data[](0), new bytes(0)) {
            revert("The call was expected to revert");
        } catch (bytes memory err) {
            emitRevertReason(err);
        }
    }
}
