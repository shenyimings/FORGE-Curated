// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.26;

/**
 * @title  UniswapV3 swap adapter interface.
 * @author MetaStreet Foundation
 *         Adapted from https://github.com/metastreet-labs/metastreet-usdai-contracts/blob/main/src/swapAdapters/UniswapV3SwapAdapter.sol
 */
interface IUniswapV3SwapAdapter {
    /* ============ Events ============ */

    /**
     * @notice Emitted when a token is swapped in for base token.
     * @param inputToken The address of the input token.
     * @param inputAmount The amount of the input token swapped.
     * @param baseOutputAmount The amount of base token received from the swap.
     */
    event SwappedIn(address indexed inputToken, uint256 inputAmount, uint256 baseOutputAmount);

    /**
     * @notice Emitted when base token is swapped for the output token.
     * @param outputToken The address of the output token.
     * @param baseInputAmount The amount of base token swapped.
     * @param outputAmount The amount of the output token received from the swap.
     */
    event SwappedOut(address indexed outputToken, uint256 baseInputAmount, uint256 outputAmount);

    /**
     * @notice Emitted when a token is added or removed from the whitelist.
     * @param token The address of the token.
     * @param isWhitelisted True if the token is whitelisted, false otherwise.
     */
    event TokenWhitelisted(address indexed token, bool isWhitelisted);

    /* ============ Custom Errors ============ */

    /// @notice Thrown in the constructor if Base Token is 0x0.
    error ZeroBaseToken();

    /// @notice Thrown in the constructor if Uniswap SwapRouter is 0x0.
    error ZeroSwapRouter();

    /// @notice Thrown token address is 0x0.
    error ZeroToken();

    /// @notice Thrown if swap amount is 0.
    error ZeroAmount();

    /// @notice Thrown if recipient address is 0x0.
    error ZeroRecipient();

    /// @notice Thrown if the token is not whitelisted.
    error NotWhitelistedToken(address token);

    /// @notice Invalid path
    error InvalidPath();

    /// @notice Invalid path format
    error InvalidPathFormat();

    /* ============ Interactive Functions ============ */

    /**
     * @notice Swaps `inputToken` to base token
     * @param  inputToken    The address of the input token.
     * @param  inputAmount   The amount of the input token to swap.
     * @param  minBaseAmount The minimum amount of base token to receive.
     * @param  recipient     The address to receive base tokens.
     * @param  path          The swap path.
     */
    function swapIn(
        address inputToken,
        uint256 inputAmount,
        uint256 minBaseAmount,
        address recipient,
        bytes calldata path
    ) external returns (uint256 baseAmount);

    /**
     * @notice Swaps base token to `outputToken`
     * @param  outputToken     The address of the output token.
     * @param  baseAmount      The amount of base token to swap.
     * @param  minOutputAmount The minimum amount of output token to receive.
     * @param  recipient       The address to receive output tokens.
     * @param  path            The swap path.
     */
    function swapOut(
        address outputToken,
        uint256 baseAmount,
        uint256 minOutputAmount,
        address recipient,
        bytes calldata path
    ) external returns (uint256 outputAmount);

    /**
     * @notice Adds or removes a token from the whitelist.
     * @param  token         The address of the token.
     * @param  isWhitelisted True to whitelist the token, false otherwise.
     */
    function whitelistToken(address token, bool isWhitelisted) external;

    /* ============ View/Pure Functions ============ */

    /// @notice The address of the base token.
    function baseToken() external view returns (address baseToken);

    /// @notice The address of the Uniswap V3 swap router.
    function swapRouter() external view returns (address swapRouter);
}
