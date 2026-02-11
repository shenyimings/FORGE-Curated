// SPDX-License-Identifier: SHIFT-1.0
pragma solidity ^0.8.0;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {USDKG} from "../USDKG.sol";

contract IntegrationTest {
    using SafeERC20 for USDKG;

    USDKG public token;

    constructor (address _token) {
        token = USDKG(_token);
    }

    function safeTransfer_test(address to, uint256 value) external {
        token.safeTransfer(to, value);
    }

    function safeTransferFrom_test(address from, address to, uint256 value) external {
        token.safeTransferFrom(from, to, value);
    }

    function safeIncreaseAllowance_test(address spender, uint256 value) external {
        token.safeIncreaseAllowance(spender, value);
    }

    function safeDecreaseAllowance_test(address spender, uint256 value) external {
        token.safeDecreaseAllowance(spender, value);
    }

    function forceApprove_test(address spender, uint256 value) external {
        token.forceApprove(spender, value);
    }
}