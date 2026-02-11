// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title MockUniswapRouter
 * @dev A mock router that simulates Uniswap's swapping functionality for testing
 */
contract MockUniswapRouter {
    using SafeERC20 for IERC20;

    // Maps from token to token with numerator/denominator to represent exchange rates
    mapping(address => mapping(address => uint256)) public rateNumerator;
    mapping(address => mapping(address => uint256)) public rateDenominator;

    /**
     * @dev Set the exchange rate between two tokens
     * @param _tokenIn The input token
     * @param _tokenOut The output token
     * @param _numerator The numerator of the exchange rate
     * @param _denominator The denominator of the exchange rate
     */
    function setExchangeRate(address _tokenIn, address _tokenOut, uint256 _numerator, uint256 _denominator) external {
        require(_denominator > 0, "MockUniswapRouter: denominator cannot be zero");
        rateNumerator[_tokenIn][_tokenOut] = _numerator;
        rateDenominator[_tokenIn][_tokenOut] = _denominator;
    }

    /**
     * @dev Simulates swapping tokens
     * @param amountIn The amount of input tokens
     * @param amountOutMin The minimum amount of output tokens required
     * @param path The swap path (only uses first and last elements)
     * @param to The recipient of the swapped tokens
     * @param deadline The deadline for the swap
     * @return amounts The input and output amounts
     */
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts) {
        require(path.length >= 2, "MockUniswapRouter: invalid path");
        require(block.timestamp <= deadline, "MockUniswapRouter: deadline expired");

        address tokenIn = path[0];
        address tokenOut = path[path.length - 1];

        // Check if we have an exchange rate set
        uint256 numerator = rateNumerator[tokenIn][tokenOut];
        uint256 denominator = rateDenominator[tokenIn][tokenOut];
        require(numerator > 0 && denominator > 0, "MockUniswapRouter: exchange rate not set");

        // Calculate output amount based on the set rate
        uint256 amountOut = (amountIn * numerator) / denominator;
        require(amountOut >= amountOutMin, "MockUniswapRouter: insufficient output amount");

        // Transfer tokens
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20(tokenOut).safeTransfer(to, amountOut);

        // Return the input and output amounts
        amounts = new uint256[](2);
        amounts[0] = amountIn;
        amounts[1] = amountOut;

        return amounts;
    }
}
