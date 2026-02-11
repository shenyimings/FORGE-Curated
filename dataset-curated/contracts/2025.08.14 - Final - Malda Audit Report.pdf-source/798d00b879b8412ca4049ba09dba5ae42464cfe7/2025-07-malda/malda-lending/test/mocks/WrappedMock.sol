// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.28;

import {ERC20Mock} from "./ERC20Mock.sol";

contract WrappedMock {
    address public underlying;

    constructor(address _token) {
        underlying = _token;
    }

    function deposit() external payable {
        ERC20Mock(underlying).mint(msg.sender, msg.value);
    }
}
