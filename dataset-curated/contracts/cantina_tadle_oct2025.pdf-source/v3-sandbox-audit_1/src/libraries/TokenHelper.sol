// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title TokenInterface
 * @dev Interface for token operations including ERC20 functions and ETH wrapper functions
 */
interface TokenInterface {
    function approve(address, uint256) external;

    function allowance(address, address) external view returns (uint256);

    function transfer(address, uint256) external;

    function transferFrom(address, address, uint256) external;

    function deposit() external payable;

    function withdraw(uint256) external;

    function balanceOf(address) external view returns (uint256);

    function decimals() external view returns (uint256);
}

/**
 * @title TokenHelper Library
 * @dev Library for handling token-related operations including ETH/WETH conversions
 * @notice Provides utility functions for token approvals, transfers, and balance checks
 */
library TokenHelper {
    using SafeERC20 for IERC20;

    // ETH token address representation
    address internal constant ethAddr = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    /**
     * @dev Get token balance for the current contract
     * @param token Token interface to check balance
     * @return _amt Current balance of the token
     */
    function getTokenBal(TokenInterface token) internal view returns (uint256 _amt) {
        _amt = address(token) == ethAddr ? address(this).balance : token.balanceOf(address(this));
    }

    /**
     * @dev Get decimals for a pair of tokens
     * @param buyAddr First token address
     * @param sellAddr Second token address
     * @return buyDec Decimals of first token
     * @return sellDec Decimals of second token
     */
    function getTokensDec(TokenInterface buyAddr, TokenInterface sellAddr)
        internal
        view
        returns (uint256 buyDec, uint256 sellDec)
    {
        buyDec = address(buyAddr) == ethAddr ? 18 : buyAddr.decimals();
        sellDec = address(sellAddr) == ethAddr ? 18 : sellAddr.decimals();
    }

    /**
     * @dev Safe approve tokens for all ERC20 tokens including non-standard ones
     * @param token Token to approve
     * @param spender Address to approve for
     * @param amount Amount to approve
     * @notice This function handles various token implementations safely:
     *         1. Skips approval for ETH (not needed)
     *         2. Uses SafeERC20 for standard and non-standard ERC20 tokens
     *         3. Handles tokens that return no value (like USDT)
     *         4. Handles tokens that require setting to zero before non-zero value
     */
    function approve(TokenInterface token, address spender, uint256 amount) internal {
        if (address(token) == ethAddr) return; // ETH doesn't need approval

        // For ERC20 tokens, use SafeERC20's forceApprove which handles non-standard tokens
        address tokenAddr = address(token);
        IERC20 erc20Token = IERC20(tokenAddr);

        // Use SafeERC20's forceApprove which handles tokens that:
        // 1. Return no value (like USDT)
        // 2. Require setting to zero before non-zero value (like USDT)
        // 3. Standard tokens that return boolean
        SafeERC20.forceApprove(erc20Token, spender, amount);
    }

    /**
     * @dev Convert ETH addresses to WETH addresses if needed
     * @param buy Buy token address
     * @param sell Sell token address
     * @param wethAddr WETH contract address
     * @return _buy Converted buy token interface
     * @return _sell Converted sell token interface
     */
    function changeEthAddress(address buy, address sell, address wethAddr)
        internal
        pure
        returns (TokenInterface _buy, TokenInterface _sell)
    {
        _buy = buy == ethAddr ? TokenInterface(wethAddr) : TokenInterface(buy);
        _sell = sell == ethAddr ? TokenInterface(wethAddr) : TokenInterface(sell);
    }

    /**
     * @dev Convert ETH to WETH
     * @param isEth Flag indicating if conversion is needed
     * @param token WETH token interface
     * @param amount Amount to convert
     */
    function convertEthToWeth(bool isEth, TokenInterface token, uint256 amount) internal {
        if (isEth) token.deposit{value: amount}();
    }

    /**
     * @dev Convert WETH back to ETH
     * @param isEth Flag indicating if conversion is needed
     * @param token WETH token interface
     * @param amount Amount to convert
     */
    function convertWethToEth(bool isEth, TokenInterface token, uint256 amount) internal {
        if (isEth) {
            approve(token, address(token), amount);
            token.withdraw(amount);
        }
    }

    /**
     * @dev Safely transfers ERC20 tokens to a recipient
     * @param token Token interface to transfer
     * @param to Recipient address
     * @param amount Amount of tokens to transfer
     * @notice Uses SafeERC20 to handle non-standard tokens (like USDT)
     */
    function safeTransfer(TokenInterface token, address to, uint256 amount) internal {
        if (address(token) == ethAddr) {
            // Handle ETH transfer
            (bool success,) = to.call{value: amount}("");
            require(success, "ETH transfer failed");
        } else {
            // For ERC20 tokens, use SafeERC20's safeTransfer
            IERC20 erc20Token = IERC20(address(token));
            SafeERC20.safeTransfer(erc20Token, to, amount);
        }
    }

    /**
     * @dev Safely transfers ERC20 tokens from a sender to a recipient
     * @param token Token interface to transfer
     * @param from Sender address
     * @param to Recipient address
     * @param amount Amount of tokens to transfer
     * @notice Uses SafeERC20 to handle non-standard tokens (like USDT)
     */
    function safeTransferFrom(TokenInterface token, address from, address to, uint256 amount) internal {
        if (address(token) == ethAddr) {
            revert("Cannot transferFrom ETH");
        } else {
            // For ERC20 tokens, use SafeERC20's safeTransferFrom
            IERC20 erc20Token = IERC20(address(token));
            SafeERC20.safeTransferFrom(erc20Token, from, to, amount);
        }
    }
}
