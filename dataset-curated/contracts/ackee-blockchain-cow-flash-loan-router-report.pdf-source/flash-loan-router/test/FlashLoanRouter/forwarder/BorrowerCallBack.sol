// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {BaseForwarder} from "./Base.sol";

/// @dev Every time this contract is called, it calls the `borrowerCallBack`
/// function of the router with empty data.
contract BorrowerCallBackForwarder is BaseForwarder {
    fallback() external {
        try router.borrowerCallBack(hex"") {
            revert("The call was expected to revert");
        } catch (bytes memory err) {
            emitRevertReason(err);
        }
    }
}
