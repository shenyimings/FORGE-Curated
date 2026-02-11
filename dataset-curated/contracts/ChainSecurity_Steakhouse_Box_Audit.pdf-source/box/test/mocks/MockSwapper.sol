// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ISwapper} from "../../src/interfaces/ISwapper.sol";
import {IOracle} from "../../src/interfaces/IOracle.sol";

contract MockSwapper is ISwapper {
    using SafeERC20 for IERC20;

    mapping(IERC20 => IOracle) public oracles;

    constructor() {}

    function setOracle(IERC20 token, IOracle oracle) external {
        oracles[token] = oracle;
    }

    function sell(IERC20 fromToken, IERC20 toToken, uint256 amount, bytes calldata /* data */) external override {
        // Transfer the fromToken from the caller
        fromToken.safeTransferFrom(msg.sender, address(this), amount);

        // Calculate how much toToken to give back using oracles
        uint256 amountOut;

        if (address(oracles[fromToken]) != address(0) && address(oracles[toToken]) != address(0)) {
            // Both tokens have oracles - use oracle prices
            uint256 fromPrice = oracles[fromToken].price(); // 36 decimals
            uint256 toPrice = oracles[toToken].price(); // 36 decimals

            // amountOut = amount * fromPrice / toPrice
            amountOut = (amount * fromPrice) / toPrice;
        } else {
            // Fallback to 1:1 if no oracles (shouldn't happen in our test)
            amountOut = amount;
        }

        // Mint/transfer the toToken to the caller
        // In a real test, we'd need to deal() tokens to this contract
        // For now, assume we have unlimited balance
        _ensureBalance(toToken, amountOut);
        toToken.safeTransfer(msg.sender, amountOut);
    }

    // Helper to ensure we have enough balance (use vm.deal equivalent for tokens)
    function _ensureBalance(IERC20 token, uint256 amount) internal view {
        uint256 currentBalance = token.balanceOf(address(this));
        if (currentBalance < amount) {
            // In a test environment, we would use vm.deal or similar
            // For now, this is a placeholder - the actual test needs to deal tokens to this contract
            revert("MockSwapper: insufficient balance - need to deal tokens in test");
        }
    }
}
