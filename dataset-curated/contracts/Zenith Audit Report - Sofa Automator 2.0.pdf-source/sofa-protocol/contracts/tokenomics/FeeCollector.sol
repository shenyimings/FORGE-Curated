// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "../interfaces/IUniswapV2Router.sol";
import "../interfaces/IERC20Burnable.sol";

contract FeeCollector is Ownable {
    using SafeERC20 for IERC20;

    address immutable public rch;
    address immutable public routerV2;
    address immutable public routerV3;
    uint256 public tradingFeeRate;
    uint256 public settlementFeeRate;

    constructor(
        address rch_,
        uint256 tradingFeeRate_,
        uint256 settlementFeeRate_,
        address routerV2_,
        address routerV3_
    ) {
        rch = rch_;
        tradingFeeRate = tradingFeeRate_;
        settlementFeeRate = settlementFeeRate_;
        routerV2 = routerV2_;
        routerV3 = routerV3_;
    }

    function approve(IERC20 token, address router) external {
        require(router == routerV2 || router == routerV3, "Collector: invalid router");
        token.safeApprove(router, type(uint256).max);
    }

    function swapRCH(
        address token,
        uint256 minPrice,
        uint256 deadline,
        address[] calldata path
    ) external onlyOwner {
        // last element of path should be rch
        require(path.length <= 4, "Collector: path too long");
        require(path[path.length - 1] == rch, "Collector: invalid path");

        uint256 amountIn = IERC20(token).balanceOf(address(this));
        IUniswapV2Router(routerV2).swapExactTokensForTokens(
            amountIn,
            amountIn * minPrice / 1e18,
            path,
            address(this),
            deadline
        );
    }

    function swapRCH(
        address token,
        uint256 minPrice,
        uint256 deadline,
        bytes calldata path
    ) external onlyOwner {
        uint256 balanceBefore = IERC20(rch).balanceOf(address(this));
        uint256 amountIn = IERC20(token).balanceOf(address(this));
        ISwapRouter.ExactInputParams memory params =
            ISwapRouter.ExactInputParams({
                path: path,
                recipient: address(this),
                deadline: deadline,
                amountIn: amountIn,
                amountOutMinimum: amountIn * minPrice / 1e18
           });
        uint256 amountOut = ISwapRouter(routerV3).exactInput(params);
        uint256 balanceAfter = IERC20(rch).balanceOf(address(this));
        require(balanceAfter == balanceBefore + amountOut, "Collector: invalid path");
    }

    function burnRCH() external {
        IERC20Burnable(rch).burn(IERC20(rch).balanceOf(address(this)));
    }

    // set feeRate
    function setTradingFeeRate(uint256 tradingFeeRate_) external onlyOwner {
        tradingFeeRate = tradingFeeRate_;
    }
    function setSettlementFeeRate(uint256 settlementFeeRate_) external onlyOwner {
        settlementFeeRate = settlementFeeRate_;
    }
}
