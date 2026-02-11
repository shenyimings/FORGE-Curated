// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../../../../src/interfaces/aerodrome/IAerodromeSlipstreamFactory.sol";

contract MockAerodromeFactory is IAerodromeSlipstreamFactory {
    mapping(address => mapping(address => mapping(int24 => address))) public pools;
    address public immutable override owner;
    address public immutable override poolImplementation;

    constructor() {
        owner = msg.sender;
        poolImplementation = address(0x1234); // Mock implementation
    }

    function setPool(address tokenA, address tokenB, int24 tickSpacing, address pool) external {
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        pools[token0][token1][tickSpacing] = pool;
    }

    function getPool(address tokenA, address tokenB, int24 tickSpacing) external view override returns (address pool) {
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        return pools[token0][token1][tickSpacing];
    }

    function createPool(address tokenA, address tokenB, int24 tickSpacing, uint160 sqrtPriceX96) 
        external override returns (address pool) {
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        
        // Create a simple mock pool address
        pool = address(uint160(uint256(keccak256(abi.encodePacked(token0, token1, tickSpacing)))));
        pools[token0][token1][tickSpacing] = pool;
        
        emit PoolCreated(token0, token1, tickSpacing, pool);
        return pool;
    }
}