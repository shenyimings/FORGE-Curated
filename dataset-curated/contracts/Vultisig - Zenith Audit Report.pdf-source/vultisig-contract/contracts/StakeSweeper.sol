// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IUniswapRouter.sol";

/**
 * @title StakeSweeper
 * @dev Contract for sweeping tokens into reward tokens using Uniswap-like routers
 */
contract StakeSweeper is Ownable {
    using SafeERC20 for IERC20;

    // Events
    event RouterSet(address indexed router);
    event MinOutPercentageSet(uint8 percentage);
    event TokenSwept(address indexed token, uint256 amountIn, uint256 amountOut);

    // State variables
    address public defaultRouter;
    uint8 public minOutPercentage = 90; // Default 90% to protect from slippage
    IERC20 public immutable rewardToken;

    constructor(address _rewardToken, address _router) Ownable(msg.sender) {
        require(_rewardToken != address(0), "StakeSweeper: reward token is zero address");
        require(_router != address(0), "StakeSweeper: router is zero address");
        rewardToken = IERC20(_rewardToken);
        defaultRouter = _router;
    }

    /**
     * @dev Sets the router for sweep operations
     * @param _router The address of the Uniswap-like router to use
     */
    function setRouter(address _router) external onlyOwner {
        require(_router != address(0), "StakeSweeper: router is zero address");
        defaultRouter = _router;
        emit RouterSet(_router);
    }

    /**
     * @dev Sets the minimum percentage of output tokens expected (slippage protection)
     * @param _percentage The percentage (1-100)
     */
    function setMinOutPercentage(uint8 _percentage) external onlyOwner {
        require(_percentage > 0 && _percentage <= 100, "StakeSweeper: percentage must be between 1-100");
        minOutPercentage = _percentage;
        emit MinOutPercentageSet(_percentage);
    }

    /**
     */
    function reinvest(address _stakingToken, address _recipient) external returns (uint256) {
        uint256 balance = IERC20(rewardToken).balanceOf(address(this));

        uint256 amountOut = _swapTokens(address(rewardToken), address(_stakingToken), balance, _recipient);

        emit TokenSwept(address(rewardToken), balance, amountOut);
        return amountOut;
    }

    /**
     * @dev Sweeps a token and converts it to reward tokens
     * @param _token Token to sweep
     * @param _recipient Address to receive the reward tokens
     * @return Amount of reward tokens received
     */
    function sweep(address _token, address _recipient) external returns (uint256) {
        require(_token != address(rewardToken), "StakeSweeper: cannot sweep reward token");
        require(_recipient != address(0), "StakeSweeper: recipient is zero address");

        IERC20 token = IERC20(_token);
        uint256 balance = token.balanceOf(address(this));
        require(balance > 0, "StakeSweeper: no tokens to sweep");

        // Execute the swap
        uint256 amountOut = _swapTokens(_token, address(rewardToken), balance, _recipient);

        emit TokenSwept(_token, balance, amountOut);
        return amountOut;
    }

    /**
     * @dev Internal function to swap tokens using Uniswap router
     */
    function _swapTokens(address _tokenIn, address _tokenOut, uint256 _amountIn, address _recipient)
        internal
        returns (uint256)
    {
        require(_amountIn > 0, "StakeSweeper: amount to swap must be greater than 0");

        address[] memory path = new address[](2);
        path[0] = _tokenIn;
        path[1] = _tokenOut;

        IERC20(_tokenIn).safeIncreaseAllowance(defaultRouter, _amountIn);

        // Get quote from router
        uint256[] memory amountsOut;
        uint256 expectedOut = 0;

        try IUniswapRouter(defaultRouter).getAmountsOut(_amountIn, path) returns (uint256[] memory output) {
            amountsOut = output;
            if (amountsOut.length > 1) {
                expectedOut = amountsOut[amountsOut.length - 1];
            }
        } catch {}

        uint256 amountOutMin = expectedOut > 0 ? (expectedOut * minOutPercentage) / 100 : 1;

        // Execute swap
        uint256[] memory amounts = IUniswapRouter(defaultRouter).swapExactTokensForTokens(
            _amountIn, amountOutMin, path, _recipient, block.timestamp + 1 hours
        );

        IERC20(_tokenIn).safeIncreaseAllowance(defaultRouter, 0);
        return amounts[amounts.length - 1];
    }
}
