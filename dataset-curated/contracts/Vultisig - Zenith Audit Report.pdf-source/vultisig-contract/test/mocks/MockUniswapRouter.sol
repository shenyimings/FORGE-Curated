// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../contracts/interfaces/IUniswapRouter.sol";

/**
 * @title MockUniswapRouter
 * @dev A simple mock implementation of Uniswap Router for testing
 */
contract MockUniswapRouter is IUniswapRouter {
    using SafeERC20 for IERC20;

    // Mock exchange rate: 1 input token = exchangeRate output tokens
    uint256 public exchangeRate = 2; // Default 2x for testing
    bool public failQuote;
    bool public invalidQuoteLength;

    function setExchangeRate(uint256 _rate) external {
        require(_rate > 0, "Exchange rate must be positive");
        exchangeRate = _rate;
    }

    function setFailQuote(bool _fail) external {
        failQuote = _fail;
    }

    function setInvalidQuoteLength(bool _invalid) external {
        invalidQuoteLength = _invalid;
    }

    /**
     * @dev Mock implementation of swapExactTokensForTokens
     * Simply transfers input tokens from sender to this contract and
     * transfers output tokens from this contract to recipient
     */
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external override returns (uint256[] memory amounts) {
        require(deadline >= block.timestamp, "Transaction expired");
        require(path.length >= 2, "Invalid path");

        IERC20 inputToken = IERC20(path[0]);
        IERC20 outputToken = IERC20(path[path.length - 1]);

        // Calculate output amount based on exchange rate
        uint256 amountOut = amountIn * exchangeRate;
        require(amountOut >= amountOutMin, "Insufficient output amount");

        // Transfer input tokens from sender to this contract
        inputToken.safeTransferFrom(msg.sender, address(this), amountIn);

        // Transfer output tokens to recipient
        outputToken.safeTransfer(to, amountOut);

        // Return amounts array
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        amounts[path.length - 1] = amountOut;

        return amounts;
    }

    /**
     * @dev Mock implementation of getAmountsOut
     * @param amountIn The amount of input tokens
     * @param path Array of token addresses representing the path
     * @return amounts The input amount and calculated output amounts based on exchange rate
     */
    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external
        view
        override
        returns (uint256[] memory amounts)
    {
        require(path.length >= 2, "Invalid path");

        // Calculate output amount based on exchange rate
        uint256 amountOut = amountIn * exchangeRate;

        // Create and populate the amounts array
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        amounts[path.length - 1] = amountOut;

        return amounts;
    }
}
