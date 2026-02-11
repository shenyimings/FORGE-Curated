// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ISTETH} from "../tokens/ISTETH.sol";
import {IWETH} from "../tokens/IWETH.sol";
import {IWSTETH} from "../tokens/IWSTETH.sol";

import {IERC4626Vault} from "../vaults/IERC4626Vault.sol";

/**
 * @title IEthWrapper
 * @notice Interface for wrapping and converting input tokens (WETH, wstETH, stETH, ETH) into wstETH and depositing them into an ERC4626Vault.
 * @dev This contract acts as an intermediary to handle deposits using various ETH derivatives and wraps them into wstETH for ERC4626 vault deposits.
 */
interface IEthWrapper {
    /**
     * @notice Returns the address of the WETH token.
     * @return The address of WETH.
     */
    function WETH() external view returns (address);

    /**
     * @notice Returns the address of the wstETH token.
     * @return The address of wstETH.
     */
    function wstETH() external view returns (address);

    /**
     * @notice Returns the address of the stETH token.
     * @return The address of stETH.
     */
    function stETH() external view returns (address);

    /**
     * @notice Returns the address used to represent ETH (0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE).
     * @return The special address representing ETH.
     */
    function ETH() external view returns (address);

    /**
     * @notice Deposits a specified `amount` of the `depositToken` into the provided `vault`, crediting the specified `receiver` with shares.
     * @param depositToken The address of the token being deposited (WETH, wstETH, stETH, or ETH).
     * @param amount The amount of `depositToken` to deposit.
     * @param vault The address of the ERC4626 vault where the deposit will be made.
     * @param receiver The address of the account receiving shares from the deposit.
     * @param referral The address of the referral, if applicable.
     * @return shares The amount of vault shares received after the deposit.
     *
     * @dev The `depositToken` must be one of WETH, wstETH, stETH, or ETH.
     * @dev If `depositToken` is ETH, the `amount` must match `msg.value`.
     * @dev If `depositToken` is not ETH, `msg.value` must be zero and the specified `amount` must be transferred from the sender.
     */
    function deposit(
        address depositToken,
        uint256 amount,
        address vault,
        address receiver,
        address referral
    ) external payable returns (uint256 shares);
}
