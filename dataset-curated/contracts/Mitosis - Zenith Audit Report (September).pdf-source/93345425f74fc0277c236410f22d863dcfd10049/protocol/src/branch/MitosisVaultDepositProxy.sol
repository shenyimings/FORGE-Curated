// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.28;

import { SafeERC20 } from '@oz/token/ERC20/utils/SafeERC20.sol';
import { Address } from '@oz/utils/Address.sol';
import { Context } from '@oz/utils/Context.sol';
import { ReentrancyGuard } from '@oz/utils/ReentrancyGuard.sol';

import { IMitosisVault } from '../interfaces/branch/IMitosisVault.sol';
import { INativeWrappedToken } from '../interfaces/branch/INativeWrappedToken.sol';
import { StdError } from '../lib/StdError.sol';

/**
 * @title MitosisVaultDepositProxy
 * @author Mitosis Foundation
 * @notice A proxy contract that enables native ETH deposits to MitosisVault by automatically
 *         wrapping ETH to WETH and handling the deposit process with proper gas management.
 * @dev This contract acts as a stateless proxy that:
 *      - Wraps native ETH to WETH
 *      - Approves the vault to spend WETH
 *      - Calls the vault's deposit function with remaining ETH for gas
 *      - Returns excess ETH to the user
 *      - Provides reentrancy protection and secure context management
 */
contract MitosisVaultDepositProxy is ReentrancyGuard, Context {
  using Address for address payable;
  using SafeERC20 for INativeWrappedToken;

  //=========== NOTE: STRUCT DEFINITIONS ===========//

  /**
   * @notice Execution context for tracking the current operation
   * @param sender The original caller of the deposit function
   * @param vault The vault address being deposited to
   */
  struct ExecutionContext {
    address sender;
    address vault;
  }

  //=========== NOTE: STATE VARIABLES ===========//

  /// @dev The wrapped native token contract (e.g., WETH) - set once in constructor
  address private immutable _nativeWrappedToken;

  /// @dev Current execution context, used for secure receive() handling
  ExecutionContext private _ctx;

  //=========== NOTE: EVENTS ===========//

  /**
   * @notice Emitted when a native deposit is successfully completed
   * @param vault The vault that received the deposit
   * @param to The recipient address for the deposit
   * @param amount The amount of native tokens deposited
   * @param excessReturned The amount of excess ETH returned to sender
   */
  event NativeDeposited(address indexed vault, address indexed to, uint256 amount, uint256 excessReturned);

  /**
   * @notice Emitted when a native deposit with VLF supply is successfully completed
   * @param vault The vault that received the deposit
   * @param to The recipient address for the deposit
   * @param hubVLFVault The VLF vault address
   * @param amount The amount of native tokens deposited
   * @param excessReturned The amount of excess ETH returned to sender
   */
  event NativeDepositedWithVLF(
    address indexed vault, address indexed to, address indexed hubVLFVault, uint256 amount, uint256 excessReturned
  );

  //=========== NOTE: CONSTRUCTOR ===========//

  /**
   * @notice Initializes the deposit proxy with the native wrapped token address
   * @param nativeWrappedToken_ The address of the wrapped native token (e.g., WETH)
   * @dev Validates that the provided address is not zero to prevent misconfiguration
   */
  constructor(address nativeWrappedToken_) {
    require(nativeWrappedToken_ != address(0), StdError.ZeroAddress('nativeWrappedToken'));
    _nativeWrappedToken = nativeWrappedToken_;
  }

  //=========== NOTE: MODIFIERS ===========//

  /**
   * @notice Sets up execution context for secure ETH handling during deposit operations
   * @param vault The vault address for this deposit operation
   * @dev This modifier:
   *      - Records the sender and vault for the current operation
   *      - Enables secure receive() function operation
   *      - Cleans up context after execution to prevent reuse
   */
  modifier ctx(address vault) {
    _ctx = ExecutionContext({ sender: _msgSender(), vault: vault });

    _;

    delete _ctx;
  }

  //=========== NOTE: FALLBACK FUNCTIONS ===========//

  /**
   * @notice Fallback function that rejects all calls with data
   * @dev Always reverts to prevent accidental function calls or ETH loss
   */
  fallback() external payable {
    revert StdError.Unauthorized();
  }

  /**
   * @notice Receive function for handling ETH returns during deposit operations
   * @dev This function:
   *      - Only operates during valid execution context (during deposit)
   *      - Prevents unauthorized ETH deposits
   */
  receive() external payable {
    require(_ctx.sender != address(0) && _ctx.vault != address(0), StdError.Unauthorized());
  }

  //=========== NOTE: VIEW FUNCTIONS ===========//

  /**
   * @notice Returns the address of the native wrapped token
   * @return The address of the wrapped native token contract
   */
  function nativeWrappedToken() external view returns (address) {
    return _nativeWrappedToken;
  }

  //=========== NOTE: DEPOSIT FUNCTIONS ===========//

  /**
   * @notice Deposits native ETH to a MitosisVault by wrapping to WETH
   * @param vault The MitosisVault contract to deposit into
   * @param to The recipient address for the deposit
   * @param amount The amount of native ETH to deposit (must be <= msg.value)
   * @dev This function:
   *      - Validates input parameters and sufficient ETH sent
   *      - Wraps the specified amount of ETH to WETH
   *      - Approves the vault to spend WETH
   *      - Calls vault.deposit() with remaining ETH for gas fees
   *      - Resets approval and explicitly returns any excess ETH to sender
   *      - Emits NativeDeposited event with excess amount for tracking
   * @custom:security Reentrancy protection via nonReentrant modifier
   * @custom:security Context protection via ctx modifier
   * @custom:security Explicit excess ETH return prevents ETH being stuck
   */
  function depositNative(address vault, address to, uint256 amount) external payable nonReentrant ctx(vault) {
    // Input validation
    require(msg.value >= amount, StdError.InvalidParameter('msg.value'));
    require(to != address(0), StdError.ZeroAddress('to'));
    require(amount > 0, StdError.ZeroAmount());

    INativeWrappedToken native = INativeWrappedToken(_nativeWrappedToken);

    // Wrap ETH to WETH
    native.deposit{ value: amount }();

    // Approve vault to spend WETH
    native.forceApprove(vault, amount);

    // Deposit to vault with remaining ETH for gas
    IMitosisVault(vault).deposit{ value: msg.value - amount }(address(native), to, amount);

    // Reset approval for security
    native.forceApprove(vault, 0);

    // Calculate and emit excess returned
    uint256 excessReturned = address(this).balance;
    if (excessReturned > 0) payable(_ctx.sender).sendValue(excessReturned);

    emit NativeDeposited(vault, to, amount, excessReturned);
  }

  /**
   * @notice Deposits native ETH to a MitosisVault with VLF supply by wrapping to WETH
   * @param vault The MitosisVault contract to deposit into
   * @param to The recipient address for the deposit
   * @param hubVLFVault The VLF vault address for yield strategy
   * @param amount The amount of native ETH to deposit (must be <= msg.value)
   * @dev This function:
   *      - Validates input parameters and sufficient ETH sent
   *      - Wraps the specified amount of ETH to WETH
   *      - Approves the vault to spend WETH
   *      - Calls vault.depositWithSupplyVLF() with remaining ETH for gas
   *      - Resets approval and explicitly returns any excess ETH to sender
   *      - Emits NativeDepositedWithVLF event with excess amount for tracking
   * @custom:security Reentrancy protection via nonReentrant modifier
   * @custom:security Context protection via ctx modifier
   * @custom:security Explicit excess ETH return prevents ETH being stuck
   */
  function depositNativeWithSupplyVLF(address vault, address to, address hubVLFVault, uint256 amount)
    external
    payable
    nonReentrant
    ctx(vault)
  {
    // Input validation
    require(msg.value >= amount, StdError.InvalidParameter('msg.value'));
    require(to != address(0), StdError.ZeroAddress('to'));
    require(hubVLFVault != address(0), StdError.ZeroAddress('hubVLFVault'));
    require(amount > 0, StdError.ZeroAmount());

    INativeWrappedToken native = INativeWrappedToken(_nativeWrappedToken);

    // Wrap ETH to WETH
    native.deposit{ value: amount }();

    // Approve vault to spend WETH
    native.forceApprove(vault, amount);

    // Deposit to vault with VLF supply and remaining ETH for gas
    IMitosisVault(vault).depositWithSupplyVLF{ value: msg.value - amount }(address(native), to, hubVLFVault, amount);

    // Reset approval for security
    native.forceApprove(vault, 0);

    // Calculate and emit excess returned
    uint256 excessReturned = address(this).balance;
    if (excessReturned > 0) payable(_ctx.sender).sendValue(excessReturned);

    emit NativeDepositedWithVLF(vault, to, hubVLFVault, amount, excessReturned);
  }
}
