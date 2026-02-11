// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.26;

import { IERC20 } from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import { AccessControl } from "../../lib/openzeppelin-contracts/contracts/access/AccessControl.sol";

import { IUniswapV3SwapAdapter } from "./interfaces/IUniswapV3SwapAdapter.sol";
import { IV3SwapRouter } from "./interfaces/uniswap/IV3SwapRouter.sol";

/**
 * @title  Uniswap V3 Swap Adapter
 * @author M0 Labs
 *         MetaStreet Foundation
 *         Adapted from https://github.com/metastreet-labs/metastreet-usdai-contracts/blob/main/src/swapAdapters/UniswapV3SwapAdapter.sol
 */
contract UniswapV3SwapAdapter is IUniswapV3SwapAdapter, AccessControl {
    using SafeERC20 for IERC20;

    /// @notice Fee for Uniswap V3 swap router (0.01%)
    uint24 internal constant UNISWAP_V3_FEE = 100;

    /// @notice Path address size
    uint256 internal constant PATH_ADDR_SIZE = 20;

    /// @notice Path fee size
    uint256 internal constant PATH_FEE_SIZE = 3;

    /// @notice Path next offset
    uint256 internal constant PATH_NEXT_OFFSET = PATH_ADDR_SIZE + PATH_FEE_SIZE;

    address public immutable swapRouter;

    address public immutable baseToken;

    mapping(address token => bool whitelisted) public whitelistedTokens;

    /**
     * @notice Constructs UniswapV3SwapAdapter contract
     * @param  baseToken_ The address of base token.
     * @param  swapRouter_ The address of the Uniswap V3 swap router.
     * @param  admin The address of the admin.
     * @param  tokens The list of whitelisted tokens.
     */
    constructor(address baseToken_, address swapRouter_, address admin, address[] memory tokens) {
        if ((baseToken = baseToken_) == address(0)) revert ZeroBaseToken();
        if ((swapRouter = swapRouter_) == address(0)) revert ZeroSwapRouter();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);

        for (uint256 i; i < tokens.length; i++) {
            _whitelistToken(tokens[i], true);
        }
    }

    /// @inheritdoc IUniswapV3SwapAdapter
    function swapIn(
        address inputToken,
        uint256 inputAmount,
        uint256 minBaseAmount,
        address recipient,
        bytes calldata path
    ) external returns (uint256 baseAmount) {
        _revertIfNotWhitelistedToken(inputToken);
        _revertIfZeroAmount(inputAmount);
        _revertIfInvalidSwapInPath(inputToken, path);
        _revertIfZeroRecipient(recipient);

        // Transfer token input from sender to this contract
        IERC20(inputToken).safeTransferFrom(msg.sender, address(this), inputAmount);

        address swapRouter_ = swapRouter;

        // Approve the router to spend token input
        IERC20(inputToken).forceApprove(swapRouter_, inputAmount);

        // Swap token input for base token
        if (path.length == 0) {
            IV3SwapRouter.ExactInputSingleParams memory params = IV3SwapRouter.ExactInputSingleParams({
                tokenIn: inputToken,
                tokenOut: baseToken,
                fee: UNISWAP_V3_FEE,
                recipient: recipient,
                amountIn: inputAmount,
                amountOutMinimum: minBaseAmount,
                sqrtPriceLimitX96: 0
            });

            baseAmount = IV3SwapRouter(swapRouter_).exactInputSingle(params);
        } else {
            IV3SwapRouter.ExactInputParams memory params = IV3SwapRouter.ExactInputParams({
                path: path,
                recipient: msg.sender,
                amountIn: inputAmount,
                amountOutMinimum: minBaseAmount
            });

            baseAmount = IV3SwapRouter(swapRouter_).exactInput(params);
        }
    }

    /// @inheritdoc IUniswapV3SwapAdapter
    function swapOut(
        address outputToken,
        uint256 baseAmount,
        uint256 minOutputAmount,
        address recipient,
        bytes calldata path
    ) external returns (uint256 outputAmount) {
        _revertIfNotWhitelistedToken(outputToken);
        _revertIfZeroAmount(baseAmount);
        _revertIfInvalidSwapOutPath(outputToken, path);
        _revertIfZeroRecipient(recipient);

        // Transfer token input from sender to this contract
        IERC20(baseToken).safeTransferFrom(msg.sender, address(this), baseAmount);

        // Approve the router to spend base token
        IERC20(baseToken).forceApprove(swapRouter, baseAmount);

        // Swap base token for token output
        if (path.length == 0) {
            IV3SwapRouter.ExactInputSingleParams memory params = IV3SwapRouter.ExactInputSingleParams({
                tokenIn: baseToken,
                tokenOut: outputToken,
                fee: UNISWAP_V3_FEE,
                recipient: recipient,
                amountIn: baseAmount,
                amountOutMinimum: minOutputAmount,
                sqrtPriceLimitX96: 0
            });

            outputAmount = IV3SwapRouter(swapRouter).exactInputSingle(params);
        } else {
            IV3SwapRouter.ExactInputParams memory params = IV3SwapRouter.ExactInputParams({
                path: path,
                recipient: recipient,
                amountIn: baseAmount,
                amountOutMinimum: minOutputAmount
            });

            outputAmount = IV3SwapRouter(swapRouter).exactInput(params);
        }
    }

    /// @inheritdoc IUniswapV3SwapAdapter
    function whitelistToken(address token, bool isWhitelisted) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _whitelistToken(token, isWhitelisted);
    }

    function _whitelistToken(address token, bool isWhitelisted) private {
        if (token == address(0)) revert ZeroToken();
        whitelistedTokens[token] = isWhitelisted;

        emit TokenWhitelisted(token, isWhitelisted);
    }

    /**
     * @notice Decode input and output tokens
     * @param  path Swap path
     * @return tokenInput Address of the input token
     * @return tokenOutput Address if the output token
     */
    function _decodeInputAndOutputTokens(
        bytes calldata path
    ) internal pure returns (address tokenInput, address tokenOutput) {
        // Validate path format
        if (
            (path.length < PATH_ADDR_SIZE + PATH_FEE_SIZE + PATH_ADDR_SIZE) ||
            ((path.length - PATH_ADDR_SIZE) % PATH_NEXT_OFFSET != 0)
        ) {
            revert InvalidPathFormat();
        }

        tokenInput = address(bytes20(path[:PATH_ADDR_SIZE]));

        // Calculate position of output token
        uint256 numHops = (path.length - PATH_ADDR_SIZE) / PATH_NEXT_OFFSET;
        uint256 outputTokenIndex = numHops * PATH_NEXT_OFFSET;

        tokenOutput = address(bytes20(path[outputTokenIndex:outputTokenIndex + PATH_ADDR_SIZE]));
    }

    /**
     * @dev   Reverts if not whitelisted token.
     * @param token Address of a token.
     */
    function _revertIfNotWhitelistedToken(address token) internal view {
        if (!whitelistedTokens[token]) revert NotWhitelistedToken(token);
    }

    /**
     * @dev   Reverts if `recipient` is address(0).
     * @param recipient Address of a recipient.
     */
    function _revertIfZeroRecipient(address recipient) internal pure {
        if (recipient == address(0)) revert ZeroRecipient();
    }

    /**
     * @dev   Reverts if `amount` is equal to 0.
     * @param amount Amount of token.
     */
    function _revertIfZeroAmount(uint256 amount) internal pure {
        if (amount == 0) revert ZeroAmount();
    }

    /**
     * @notice Reverts if the swap path is invalid for swapping in.
     * @param  tokenInput Address of the input token.
     * @param  path Swap path.
     */
    function _revertIfInvalidSwapInPath(address tokenInput, bytes calldata path) internal view {
        if (path.length != 0) {
            (address tokenInput_, address tokenOutput) = _decodeInputAndOutputTokens(path);
            if (tokenInput_ != tokenInput || tokenOutput != baseToken) revert InvalidPath();
        }
    }

    /**
     * @notice Reverts if the swap path is invalid for swapping out.
     * @param  tokenOutput Address of the output token.
     * @param  path Swap path.
     */
    function _revertIfInvalidSwapOutPath(address tokenOutput, bytes calldata path) internal view {
        if (path.length != 0) {
            (address tokenInput, address tokenOutput_) = _decodeInputAndOutputTokens(path);
            if (tokenInput != baseToken || tokenOutput_ != tokenOutput) revert InvalidPath();
        }
    }
}
