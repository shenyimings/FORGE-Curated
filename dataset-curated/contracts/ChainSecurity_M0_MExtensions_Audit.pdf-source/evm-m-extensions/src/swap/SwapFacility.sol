// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.26;

import { IERC20 } from "../../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "../../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {
    AccessControlUpgradeable
} from "../../lib/common/lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import { Lock } from "../../lib/universal-router/contracts/base/Lock.sol";

import { IMTokenLike } from "../interfaces/IMTokenLike.sol";
import { IMExtension } from "../interfaces/IMExtension.sol";

import { ISwapFacility } from "./interfaces/ISwapFacility.sol";
import { IRegistrarLike } from "./interfaces/IRegistrarLike.sol";
import { IUniswapV3SwapAdapter } from "./interfaces/IUniswapV3SwapAdapter.sol";

/**
 * @title  Swap Facility
 * @notice A contract responsible for swapping between $M Extensions.
 * @author M0 Labs
 */
contract SwapFacility is ISwapFacility, AccessControlUpgradeable, Lock {
    using SafeERC20 for IERC20;

    bytes32 public constant EARNERS_LIST_IGNORED_KEY = "earners_list_ignored";
    bytes32 public constant EARNERS_LIST_NAME = "earners";
    bytes32 public constant M_SWAPPER_ROLE = keccak256("M_SWAPPER_ROLE");

    /// @inheritdoc ISwapFacility
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    address public immutable mToken;

    /// @inheritdoc ISwapFacility
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    address public immutable registrar;

    /// @inheritdoc ISwapFacility
    address public immutable swapAdapter;

    /**
     * @notice Constructs SwapFacility Implementation contract
     * @dev    Sets immutable storage.
     * @param  mToken_      The address of $M token.
     * @param  registrar_   The address of Registrar.
     * @param  swapAdapter_ The address of Uniswap swap adapter.
     */
    constructor(address mToken_, address registrar_, address swapAdapter_) {
        _disableInitializers();

        if ((mToken = mToken_) == address(0)) revert ZeroMToken();
        if ((registrar = registrar_) == address(0)) revert ZeroRegistrar();
        if ((swapAdapter = swapAdapter_) == address(0)) revert ZeroSwapAdapter();
    }

    /* ============ Initializer ============ */

    /**
     * @notice Initializes SwapFacility Proxy.
     * @param  admin Address of the SwapFacility admin.
     */
    function initialize(address admin) external initializer {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /* ============ Interactive Functions ============ */

    /// @inheritdoc ISwapFacility
    function swap(address extensionIn, address extensionOut, uint256 amount, address recipient) external isNotLocked {
        // NOTE: Amount and recipient validation is performed in Extensions.
        _revertIfNotApprovedExtension(extensionIn);
        _revertIfNotApprovedExtension(extensionOut);

        _swap(extensionIn, extensionOut, amount, recipient);

        emit Swapped(extensionIn, extensionOut, amount, recipient);
    }

    /// @inheritdoc ISwapFacility
    function swapInM(address extensionOut, uint256 amount, address recipient) external isNotLocked {
        // NOTE: Amount and recipient validation is performed in Extensions.
        _revertIfNotApprovedExtension(extensionOut);

        _swapInM(extensionOut, amount, recipient);
    }

    /// @inheritdoc ISwapFacility
    function swapInMWithPermit(
        address extensionOut,
        uint256 amount,
        address recipient,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external isNotLocked {
        _revertIfNotApprovedExtension(extensionOut);

        try IMTokenLike(mToken).permit(msgSender(), address(this), amount, deadline, v, r, s) {} catch {}

        _swapInM(extensionOut, amount, recipient);
    }

    /// @inheritdoc ISwapFacility
    function swapInMWithPermit(
        address extensionOut,
        uint256 amount,
        address recipient,
        uint256 deadline,
        bytes calldata signature
    ) external isNotLocked {
        _revertIfNotApprovedExtension(extensionOut);

        try IMTokenLike(mToken).permit(msgSender(), address(this), amount, deadline, signature) {} catch {}

        _swapInM(extensionOut, amount, recipient);
    }

    /// @inheritdoc ISwapFacility
    function swapOutM(address extensionIn, uint256 amount, address recipient) external isNotLocked {
        // NOTE: Amount and recipient validation is performed in Extensions.
        _revertIfNotApprovedExtension(extensionIn);
        _revertIfNotApprovedSwapper(msgSender());

        _swapOutM(extensionIn, amount, recipient);
    }

    /// @inheritdoc ISwapFacility
    function swapInToken(
        address tokenIn,
        uint256 amountIn,
        address extensionOut,
        uint256 minAmountOut,
        address recipient,
        bytes calldata path
    ) external isNotLocked {
        _revertIfNotApprovedExtension(extensionOut);

        // Transfer input token to SwapFacility for future transfer to Swap Adapter.
        IERC20(tokenIn).safeTransferFrom(msgSender(), address(this), amountIn);

        // Approve Swap Adapter to spend input token.
        IERC20(tokenIn).forceApprove(swapAdapter, amountIn);

        // Swap input token for base token in Uniswap pool
        uint256 amountOut = IUniswapV3SwapAdapter(swapAdapter).swapIn(
            tokenIn,
            amountIn,
            minAmountOut,
            address(this),
            path
        );

        address baseToken = IUniswapV3SwapAdapter(swapAdapter).baseToken();
        // If extensionOut is baseToken, transfer to the recipient directly
        if (extensionOut == baseToken) {
            IERC20(baseToken).transfer(recipient, amountOut);
        } else {
            // Otherwise, swap the baseToken to extensionOut
            _swap(baseToken, extensionOut, amountOut, recipient);
        }

        emit Swapped(tokenIn, extensionOut, amountOut, recipient);
    }

    /// @inheritdoc ISwapFacility
    function swapOutToken(
        address extensionIn,
        uint256 amountIn,
        address tokenOut,
        uint256 minAmountOut,
        address recipient,
        bytes calldata path
    ) external isNotLocked {
        _revertIfNotApprovedExtension(extensionIn);

        address baseToken = IUniswapV3SwapAdapter(swapAdapter).baseToken();
        if (extensionIn == baseToken) {
            // If extensionIn is baseToken (Wrapped $M), transfer it to SwapFacility
            IERC20(baseToken).safeTransferFrom(msgSender(), address(this), amountIn);
        } else {
            uint256 balanceBefore = IERC20(baseToken).balanceOf(address(this));

            // Otherwise, swap the extensionIn to baseToken
            _swap(extensionIn, baseToken, amountIn, address(this));

            // Calculate amountIn as the difference in balance to account for rounding errors
            amountIn = IERC20(baseToken).balanceOf(address(this)) - balanceBefore;
        }

        // Approve Swap Adapter to spend baseToken (Wrapped $M).
        IERC20(baseToken).forceApprove(swapAdapter, amountIn);

        // Swap baseToken in Uniswap pool for output token
        uint256 amountOut = IUniswapV3SwapAdapter(swapAdapter).swapOut(
            tokenOut,
            amountIn,
            minAmountOut,
            recipient,
            path
        );

        emit Swapped(extensionIn, tokenOut, amountOut, recipient);
    }

    /* ============ View/Pure Functions ============ */

    /// @inheritdoc ISwapFacility
    function msgSender() public view returns (address) {
        return _getLocker();
    }

    /* ============ Private Interactive Functions ============ */

    /**
     * @notice Swaps one $M Extension to another.
     * @param  extensionIn  The address of the $M Extension to swap from.
     * @param  extensionOut The address of the $M Extension to swap to.
     * @param  amount       The amount to swap.
     * @param  recipient    The address to receive the swapped $M Extension tokens.
     */
    function _swap(address extensionIn, address extensionOut, uint256 amount, address recipient) private {
        uint256 balanceBefore = _mBalanceOf(address(this));

        // Recipient parameter is ignored in the MExtension, keeping it for backward compatibility.
        IMExtension(extensionIn).unwrap(address(this), amount);

        // NOTE: Calculate amount as $M Token balance difference
        //       to account for rounding errors.
        amount = _mBalanceOf(address(this)) - balanceBefore;

        IERC20(mToken).approve(extensionOut, amount);
        IMExtension(extensionOut).wrap(recipient, amount);
    }

    /**
     * @notice Swaps $M token to $M Extension.
     * @param  extensionOut The address of the M Extension to swap to.
     * @param  amount       The amount of $M token to swap.
     * @param  recipient    The address to receive the swapped $M Extension tokens.
     */
    function _swapInM(address extensionOut, uint256 amount, address recipient) private {
        IERC20(mToken).transferFrom(msgSender(), address(this), amount);
        IERC20(mToken).approve(extensionOut, amount);
        IMExtension(extensionOut).wrap(recipient, amount);

        emit SwappedInM(extensionOut, amount, recipient);
    }

    /**
     * @notice Swaps $M Extension to $M token.
     * @param  extensionIn The address of the $M Extension to swap from.
     * @param  amount      The amount of $M Extension tokens to swap.
     * @param  recipient   The address to receive $M tokens.
     */
    function _swapOutM(address extensionIn, uint256 amount, address recipient) private {
        uint256 balanceBefore = _mBalanceOf(address(this));

        // Recipient parameter is ignored in the MExtension, keeping it for backward compatibility.
        IMExtension(extensionIn).unwrap(address(this), amount);

        // NOTE: Calculate amount as $M Token balance difference
        //       to account for rounding errors.
        amount = _mBalanceOf(address(this)) - balanceBefore;
        IERC20(mToken).transfer(recipient, amount);

        emit SwappedOutM(extensionIn, amount, recipient);
    }

    /**
     * @dev    Returns the M Token balance of `account`.
     * @param  account The account being queried.
     * @return balance The M Token balance of the account.
     */
    function _mBalanceOf(address account) internal view returns (uint256) {
        return IMTokenLike(mToken).balanceOf(account);
    }

    /* ============ Private View/Pure Functions ============ */

    /**
     * @dev   Reverts if `extension` is not an approved earner.
     * @param extension Address of an extension.
     */
    function _revertIfNotApprovedExtension(address extension) private view {
        if (!_isApprovedEarner(extension)) revert NotApprovedExtension(extension);
    }

    /**
     * @dev   Reverts if `account` is not an approved M token swapper.
     * @param account Address of an extension.
     */
    function _revertIfNotApprovedSwapper(address account) private view {
        if (!hasRole(M_SWAPPER_ROLE, account)) revert NotApprovedSwapper(account);
    }

    /**
     * @dev    Checks if the given extension is an approved earner.
     * @param  extension Address of the extension to check.
     * @return True if the extension is an approved earner, false otherwise.
     */
    function _isApprovedEarner(address extension) private view returns (bool) {
        return
            IRegistrarLike(registrar).get(EARNERS_LIST_IGNORED_KEY) != bytes32(0) ||
            IRegistrarLike(registrar).listContains(EARNERS_LIST_NAME, extension);
    }
}
