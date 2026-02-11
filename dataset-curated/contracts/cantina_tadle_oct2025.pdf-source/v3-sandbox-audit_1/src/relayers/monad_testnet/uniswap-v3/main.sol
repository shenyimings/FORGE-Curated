// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {INonfungiblePositionManager, Helpers} from "./helpers.sol";

/**
 * @title Uniswap V3 Position Resolver
 * @dev Contract for managing Uniswap V3 NFT liquidity positions
 * @notice Provides functionality for minting, depositing, withdrawing, collecting fees, and burning positions
 */
contract UniswapV3PositionResolver is Helpers {
    constructor(address _nftManager, address _wethAddr, address _tadleMemory, address _uniswapV3Factory)
        Helpers(_nftManager, _wethAddr, _tadleMemory, _uniswapV3Factory)
    {}

    /**
     * @dev Creates a new Uniswap V3 liquidity pool
     * @param tokenA Address of the first token in the pair
     * @param tokenB Address of the second token in the pair
     * @param fee Trading fee tier (500 = 0.05%, 3000 = 0.3%, 10000 = 1%)
     * @param sqrtPriceX96 Initial sqrt price of the pool (Q64.96 format)
     * @return _eventName Name of the event to emit
     * @return _eventParam Encoded event parameters containing pool details
     */
    function createPool(address tokenA, address tokenB, uint24 fee, uint160 sqrtPriceX96)
        external
        returns (string memory _eventName, bytes memory _eventParam)
    {
        // Create pool and get pool address
        address pool = _createPool(tokenA, tokenB, fee, sqrtPriceX96);

        // Return event data for logging
        _eventName = "LogCreatePool(address,address,uint24,uint160,address)";
        _eventParam = abi.encode(tokenA, tokenB, fee, sqrtPriceX96, pool);
    }

    /**
     * @dev Creates a new Uniswap V3 NFT liquidity position
     * @param tokenA Address of the first token in the pair
     * @param tokenB Address of the second token in the pair
     * @param fee Trading fee tier (500 = 0.05%, 3000 = 0.3%, 10000 = 1%)
     * @param tickLower Lower price bound of the position
     * @param tickUpper Upper price bound of the position
     * @param amtA Amount of tokenA to deposit (use type(uint256).max for entire balance)
     * @param amtB Amount of tokenB to deposit (use type(uint256).max for entire balance)
     * @param slippage Maximum allowed slippage in basis points
     * @param getIds Array of IDs to retrieve token amounts [amtAId, amtBId]
     * @param setId ID to store the liquidity amount
     * @return _eventName Name of the event to emit
     * @return _eventParam Encoded event parameters
     */
    function mint(
        address tokenA,
        address tokenB,
        uint24 fee,
        int24 tickLower,
        int24 tickUpper,
        uint256 amtA,
        uint256 amtB,
        uint256 slippage,
        uint256[] calldata getIds,
        uint256 setId
    ) external payable returns (string memory _eventName, bytes memory _eventParam) {
        MintParams memory params;
        {
            params = MintParams(tokenA, tokenB, fee, tickLower, tickUpper, amtA, amtB, slippage);
        }
        params.amtA = getUint(getIds[0], params.amtA);
        params.amtB = getUint(getIds[1], params.amtB);

        (uint256 _tokenId, uint256 liquidity, uint256 amountA, uint256 amountB) = _mint(params);

        setUint(setId, liquidity);

        _eventName = "LogMint(uint256,uint256,uint256,uint256,int24,int24)";
        _eventParam = abi.encode(_tokenId, liquidity, amountA, amountB, params.tickLower, params.tickUpper);
    }

    /**
     * @dev Increases liquidity in an existing position
     * @param tokenId NFT position ID (0 for most recent position)
     * @param amountA Amount of tokenA to add
     * @param amountB Amount of tokenB to add
     * @param slippage Maximum allowed slippage in basis points
     * @param getIds Array of IDs to retrieve token amounts [amtAId, amtBId]
     * @param setId ID to store the new liquidity amount
     * @return _eventName Name of the event to emit
     * @return _eventParam Encoded event parameters
     */
    function deposit(
        uint256 tokenId,
        uint256 amountA,
        uint256 amountB,
        uint256 slippage,
        uint256[] calldata getIds,
        uint256 setId
    ) external payable returns (string memory _eventName, bytes memory _eventParam) {
        if (tokenId == 0) tokenId = _getLastNftId(address(this));
        amountA = getUint(getIds[0], amountA);
        amountB = getUint(getIds[1], amountB);
        (uint256 _liquidity, uint256 _amtA, uint256 _amtB) = _addLiquidityWrapper(tokenId, amountA, amountB, slippage);
        setUint(setId, _liquidity);

        _eventName = "LogDeposit(uint256,uint256,uint256,uint256)";
        _eventParam = abi.encode(tokenId, _liquidity, _amtA, _amtB);
    }

    /**
     * @dev Decreases liquidity from a position
     * @param tokenId NFT position ID (0 for most recent position)
     * @param liquidity Amount of liquidity to remove
     * @param amountAMin Minimum amount of tokenA to receive
     * @param amountBMin Minimum amount of tokenB to receive
     * @param getId ID to retrieve liquidity amount
     * @param setIds Array of IDs to store withdrawn amounts [amtAId, amtBId]
     * @return _eventName Name of the event to emit
     * @return _eventParam Encoded event parameters
     */
    function withdraw(
        uint256 tokenId,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        uint256 getId,
        uint256[] calldata setIds
    ) external payable returns (string memory _eventName, bytes memory _eventParam) {
        if (tokenId == 0) tokenId = _getLastNftId(address(this));
        uint128 _liquidity = uint128(getUint(getId, liquidity));

        (uint256 _amtA, uint256 _amtB) = _decreaseLiquidity(tokenId, _liquidity, amountAMin, amountBMin);

        setUint(setIds[0], _amtA);
        setUint(setIds[1], _amtB);

        _eventName = "LogWithdraw(uint256,uint256,uint256,uint256)";
        _eventParam = abi.encode(tokenId, _liquidity, _amtA, _amtB);
    }

    /**
     * @dev Collects accumulated fees from a position
     * @param tokenId NFT position ID (0 for most recent position)
     * @param amount0Max Maximum amount of token0 to collect
     * @param amount1Max Maximum amount of token1 to collect
     * @param getIds Array of IDs to retrieve max amounts [amount0MaxId, amount1MaxId]
     * @param setIds Array of IDs to store collected amounts [amount0Id, amount1Id]
     * @return _eventName Name of the event to emit
     * @return _eventParam Encoded event parameters
     */
    function collect(
        uint256 tokenId,
        uint256 amount0Max,
        uint256 amount1Max,
        uint256[] calldata getIds,
        uint256[] calldata setIds
    ) external payable returns (string memory _eventName, bytes memory _eventParam) {
        if (tokenId == 0) tokenId = _getLastNftId(address(this));
        uint128 _amount0Max = uint128(getUint(getIds[0], amount0Max));
        uint128 _amount1Max = uint128(getUint(getIds[1], amount1Max));
        (uint256 amount0, uint256 amount1) = _collect(tokenId, _amount0Max, _amount1Max);

        setUint(setIds[0], amount0);
        setUint(setIds[1], amount1);
        _eventName = "LogCollect(uint256,uint256,uint256)";
        _eventParam = abi.encode(tokenId, amount0, amount1);
    }

    /**
     * @dev Burns an NFT position after all liquidity has been withdrawn
     * @param tokenId NFT position ID (0 for most recent position)
     * @return _eventName Name of the event to emit
     * @return _eventParam Encoded event parameters
     */
    function burn(uint256 tokenId) external payable returns (string memory _eventName, bytes memory _eventParam) {
        if (tokenId == 0) tokenId = _getLastNftId(address(this));
        _burn(tokenId);
        _eventName = "LogBurnPosition(uint256)";
        _eventParam = abi.encode(tokenId);
    }
}

/**
 * @title Uniswap V3 Position Connector
 * @dev Connector contract for integrating Uniswap V3 position management
 */
contract ConnectV1UniswapV3Position is UniswapV3PositionResolver {
    /// @dev Connector name for identification
    string public constant name = "UniswapV3-position-v1.0.0";

    constructor(address _nftManager, address _wethAddr, address _tadleMemory, address _uniswapV3Factory)
        UniswapV3PositionResolver(_nftManager, _wethAddr, _tadleMemory, _uniswapV3Factory)
    {}
}
