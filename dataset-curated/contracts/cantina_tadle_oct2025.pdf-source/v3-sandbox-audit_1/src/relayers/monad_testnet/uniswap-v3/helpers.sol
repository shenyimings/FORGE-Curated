// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Math} from "../../../libraries/Math.sol";
import {TokenHelper, TokenInterface} from "../../../libraries/TokenHelper.sol";
import {Stores} from "../implementation/Stores.sol";

/**
 * @title Uniswap V3 Nonfungible Position Manager Interface
 * @dev Interface for managing liquidity positions as NFTs in Uniswap V3
 */
interface INonfungiblePositionManager {
    /**
     * @dev Parameters for minting a new position
     * @param token0 The address of the first token
     * @param token1 The address of the second token
     * @param fee The fee tier of the pool
     * @param tickLower The lower tick of the position
     * @param tickUpper The upper tick of the position
     * @param amount0Desired The desired amount of token0 to deposit
     * @param amount1Desired The desired amount of token1 to deposit
     * @param amount0Min The minimum amount of token0 to deposit
     * @param amount1Min The minimum amount of token1 to deposit
     * @param recipient The address that will receive the NFT
     * @param deadline The timestamp after which the transaction will revert
     */
    struct MintParams {
        address token0;
        address token1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address recipient;
        uint256 deadline;
    }

    /**
     * @dev Parameters for increasing liquidity in a position
     * @param tokenId The ID of the token for which liquidity is being increased
     * @param amount0Desired The desired amount of token0 to add
     * @param amount1Desired The desired amount of token1 to add
     * @param amount0Min The minimum amount of token0 to add
     * @param amount1Min The minimum amount of token1 to add
     * @param deadline The timestamp after which the transaction will revert
     */
    struct IncreaseLiquidityParams {
        uint256 tokenId;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }

    /**
     * @dev Parameters for decreasing liquidity in a position
     * @param tokenId The ID of the token for which liquidity is being decreased
     * @param liquidity The amount of liquidity to remove
     * @param amount0Min The minimum amount of token0 that should be received
     * @param amount1Min The minimum amount of token1 that should be received
     * @param deadline The timestamp after which the transaction will revert
     */
    struct DecreaseLiquidityParams {
        uint256 tokenId;
        uint128 liquidity;
        uint256 amount0Min;
        uint256 amount1Min;
        uint256 deadline;
    }

    /**
     * @dev Parameters for collecting fees from a position
     * @param tokenId The ID of the NFT for which tokens are being collected
     * @param recipient The address that will receive the collected tokens
     * @param amount0Max The maximum amount of token0 to collect
     * @param amount1Max The maximum amount of token1 to collect
     */
    struct CollectParams {
        uint256 tokenId;
        address recipient;
        uint128 amount0Max;
        uint128 amount1Max;
    }

    /**
     * @dev Returns the position information associated with a given token ID
     * @param tokenId The ID of the token that represents the position
     * @return nonce The nonce for permits
     * @return operator The address that is approved for spending
     * @return token0 The address of the token0 for a specific pool
     * @return token1 The address of the token1 for a specific pool
     * @return fee The fee associated with the pool
     * @return tickLower The lower end of the tick range for the position
     * @return tickUpper The upper end of the tick range for the position
     * @return liquidity The amount of liquidity in the position
     * @return feeGrowthInside0LastX128 The fee growth of token0 as of the last action on the individual position
     * @return feeGrowthInside1LastX128 The fee growth of token1 as of the last action on the individual position
     * @return tokensOwed0 The uncollected amount of token0 owed to the position
     * @return tokensOwed1 The uncollected amount of token1 owed to the position
     */
    function positions(uint256 tokenId)
        external
        view
        returns (
            uint96 nonce,
            address operator,
            address token0,
            address token1,
            uint24 fee,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            uint256 feeGrowthInside0LastX128,
            uint256 feeGrowthInside1LastX128,
            uint128 tokensOwed0,
            uint128 tokensOwed1
        );

    /**
     * @dev Creates a new position wrapped in a NFT
     * @param params The parameters necessary for the mint, encoded as MintParams
     * @return tokenId The ID of the token that represents the minted position
     * @return liquidity The amount of liquidity for this position
     * @return amount0 The amount of token0 that was paid to mint the position
     * @return amount1 The amount of token1 that was paid to mint the position
     */
    function mint(MintParams calldata params)
        external
        payable
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);

    /**
     * @dev Increases the amount of liquidity in a position
     * @param params The parameters necessary for the increase, encoded as IncreaseLiquidityParams
     * @return liquidity The new liquidity amount as a result of the increase
     * @return amount0 The amount of token0 that was paid for the increase
     * @return amount1 The amount of token1 that was paid for the increase
     */
    function increaseLiquidity(IncreaseLiquidityParams calldata params)
        external
        payable
        returns (uint128 liquidity, uint256 amount0, uint256 amount1);

    /**
     * @dev Decreases the amount of liquidity in a position
     * @param params The parameters necessary for the decrease, encoded as DecreaseLiquidityParams
     * @return amount0 The amount of token0 withdrawn
     * @return amount1 The amount of token1 withdrawn
     */
    function decreaseLiquidity(DecreaseLiquidityParams calldata params)
        external
        payable
        returns (uint256 amount0, uint256 amount1);

    /**
     * @dev Collects tokens owed to a position
     * @param params The parameters necessary for collecting fees, encoded as CollectParams
     * @return amount0 The amount of fees collected in token0
     * @return amount1 The amount of fees collected in token1
     */
    function collect(CollectParams calldata params) external payable returns (uint256 amount0, uint256 amount1);

    /**
     * @dev Burns a token ID, which deletes it from the NFT contract
     * @param tokenId The ID of the token that is being burned
     */
    function burn(uint256 tokenId) external payable;

    /**
     * @dev Returns the number of tokens owned by an address
     * @param owner The address to query the balance of
     * @return balance The number of tokens owned by the address
     */
    function balanceOf(address owner) external view returns (uint256 balance);

    /**
     * @dev Returns a token ID at a given index of the tokens list of the requested owner
     * @param owner The address owning the tokens list to be accessed
     * @param index The index in the owner's tokens list
     * @return tokenId The token ID at the given index of the tokens list
     */
    function tokenOfOwnerByIndex(address owner, uint256 index) external view returns (uint256 tokenId);
}

interface IUniswapV3Factory {
    function createPool(address tokenA, address tokenB, uint24 fee) external returns (address pool);
}

interface IUniswapV3Pool {
    function initialize(uint160 sqrtPriceX96) external;
}

/**
 * @title Uniswap V3 Helper Contract
 * @dev Helper functions for interacting with Uniswap V3 NFT positions
 * @notice This contract provides utility functions for managing liquidity positions
 */
contract Helpers is Stores {
    using TokenHelper for TokenInterface;
    using TokenHelper for address;
    using Math for uint256;

    /// @dev Constant for base unit (1e18)
    uint256 private constant WAD = 10 ** 18;
    /// @dev WETH contract address
    address public immutable wethAddr;
    /// @dev Uniswap V3 NFT position manager contract
    INonfungiblePositionManager public immutable nftManager;

    IUniswapV3Factory public immutable uniswapV3Factory;

    /**
     * @dev Parameters for minting a new position
     * @param tokenA Address of the first token
     * @param tokenB Address of the second token
     * @param fee Trading fee tier (e.g., 500 for 0.05%, 3000 for 0.3%, 10000 for 1%)
     * @param tickLower Lower tick boundary for the position
     * @param tickUpper Upper tick boundary for the position
     * @param amtA Amount of tokenA to add (use type(uint256).max for entire balance)
     * @param amtB Amount of tokenB to add (use type(uint256).max for entire balance)
     * @param slippage Maximum allowed slippage in WAD (e.g., 0.01e18 for 1%)
     */
    struct MintParams {
        address tokenA;
        address tokenB;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amtA;
        uint256 amtB;
        uint256 slippage;
    }

    /**
     * @dev Contract constructor
     * @param _nftManager Address of Uniswap V3 NFT position manager
     * @param _wethAddr Address of WETH contract
     */
    constructor(address _nftManager, address _wethAddr, address _tadleMemory, address _uniswapV3Factory)
        Stores(_tadleMemory)
    {
        require(_nftManager != address(0), "Invalid NFT manager");
        require(_wethAddr != address(0), "Invalid WETH address");
        require(_uniswapV3Factory != address(0), "Invalid Uniswap V3 factory address");

        nftManager = INonfungiblePositionManager(_nftManager);
        wethAddr = _wethAddr;
        uniswapV3Factory = IUniswapV3Factory(_uniswapV3Factory);
    }

    /**
     * @dev Retrieves the latest NFT token ID for a user
     * @param user Address of the user
     * @return tokenId The latest NFT token ID
     */
    function _getLastNftId(address user) internal view returns (uint256 tokenId) {
        uint256 len = nftManager.balanceOf(user);
        require(len > 0, "No NFTs found");
        tokenId = nftManager.tokenOfOwnerByIndex(user, len - 1);
    }

    /**
     * @dev Calculates minimum amount considering slippage
     * @param token Token interface
     * @param amt Original amount
     * @param slippage Slippage percentage in WAD
     * @return minAmt Minimum amount after slippage
     */
    function getMinAmount(TokenInterface token, uint256 amt, uint256 slippage) internal view returns (uint256 minAmt) {
        uint256 _amt18 = amt.convertTo18(token.decimals());
        minAmt = _amt18.wmul(WAD.sub(slippage));
        minAmt = minAmt.convert18ToDec(token.decimals());
    }

    /**
     * @dev Creates and initializes a new Uniswap V3 pool
     * @param tokenA Address of the first token in the pair
     * @param tokenB Address of the second token in the pair
     * @param fee Trading fee tier (500 = 0.05%, 3000 = 0.3%, 10000 = 1%)
     * @param sqrtPriceX96 Initial sqrt price of the pool (Q64.96 format)
     * @return pool Address of the newly created pool
     */
    function _createPool(address tokenA, address tokenB, uint24 fee, uint160 sqrtPriceX96)
        internal
        returns (address pool)
    {
        // Create new pool through factory
        pool = uniswapV3Factory.createPool(tokenA, tokenB, fee);
        // Initialize pool with starting price
        IUniswapV3Pool(pool).initialize(sqrtPriceX96);
    }

    /**
     * @dev Wrapper function for adding liquidity to handle token conversion and validation
     * @param tokenId NFT position ID
     * @param amountA Amount of first token to add
     * @param amountB Amount of second token to add
     * @param slippage Maximum allowed slippage in basis points
     * @return liquidity Amount of liquidity added
     * @return amtA Actual amount of first token used
     * @return amtB Actual amount of second token used
     */
    function _addLiquidityWrapper(uint256 tokenId, uint256 amountA, uint256 amountB, uint256 slippage)
        internal
        returns (uint256 liquidity, uint256 amtA, uint256 amtB)
    {
        // Get token addresses from position
        (address token0, address token1) = getNftTokenPairAddresses(tokenId);

        // Add liquidity with token conversion handling
        (liquidity, amtA, amtB) = _addLiquidity(tokenId, token0, token1, amountA, amountB, slippage);
    }

    /**
     * @dev Internal helper to handle ETH/WETH conversion and token approvals
     * @param _token0 Address of first token
     * @param _token1 Address of second token
     * @param _amount0 Amount of first token
     * @param _amount1 Amount of second token
     */
    function _checkETH(address _token0, address _token1, uint256 _amount0, uint256 _amount1) internal {
        // Check if either token is ETH
        bool isEth0 = _token0 == wethAddr;
        bool isEth1 = _token1 == wethAddr;

        // Convert ETH to WETH if necessary
        TokenHelper.convertEthToWeth(isEth0, TokenInterface(_token0), _amount0);
        TokenHelper.convertEthToWeth(isEth1, TokenInterface(_token1), _amount1);

        // Approve NFT manager to spend tokens
        TokenHelper.approve(TokenInterface(_token0), address(nftManager), _amount0);
        TokenHelper.approve(TokenInterface(_token1), address(nftManager), _amount1);
    }

    /**
     * @dev Mint function which interact with Uniswap v3
     */
    function _mint(MintParams memory params)
        internal
        returns (uint256 tokenId, uint128 liquidity, uint256 amountA, uint256 amountB)
    {
        (TokenInterface _token0, TokenInterface _token1) =
            TokenHelper.changeEthAddress(params.tokenA, params.tokenB, wethAddr);
        uint256 _amount0 = params.amtA == type(uint256).max ? TokenHelper.getTokenBal(_token0) : params.amtA;
        uint256 _amount1 = params.amtB == type(uint256).max ? TokenHelper.getTokenBal(_token1) : params.amtB;

        TokenHelper.convertEthToWeth(address(_token0) == wethAddr, _token0, _amount0);
        TokenHelper.convertEthToWeth(address(_token1) == wethAddr, _token1, _amount1);

        TokenHelper.approve(_token0, address(nftManager), _amount0);
        TokenHelper.approve(_token1, address(nftManager), _amount1);

        uint256 _minAmt0 = getMinAmount(_token0, _amount0, params.slippage);
        uint256 _minAmt1 = getMinAmount(_token1, _amount1, params.slippage);

        INonfungiblePositionManager.MintParams memory mintParams = INonfungiblePositionManager.MintParams(
            address(_token0),
            address(_token1),
            params.fee,
            params.tickLower,
            params.tickUpper,
            _amount0,
            _amount1,
            _minAmt0,
            _minAmt1,
            address(this),
            block.timestamp + 20 minutes
        );

        (tokenId, liquidity, amountA, amountB) = nftManager.mint(mintParams);
    }

    /**
     * @dev Retrieves token pair addresses for a given NFT position
     * @param _tokenId The ID of the NFT position
     * @return token0 Address of the first token in the pair
     * @return token1 Address of the second token in the pair
     */
    function getNftTokenPairAddresses(uint256 _tokenId) internal view returns (address token0, address token1) {
        (bool success, bytes memory data) =
            address(nftManager).staticcall(abi.encodeWithSelector(nftManager.positions.selector, _tokenId));
        require(success, "Failed to fetch position");
        {
            (,, token0, token1,,,,) =
                abi.decode(data, (uint96, address, address, address, uint24, int24, int24, uint128));
        }
    }

    /**
     * @dev addLiquidity function which interact with Uniswap v3
     */
    function _addLiquidity(
        uint256 _tokenId,
        address _token0,
        address _token1,
        uint256 _amount0,
        uint256 _amount1,
        uint256 _slippage
    ) internal returns (uint128 liquidity, uint256 amount0, uint256 amount1) {
        _checkETH(_token0, _token1, _amount0, _amount1);
        uint256 _amount0Min = getMinAmount(TokenInterface(_token0), _amount0, _slippage);
        uint256 _amount1Min = getMinAmount(TokenInterface(_token1), _amount1, _slippage);
        INonfungiblePositionManager.IncreaseLiquidityParams memory params = INonfungiblePositionManager
            .IncreaseLiquidityParams(_tokenId, _amount0, _amount1, _amount0Min, _amount1Min, block.timestamp);

        (liquidity, amount0, amount1) = nftManager.increaseLiquidity(params);
    }

    /**
     * @dev decreaseLiquidity function which interact with Uniswap v3
     */
    function _decreaseLiquidity(uint256 _tokenId, uint128 _liquidity, uint256 _amount0Min, uint256 _amount1Min)
        internal
        returns (uint256 amount0, uint256 amount1)
    {
        INonfungiblePositionManager.DecreaseLiquidityParams memory params = INonfungiblePositionManager
            .DecreaseLiquidityParams(_tokenId, _liquidity, _amount0Min, _amount1Min, block.timestamp);
        (amount0, amount1) = nftManager.decreaseLiquidity(params);
    }

    /**
     * @dev collect function which interact with Uniswap v3
     */
    function _collect(uint256 _tokenId, uint128 _amount0Max, uint128 _amount1Max)
        internal
        returns (uint256 amount0, uint256 amount1)
    {
        INonfungiblePositionManager.CollectParams memory params =
            INonfungiblePositionManager.CollectParams(_tokenId, address(this), _amount0Max, _amount1Max);
        (amount0, amount1) = nftManager.collect(params);
    }

    /**
     * @dev Burn Function
     */
    function _burn(uint256 _tokenId) internal {
        nftManager.burn(_tokenId);
    }
}
