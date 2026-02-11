// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Stores} from "../implementation/Stores.sol";
import {SwapPath} from "../../../libraries/SwapPath.sol";
import {TokenHelper, TokenInterface} from "../../../libraries/TokenHelper.sol";

/**
 * @title IUniswapV2Router02
 * @dev Interface for interacting with Uniswap V2 and V3 Router contracts
 * @notice Defines core swap functions and parameter structures
 */
interface IUniswapV2Router02 {
    /**
     * @dev Parameters for exact input swaps
     * @param path Encoded path data for token swaps
     * @param recipient Address to receive output tokens
     * @param amountIn Exact amount of input tokens
     * @param amountOutMinimum Minimum amount of output tokens to receive
     */
    struct ExactInputParams {
        bytes path;
        address recipient;
        uint256 amountIn;
        uint256 amountOutMinimum;
    }

    /**
     * @dev Swaps exact amount of tokens using Uniswap V2 style paths
     * @param amountIn Exact amount of input tokens
     * @param amountOutMin Minimum amount of output tokens
     * @param path Array of token addresses for the swap path
     * @param to Address to receive output tokens
     * @return amountOut Amount of output tokens received
     */
    function swapExactTokensForTokens(uint256 amountIn, uint256 amountOutMin, address[] calldata path, address to)
        external
        payable
        returns (uint256 amountOut);

    /**
     * @dev Swaps exact amount of tokens using Uniswap V3 style paths
     * @param params Struct containing swap parameters
     * @return amountOut Amount of output tokens received
     */
    function exactInput(ExactInputParams calldata params) external payable returns (uint256 amountOut);
}

/**
 * @title UniswapRouter02Helper
 * @dev Helper contract for interacting with Uniswap V2 and V3 Router
 * @notice Provides unified swap functionality for both Uniswap versions
 */
contract UniswapRouter02Helper is Stores {
    using TokenHelper for TokenInterface;
    using TokenHelper for address;
    using SwapPath for bytes;

    // ============ Storage ============
    /// @dev Reference to Uniswap V2 Router contract
    IUniswapV2Router02 public immutable uniswapV2Router02;

    // ============ Constants ============
    /// @dev Signature identifier for Uniswap V2 Router
    bytes32 public constant UNISWAP_V2_ROUTER_02_SIG = keccak256("UNISWAP_V2_SWAP_ROUTER");
    /// @dev Signature identifier for Uniswap V3 Router
    bytes32 public constant UNISWAP_V3_ROUTER_02_SIG = keccak256("UNISWAP_V3_SWAP_ROUTER");
    address public immutable wethAddr;

    /**
     * @dev Initializes the contract with Uniswap Router address
     * @param _uniswapV2Router02 Address of Uniswap V2 Router contract
     */
    constructor(address _uniswapV2Router02, address _wethAddr, address _tadleMemory) Stores(_tadleMemory) {
        wethAddr = _wethAddr;
        uniswapV2Router02 = IUniswapV2Router02(_uniswapV2Router02);
    }

    /**
     * @dev Executes token swap using either Uniswap V2 or V3
     * @param amountIn Amount of input tokens
     * @param amountOutMin Minimum amount of output tokens expected
     * @param recipient Address to receive output tokens
     * @param path Encoded swap path data
     * @return amountOut Amount of output tokens received
     */
    function _buy(uint256 amountIn, uint256 amountOutMin, address recipient, bool isEth, bytes memory path)
        internal
        returns (uint256 amountOut)
    {
        // Decode swap path to determine router version
        (bytes32 swap_router_sig, bytes memory path_data) = path.decode();

        // Validate router signature
        require(
            swap_router_sig == UNISWAP_V2_ROUTER_02_SIG || swap_router_sig == UNISWAP_V3_ROUTER_02_SIG,
            "Invalid swap router"
        );

        // Get input token and handle ETH/WETH conversion
        address input_token = path_data.getInputToken(swap_router_sig == UNISWAP_V2_ROUTER_02_SIG);

        TokenHelper.convertEthToWeth(isEth, TokenInterface(input_token), amountIn);

        // Approve router to spend input tokens
        TokenHelper.approve(TokenInterface(input_token), address(uniswapV2Router02), amountIn);

        // Execute swap based on router version
        if (swap_router_sig == UNISWAP_V2_ROUTER_02_SIG) {
            // Handle Uniswap V2 style swap
            address[] memory v2_path = path_data.decodeUniswapV2Path();
            amountOut = uniswapV2Router02.swapExactTokensForTokens(amountIn, amountOutMin, v2_path, recipient);
        } else {
            // Handle Uniswap V3 style swap
            amountOut = uniswapV2Router02.exactInput(
                IUniswapV2Router02.ExactInputParams({
                    path: path_data.encodeUniswapV3Path(),
                    recipient: recipient,
                    amountIn: amountIn,
                    amountOutMinimum: amountOutMin
                })
            );
        }
    }
}
