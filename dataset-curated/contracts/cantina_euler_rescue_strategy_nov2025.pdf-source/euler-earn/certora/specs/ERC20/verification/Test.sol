// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v5.0.0) (token/ERC20/IERC20.sol)

pragma solidity ^0.8.0;

import { IERC20 } from "./IERC20.sol";

library Math {
    enum Rounding {
        Floor, // Toward negative infinity
        Ceil, // Toward positive infinity
        Trunc, // Toward zero
        Expand // Away from zero
    }
}

contract Test {

    function supplyByToken(address token) external view returns (uint256) {
        return IERC20(token).totalSupply();
    }

    function balanceByToken(address token, address account) external view returns (uint256) {
        return IERC20(token).balanceOf(account);
    }

    function transferByToken(address token, address recipient, uint256 amount) external returns (bool) {
        return IERC20(token).transfer(recipient, amount);
    }

    function transferFromByToken(address token, address from, address recipient, uint256 amount) external returns (bool) {
        return IERC20(token).transferFrom(from, recipient, amount);
    }

    function approveByToken(address token, address spender, uint256 value) external returns (bool) {
        return IERC20(token).approve(spender, value);
    }
}