// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.26;

/**
 * @title  Swap Facility interface.
 * @author M0 Labs
 */
interface ISwapFacility {
    /* ============ Events ============ */

    event Swapped(address indexed extensionIn, address indexed extensionOut, uint256 amount, address recipient);

    event SwappedInM(address indexed extensionOut, uint256 amount, address recipient);

    event SwappedOutM(address indexed extensionIn, uint256 amount, address recipient);

    /* ============ Custom Errors ============ */

    /// @notice Thrown in the constructor if $M Token is 0x0.
    error ZeroMToken();

    /// @notice Thrown in the constructor if Registrar is 0x0.
    error ZeroRegistrar();

    /// @notice Thrown in the constructor if SwapAdapter is 0x0.
    error ZeroSwapAdapter();

    /// @notice Thrown in `swap` and `swapM` functions if the extension is not TTG approved earner.
    error NotApprovedExtension(address extension);

    /// @notice Thrown in `swapOutM` and `swapOutMWithPermit` functions if the caller is not approved swapper.
    error NotApprovedSwapper(address account);

    /* ============ Interactive Functions ============ */

    /**
     * @notice Swaps one $M Extension to another.
     * @param  extensionIn  The address of the $M Extension to swap from.
     * @param  extensionOut The address of the $M Extension to swap to.
     * @param  amount       The amount to swap.
     * @param  recipient    The address to receive the swapped $M Extension tokens.
     */
    function swap(address extensionIn, address extensionOut, uint256 amount, address recipient) external;

    /**
     * @notice Swaps $M token to $M Extension.
     * @param  extensionOut The address of the M Extension to swap to.
     * @param  amount       The amount of $M token to swap.
     * @param  recipient    The address to receive the swapped $M Extension tokens.
     */
    function swapInM(address extensionOut, uint256 amount, address recipient) external;

    /**
     * @notice Swaps $M token to $M Extension using permit.
     * @param  extensionOut The address of the M Extension to swap to.
     * @param  amount       The amount of $M token to swap.
     * @param  recipient    The address to receive the swapped $M Extension tokens.
     * @param  deadline     The last timestamp where the signature is still valid.
     * @param  v            An ECDSA secp256k1 signature parameter (EIP-2612 via EIP-712).
     * @param  r            An ECDSA secp256k1 signature parameter (EIP-2612 via EIP-712).
     * @param  s            An ECDSA secp256k1 signature parameter (EIP-2612 via EIP-712).
     */
    function swapInMWithPermit(
        address extensionOut,
        uint256 amount,
        address recipient,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    /**
     * @notice Swaps $M token to $M Extension using permit.
     * @param  extensionOut The address of the M Extension to swap to.
     * @param  amount       The amount of $M token to swap.
     * @param  recipient    The address to receive the swapped $M Extension tokens.
     * @param  deadline     The last timestamp where the signature is still valid.
     * @param  signature    An arbitrary signature (EIP-712).
     */
    function swapInMWithPermit(
        address extensionOut,
        uint256 amount,
        address recipient,
        uint256 deadline,
        bytes calldata signature
    ) external;

    /**
     * @notice Swaps $M Extension to $M token.
     * @param  extensionIn The address of the $M Extension to swap from.
     * @param  amount      The amount of $M Extension tokens to swap.
     * @param  recipient   The address to receive $M tokens.
     */
    function swapOutM(address extensionIn, uint256 amount, address recipient) external;

    /**
     * @notice Swaps an external token (e.g. USDC) to $M Extension token.
     * @param  tokenIn      The address of the external token to swap from.
     * @param  amountIn     The amount of external tokens to swap.
     * @param  extensionOut The address of the $M Extension to swap to.
     * @param  minAmountOut The minimum amount of $M Extension tokens to receive.
     * @param  recipient    The address to receive $M Extension tokens.
     * @param  path         The multi-hop Uniswap path. Must be empty for direct pairs.
     */
    function swapInToken(
        address tokenIn,
        uint256 amountIn,
        address extensionOut,
        uint256 minAmountOut,
        address recipient,
        bytes calldata path
    ) external;

    /**
     * @notice Swaps $M Extension token to an external token (e.g. USDC).
     * @param  extensionIn  The address of the $M Extension to swap from.
     * @param  amountIn     The amount of $M Extension tokens to swap.
     * @param  tokenOut     The address of the external token to swap to.
     * @param  minAmountOut The minimum amount of external tokens to receive.
     * @param  recipient    The address to receive external tokens.
     * @param  path         The multi-hop Uniswap path. Must be empty for direct pairs.
     */
    function swapOutToken(
        address extensionIn,
        uint256 amountIn,
        address tokenOut,
        uint256 minAmountOut,
        address recipient,
        bytes calldata path
    ) external;

    /* ============ View/Pure Functions ============ */

    /// @notice The address of the $M Token contract.
    function mToken() external view returns (address mToken);

    /// @notice The address of the Registrar.
    function registrar() external view returns (address registrar);

    /// @notice The address of the UniswapV3 Swap Adapter contract.
    function swapAdapter() external view returns (address registrar);

    /**
     * @notice Returns the address that called `swap` or `swapM`
     * @dev    Must be used instead of `msg.sender` in $M Extensions contracts to get the original sender.
     */
    function msgSender() external view returns (address msgSender);
}
