// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract MockERC20 is ERC20Mock {
    uint8 private _decimals;

    constructor() {
        _decimals = 18;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mockSetDecimals(uint8 decimalAmount) external {
        _decimals = decimalAmount;
    }
}
