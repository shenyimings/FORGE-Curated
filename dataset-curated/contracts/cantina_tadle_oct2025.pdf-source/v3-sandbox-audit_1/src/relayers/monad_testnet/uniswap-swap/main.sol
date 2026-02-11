// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {UniswapRouter02Helper} from "./helpers.sol";

/**
 * @title UniswapSwapRouter
 * @dev Contract for executing token swaps through Uniswap
 * @notice Provides high-level swap functionality with storage integration
 */
contract UniswapSwapRouter02Resolver is UniswapRouter02Helper {
    /**
     * @dev Initializes the contract with required addresses
     * @param _uniswapRouter Address of Uniswap Router contract
     * @param _wethAddr Address of WETH token
     * @param _tadleMemory Address of storage contract
     */
    constructor(address _uniswapRouter, address _wethAddr, address _tadleMemory)
        UniswapRouter02Helper(_uniswapRouter, _wethAddr, _tadleMemory)
    {}

    /**
     * @dev Executes a token swap with storage integration
     * @param amountIn Amount of input tokens
     * @param amountOutMin Minimum amount of output tokens expected
     * @param path Encoded swap path data
     * @param getIds Storage ID for retrieving input amount
     * @param setIds Storage ID for storing output amount
     * @return _eventName Name of the event to be logged
     * @return _eventParam Encoded event parameters
     */
    function buy(bool isEth, uint256 amountIn, uint256 amountOutMin, bytes memory path, uint256 getIds, uint256 setIds)
        external
        returns (string memory _eventName, bytes memory _eventParam)
    {
        // Get input amount from storage
        amountIn = getUint(getIds, amountIn);

        // Execute swap
        uint256 amountOut = _buy(amountIn, amountOutMin, address(this), isEth, path);

        // Store output amount
        setUint(setIds, amountOut);

        // Return event data
        _eventName = "Buy(address,bytes,uint256,uint256)";
        _eventParam = abi.encode(address(this), path, amountIn, amountOut);
    }
}

/**
 * @title ConnectV1UniswapSwapRouter02
 * @dev Connector implementation for Uniswap Router V2
 * @notice Entry point for Uniswap V2/V3 swap operations
 */
contract ConnectV1UniswapSwapRouter02 is UniswapSwapRouter02Resolver {
    /// @dev Version identifier for the connector
    string public constant name = "UniswapSwapRouter02-v1.0.0";

    /**
     * @dev Initializes the connector with required dependencies
     * @param _uniswapRouter Address of Uniswap Router contract
     * @param _wethAddr Address of WETH token
     * @param _tadleMemory Address of storage contract
     */
    constructor(address _uniswapRouter, address _wethAddr, address _tadleMemory)
        UniswapSwapRouter02Resolver(_uniswapRouter, _wethAddr, _tadleMemory)
    {}
}
