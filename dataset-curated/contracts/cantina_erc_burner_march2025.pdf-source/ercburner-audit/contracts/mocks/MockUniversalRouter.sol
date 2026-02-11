// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "hardhat/console.sol";

interface IPermit2 {
    function transferFrom(address token, address from, address to, uint256 amount) external;
}

contract MockUniversalRouter {
    uint256 public returnAmount;
    mapping(address => uint256) public nativeBalances;
    IPermit2 public immutable permit2;
    IERC20 public immutable WNATIVE;
    
    constructor(address _permit2, address _wnative) {
        permit2 = IPermit2(_permit2);
        WNATIVE = IERC20(_wnative);
    }
    
    receive() external payable {
        nativeBalances[msg.sender] += msg.value;
    }

    function setReturnAmount(uint256 _amount) external {
        returnAmount = _amount;
    }

    function execute(
        bytes calldata commands,
        bytes[] calldata inputs,
        uint256 deadline
    ) external payable returns (uint256) {
        require(deadline >= block.timestamp, "Transaction too old");
        // console.log("MockUniversalRouter / Executing commands...");
        // Process each command
        for (uint256 i = 0; i < commands.length; i++) {
            bytes1 command = commands[i];
            if (command == 0x00) {
                // Handle both V3 swaps similarly for mock
                (
                    address recipient,
                    uint256 amountIn,
                    uint256 amountOutMinimum,
                    bytes memory path,
                    bool payerIsUser
                ) = abi.decode(inputs[i], (address, uint256, uint256, bytes, bool));
                // console.log("MockUniversalRouter / AmountIn: %s", amountIn);
                require(returnAmount >= amountOutMinimum, "MockUniversalRouter / Insufficient output amount");
                // console.log("MockUniversalRouter / AmountOutMinimum: %s", amountOutMinimum);

                // Extract token from path (first 20 bytes after length)
                address tokenIn;
                assembly {
                    tokenIn := shr(96, mload(add(path, 32)))
                }
                // console.log("MockUniversalRouter / TokenIn: %s", tokenIn);
                // Pull tokens from permit2 - using recipient as the from address since that's the Burner contract
                permit2.transferFrom(tokenIn, recipient, address(this), amountIn);
                // console.log("MockUniversalRouter / Transferred tokens from permit2");
                // Transfer WNATIVE as output token
                require(WNATIVE.transfer(recipient, returnAmount), "MockUniversalRouter / WNATIVE transfer failed");
                // console.log("MockUniversalRouter / Transferred WNATIVE to recipient");
            } else if (command == 0x08) {
                // Handle V2 swaps for mock
                (
                    address recipient,
                    uint256 amountIn,
                    uint256 amountOutMinimum,
                    address[] memory path,
                    bool payerIsUser
                ) = abi.decode(inputs[i], (address, uint256, uint256, address[], bool));
                // console.log("MockUniversalRouter / AmountIn: %s", amountIn);
                require(returnAmount >= amountOutMinimum, "MockUniversalRouter / Insufficient output amount");
                // console.log("MockUniversalRouter / AmountOutMinimum: %s", amountOutMinimum);

                // Extract token from path (first 20 bytes after length)
                address tokenIn = path[0];
                // console.log("MockUniversalRouter / TokenIn: %s", tokenIn);
                // Pull tokens from permit2 - using recipient as the from address since that's the Burner contract
                permit2.transferFrom(tokenIn, recipient, address(this), amountIn);
                // console.log("MockUniversalRouter / Transferred tokens from permit2");
                // Transfer WNATIVE as output token
                require(WNATIVE.transfer(recipient, returnAmount), "MockUniversalRouter / WNATIVE transfer failed");
                // console.log("MockUniversalRouter / Transferred WNATIVE to recipient");
            } else if (command == 0x0c) {
                // Wrap native token
                (address recipient, uint256 amountIn) = abi.decode(inputs[i], (address, uint256));
                require(msg.value >= amountIn, "Insufficient native token");
                nativeBalances[recipient] += amountIn;
                // console.log("Wrapped native token");
            }
        }
        
        return returnAmount;
    }

    // Helper function to withdraw native balance
    function withdrawNativeBalance() external {
        uint256 amount = nativeBalances[msg.sender];
        require(amount > 0, "No balance to withdraw");
        nativeBalances[msg.sender] = 0;
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "Native token transfer failed");
    }
} 