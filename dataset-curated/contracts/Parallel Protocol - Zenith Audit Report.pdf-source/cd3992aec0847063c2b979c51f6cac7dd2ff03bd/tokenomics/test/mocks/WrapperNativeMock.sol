// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { IWrappedNative } from "contracts/interfaces/IWrappedNative.sol";
import { ERC20Mock } from "./ERC20Mock.sol";

contract WrappedNativeMock is IWrappedNative, ERC20Mock {
    constructor(string memory name, string memory symbol, uint8 decimals) ERC20Mock(name, symbol, decimals) { }

    function deposit() external payable override {
        _mint(msg.sender, msg.value);
    }

    function withdraw(uint256 amount) external override {
        _burn(msg.sender, amount);
        payable(msg.sender).transfer(amount);
    }
}
