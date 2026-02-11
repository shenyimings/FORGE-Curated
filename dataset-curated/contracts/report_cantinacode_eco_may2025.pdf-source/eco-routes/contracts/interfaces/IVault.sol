/* -*- c-basic-offset: 4 -*- */
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Reward} from "../types/Intent.sol";
import {IPermit} from "./IPermit.sol";

/**
 * @title IVault
 * @notice Interface for Vault contract that manages reward escrow functionality
 * @dev Handles funding, withdrawal, and refund operations for cross-chain rewards
 */
interface IVault {
    /// @notice Thrown when caller is not the portal contract
    error NotPortalCaller(address caller);

    /// @notice Thrown when attempting to recover a token with zero balance
    error ZeroRecoverTokenBalance(address token);

    /// @notice Thrown when native token transfer fails
    error NativeTransferFailed(address to, uint256 amount);

    /**
     * @notice Funds the vault with reward tokens and native currency
     * @param reward The reward structure containing tokens and amounts
     * @param funder Address providing the funding
     * @param permit Optional permit contract for token transfers
     * @return fullyFunded True if vault was successfully fully funded
     */
    function fundFor(
        Reward calldata reward,
        address funder,
        IPermit permit
    ) external payable returns (bool fullyFunded);

    /**
     * @notice Withdraws rewards from the vault to the claimant
     * @param reward The reward structure to withdraw
     * @param claimant Address that will receive the rewards
     */
    function withdraw(Reward calldata reward, address claimant) external;

    /**
     * @notice Refunds rewards to a specified address
     * @param reward The reward structure to refund
     * @param refundee Address to receive the refunded rewards
     */
    function refund(Reward calldata reward, address refundee) external;

    /**
     * @notice Recovers tokens that are not part of the reward to the creator
     * @param refundee Address to receive the recovered tokens
     * @param token Address of the token to recover (must not be a reward token)
     */
    function recover(address refundee, address token) external;
}
