// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {Vm} from "forge-std/Test.sol";

import {IERC20} from "src/vendored/IERC20.sol";

/// @dev This is a helper contract to get the balance of a contract in the
/// middle of a call without advanced tracing.
contract TokenBalanceAccumulator {
    struct Balance {
        IERC20 token;
        address owner;
        uint256 balance;
    }

    Balance[] public data;

    function push(IERC20 token, address owner) external {
        data.push(Balance(token, owner, token.balanceOf(owner)));
    }

    function assertAccumulatorEq(Vm vm, Balance[] memory values) external view {
        vm.assertEq(
            data.length,
            values.length,
            "Number of stored balances in accumulator does not match that of the provided values"
        );
        for (uint256 i = 0; i < data.length; i++) {
            string memory err = string.concat("Differing record at index ", vm.toString(i), " with field ");
            vm.assertEq(address(data[i].token), address(values[i].token), string.concat(err, "`token`"));
            vm.assertEq(data[i].owner, values[i].owner, string.concat(err, "`owner`"));
            vm.assertEq(data[i].balance, values[i].balance, string.concat(err, "`balance`"));
        }
    }
}
