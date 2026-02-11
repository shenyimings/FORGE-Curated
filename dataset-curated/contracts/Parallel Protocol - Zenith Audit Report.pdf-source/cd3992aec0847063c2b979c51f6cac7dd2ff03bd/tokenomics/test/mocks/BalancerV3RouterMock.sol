// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { IBalancerV3Router } from "contracts/interfaces/IBalancerV3Router.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20Mock } from "./ERC20Mock.sol";

contract BalancerV3RouterMock is IBalancerV3Router {
    address[2] public tokens;
    ERC20Mock public bpt;

    constructor(address[2] memory _tokens, address _bpt) {
        tokens = _tokens;
        bpt = ERC20Mock(_bpt);
    }

    function addLiquidityProportional(
        address pool,
        uint256[] memory maxAmountsIn,
        uint256 exactBptAmountOut,
        bool wethIsEth,
        bytes memory userData
    )
        external
        payable
        override
        returns (uint256[] memory amountsIn)
    {
        IERC20(tokens[0]).transferFrom(msg.sender, address(this), maxAmountsIn[0]);
        IERC20(tokens[1]).transferFrom(msg.sender, address(this), maxAmountsIn[1]);
        bpt.mint(msg.sender, exactBptAmountOut);
        return maxAmountsIn;
    }

    function removeLiquidityProportional(
        address pool,
        uint256 exactBptAmountIn,
        uint256[] memory minAmountsOut,
        bool wethIsEth,
        bytes memory userData
    )
        external
        payable
        override
        returns (uint256[] memory amountsOut)
    {
        bpt.burn(msg.sender, exactBptAmountIn);
        IERC20(tokens[0]).transfer(msg.sender, minAmountsOut[0]);
        IERC20(tokens[1]).transfer(msg.sender, minAmountsOut[1]);
        return minAmountsOut;
    }
}
