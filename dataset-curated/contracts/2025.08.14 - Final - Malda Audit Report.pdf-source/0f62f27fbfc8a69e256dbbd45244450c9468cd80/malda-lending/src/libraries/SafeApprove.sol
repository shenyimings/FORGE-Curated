

// SPDX-License-Identifier: BSL-1.1
pragma solidity =0.8.28;

/*
 _____ _____ __    ____  _____ 
|     |  _  |  |  |    \|  _  |
| | | |     |  |__|  |  |     |
|_|_|_|__|__|_____|____/|__|__|                            
*/

interface IToken {
    function approve(address spender, uint256 amount) external returns (bool);
}

library SafeApprove {
    error SafeApprove_NoContract();
    error SafeApprove_Failed();

    function safeApprove(address token, address to, uint256 value) internal {
        require(token.code.length > 0, SafeApprove_NoContract());

        bool success;
        bytes memory data;
        (success, data) = token.call(abi.encodeCall(IToken.approve, (to, 0)));
        require(success && (data.length == 0 || abi.decode(data, (bool))), SafeApprove_Failed());

        if (value > 0) {
            (success, data) = token.call(abi.encodeCall(IToken.approve, (to, value)));
            require(success && (data.length == 0 || abi.decode(data, (bool))), SafeApprove_Failed());
        }
    }
}
