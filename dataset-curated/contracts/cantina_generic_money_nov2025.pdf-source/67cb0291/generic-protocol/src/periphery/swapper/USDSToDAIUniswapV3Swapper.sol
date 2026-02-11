// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import {
    UniswapV3Swapper,
    IUniswapSwapRouterLike,
    IUniswapQuoterLike,
    SafeERC20,
    IERC20
} from "./UniswapV3Swapper.sol";
import { IDaiUsdsConverter } from "../../interfaces/IDaiUsdsConverter.sol";

/**
 * @title USDSToDAIUniswapV3Swapper
 * @notice A specialized Uniswap V3 swapper that handles USDS-DAI conversions
 * @dev This contract extends UniswapV3Swapper to provide seamless swapping between
 * any token and USDS by automatically converting between DAI and USDS when needed.
 * It uses a DAI-USDS converter for 1:1 conversions and Uniswap V3 for other token pairs.
 */
contract USDSToDAIUniswapV3Swapper is UniswapV3Swapper {
    using SafeERC20 for IERC20;

    /**
     * @notice The DAI-USDS converter contract for 1:1 conversions
     */
    IDaiUsdsConverter public immutable daiToUsdsConverter;
    /**
     * @notice The address of the DAI token contract
     */
    address public immutable DAI;
    /**
     * @notice The address of the USDS token contract
     */
    address public immutable USDS;

    /**
     * @notice Thrown when both assets are USDS
     */
    error BothAssetsUSDS();

    /**
     * @notice Constructs the USDSToDAIUniswapV3Swapper contract
     * @param uniswapRouter_ The address of the Uniswap V3 router contract
     * @param quoter_ The address of the Uniswap V3 quoter contract
     * @param daiToUsdsConverter_ The address of the DAI-USDS converter contract
     * @param dai_ The address of the DAI token contract
     * @param usds_ The address of the USDS token contract
     */
    constructor(
        IUniswapSwapRouterLike uniswapRouter_,
        IUniswapQuoterLike quoter_,
        IDaiUsdsConverter daiToUsdsConverter_,
        address dai_,
        address usds_
    )
        UniswapV3Swapper(uniswapRouter_, quoter_)
    {
        daiToUsdsConverter = daiToUsdsConverter_;
        DAI = dai_;
        USDS = usds_;
    }

    /**
     * @notice Swaps tokens with automatic USDS-DAI conversion handling
     * @dev This function handles three scenarios:
     * 1. USDS -> Other Token: Converts USDS to DAI, then swaps DAI to target token
     * 2. Other Token -> USDS: Swaps input token to DAI, then converts DAI to USDS
     * 3. Other Token -> Other Token: Uses standard Uniswap V3 swap (via parent contract)
     * @param assetIn The address of the input token to swap from
     * @param amountIn The amount of input tokens to swap
     * @param assetOut The address of the output token to swap to
     * @param minAmountOut The minimum amount of output tokens expected
     * @param recipient The address that will receive the output tokens
     * @param swapperParams ABI-encoded SwapperParams struct containing the fee tier
     * @return amountOut The actual amount of output tokens received from the swap
     */
    function swap(
        address assetIn,
        uint256 amountIn,
        address assetOut,
        uint256 minAmountOut,
        address recipient,
        bytes calldata swapperParams
    )
        public
        override
        returns (uint256 amountOut)
    {
        require(assetIn != USDS || assetOut != USDS, BothAssetsUSDS());

        if (assetIn == USDS) {
            // convert USDS to DAI first
            IERC20(USDS).forceApprove(address(daiToUsdsConverter), amountIn);
            daiToUsdsConverter.usdsToDai(address(this), amountIn);
            // swap DAI to assetOut
            amountOut = super.swap(DAI, amountIn, assetOut, minAmountOut, recipient, swapperParams);
        } else if (assetOut == USDS) {
            // swap assetIn to DAI first
            amountOut = super.swap(assetIn, amountIn, DAI, minAmountOut, address(this), swapperParams);
            // convert DAI to USDS and send to recipient
            IERC20(DAI).forceApprove(address(daiToUsdsConverter), amountOut);
            daiToUsdsConverter.daiToUsds(recipient, amountOut);
        } else {
            // standard swap via Uniswap V3
            amountOut = super.swap(assetIn, amountIn, assetOut, minAmountOut, recipient, swapperParams);
        }
    }

    /**
     * @notice Quotes the amount of output tokens with USDS-DAI conversion handling
     * @dev Automatically substitutes USDS with DAI for price quotes since USDS-DAI
     * conversion is 1:1. This provides accurate pricing for swaps involving USDS.
     * @param assetIn The address of the input token
     * @param amountIn The amount of input tokens
     * @param assetOut The address of the output token
     * @param swapperParams ABI-encoded SwapperParams struct containing the fee tier
     * @return amountOut The estimated amount of output tokens
     */
    function getAmountOut(
        address assetIn,
        uint256 amountIn,
        address assetOut,
        bytes calldata swapperParams
    )
        public
        override
        returns (uint256 amountOut)
    {
        return super.getAmountOut({
            assetIn: assetIn == USDS ? DAI : assetIn,
            amountIn: amountIn,
            assetOut: assetOut == USDS ? DAI : assetOut,
            swapperParams: swapperParams
        });
    }
}
