// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "hardhat/console.sol";

contract MockPermit2 {
    mapping(address => mapping(address => mapping(address => uint256))) public allowances;

    function approve(address token, address spender, uint160 amount, uint48 expiration) external {
        allowances[token][msg.sender][spender] = amount;
        // console.log("MockPermit2 / Token: %s", token);
        // console.log("MockPermit2 / From: %s", msg.sender);
        // console.log("MockPermit2 / To: %s", spender);
        // console.log("MockPermit2 / Amount: %s", amount);
        // console.log("MockPermit2 / Approved: %s", amount);

    }


    function transferFrom(address token, address from, address to, uint256 amount) external {
        // console.log("MockPermit2 / Token: %s", token);
        // console.log("MockPermit2 / From: %s", from);
        // console.log("MockPermit2 / To: %s", to);
        // console.log("MockPermit2 / Amount: %s", amount);
        // console.log("MockPermit2 / Current allowance: %s", allowances[token][from][to]);
        require(allowances[token][from][to] >= amount, "MockPermit2: Insufficient allowance");
        allowances[token][from][to] -= amount;
        


        IERC20(token).transferFrom(from, to, amount);
        // console.log("MockPermit2 / Transfer successful");
    }

    // Helper function to check allowance
    function getAllowance(address token, address spender) external view returns (uint256) {
        return allowances[token][msg.sender][spender];
    }
}
