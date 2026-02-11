// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

contract MsgValueModule {
    error IncorrectMsgValue();

    function _checkMsgValue(uint256 inputAmount, bool isNative) internal {
        if (
            // Input is native token but user sent incorrect amount
            (isNative && inputAmount != msg.value)
            // Input is ERC20 but user sent native token as well
            || (!isNative && msg.value > 0)
        ) {
            revert IncorrectMsgValue();
        }
    }
}
