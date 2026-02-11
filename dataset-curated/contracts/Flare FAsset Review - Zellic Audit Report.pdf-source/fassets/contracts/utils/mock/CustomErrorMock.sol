// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;


contract CustomErrorMock {
    error ErrorWithoutArgs();
    error ErrorWithArgs(uint256 value, string text);

    function emitErrorWithoutArgs() external {
        revert ErrorWithoutArgs();
    }

    function emitErrorWithArgs(uint256 value, string memory text) external {
        revert ErrorWithArgs(value, text);
    }

    function emitErrorWithString() external {
        // solhint-disable-next-line gas-custom-errors
        revert("string type error");
    }
}
