// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "hardhat/console.sol";

interface ILBRouter {
    enum Version {
        V1,
        V2,
        V2_1,
        V2_2
    }

    struct Path {
        uint256[] pairBinSteps;
        Version[] versions;
        address[] tokenPath;
    }
}

contract MockLBRouter {
    uint256 public returnAmount;
    IERC20 public immutable WNATIVE;
    
    constructor(address _wnative) {
        WNATIVE = IERC20(_wnative);
    }
    
    receive() external payable {}

    function setReturnAmount(uint256 _amount) external {
        returnAmount = _amount;
    }

    // Main swap function for token to token swaps
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        ILBRouter.Path memory path,
        address to,
        uint256 deadline
    ) external returns (uint256) {
        require(deadline >= block.timestamp, "Transaction too old");
        require(path.tokenPath.length >= 2, "Invalid path");
        require(returnAmount >= amountOutMin, "Insufficient output amount");

        // Get the input token 
        address tokenIn = path.tokenPath[0];
        
        // Transfer tokens from sender to this contract
        require(IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn), "Transfer failed");
        
        // Send WNATIVE as the output token
        require(WNATIVE.transfer(to, returnAmount), "Output transfer failed");
        
        return returnAmount;
    }

    // Getter function to match LBRouter interface
    function getWNATIVE() external view returns (address) {
        return address(WNATIVE);
    }
}
