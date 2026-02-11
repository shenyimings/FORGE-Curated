// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

/// @notice An interface for CoW Protocol's settlement contract that only
/// enumerates the functions and types needed for this project.
/// For more information, see the project's repository:
/// <https://github.com/cowprotocol/contracts/blob/9c1984b864d0a6703a877a088be6dac56450808c/src/contracts/GPv2Settlement.sol>
/// The code and comments have been mostly copied from the linked resources.
interface ICowSettlement {
    /// @notice A struct representing a trade to be executed as part a batch
    /// settlement.
    /// @dev See <https://github.com/cowprotocol/contracts/blob/9c1984b864d0a6703a877a088be6dac56450808c/src/contracts/libraries/GPv2Trade.sol#L14-L28>.
    struct Trade {
        uint256 sellTokenIndex;
        uint256 buyTokenIndex;
        address receiver;
        uint256 sellAmount;
        uint256 buyAmount;
        uint32 validTo;
        bytes32 appData;
        uint256 feeAmount;
        uint256 flags;
        uint256 executedAmount;
        bytes signature;
    }

    /// @notice Interaction data for performing arbitrary contract interactions.
    /// Submitted to [`GPv2Settlement.settle`] for code execution.
    /// @dev See <https://github.com/cowprotocol/contracts/blob/9c1984b864d0a6703a877a088be6dac56450808c/src/contracts/libraries/GPv2Interaction.sol#L7-L13>.
    struct Interaction {
        address target;
        uint256 value;
        bytes callData;
    }

    /// @notice The authenticator is used to determine who can call the settle
    /// function. That is, only authorized solvers have the ability to invoke
    /// settlements. Any valid authenticator implements an isSolver method
    /// called by the onlySolver modifier below.
    /// @dev See <https://github.com/cowprotocol/contracts/blob/9c1984b864d0a6703a877a088be6dac56450808c/src/contracts/GPv2Settlement.sol#L28-L32>.
    function authenticator() external returns (address);

    /// @notice Settle the specified orders at a clearing price. Note that it is
    /// the responsibility of the caller to ensure that all GPv2 invariants are
    /// upheld for the input settlement, otherwise this call will revert.
    /// Namely:
    /// - All orders are valid and signed
    /// - Accounts have sufficient balance and approval.
    /// - Settlement contract has sufficient balance to execute trades. Note
    ///   this implies that the accumulated fees held in the contract can also
    ///   be used for settlement. This is OK since:
    ///   - Solvers need to be authorized
    ///   - Misbehaving solvers will be slashed for abusing accumulated fees for
    ///     settlement
    ///   - Critically, user orders are entirely protected
    ///
    /// @param tokens An array of ERC20 tokens to be traded in the settlement.
    /// Trades encode tokens as indices into this array.
    /// @param clearingPrices An array of clearing prices where the `i`-th price
    /// is for the `i`-th token in the [`tokens`] array.
    /// @param trades Trades for signed orders.
    /// @param interactions Smart contract interactions split into three
    /// separate lists to be run before the settlement, during the settlement
    /// and after the settlement respectively.
    /// @dev See <https://github.com/cowprotocol/contracts/blob/9c1984b864d0a6703a877a088be6dac56450808c/src/contracts/GPv2Settlement.sol#L99-L126>.
    function settle(
        address[] calldata tokens,
        uint256[] calldata clearingPrices,
        Trade[] calldata trades,
        Interaction[][3] calldata interactions
    ) external;
}
