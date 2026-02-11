/* -*- c-basic-offset: 4 -*- */
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

import {IVault} from "../interfaces/IVault.sol";
import {IPermit} from "../interfaces/IPermit.sol";
import {Reward} from "../types/Intent.sol";

/**
 * @title Vault
 * @notice Escrow contract for managing cross-chain reward payments
 * @dev Implements a lifecycle-based vault that can be funded, withdrawn from, or refunded
 */
contract Vault is IVault {
    /// @notice Address of the portal contract that can call this vault
    address private immutable portal;

    using SafeERC20 for IERC20;
    using Math for uint256;

    /**
     * @notice Creates a new vault instance
     * @dev Sets the deployer (IntentSource) as the authorized portal contract
     *      Only the portal can call fund, withdraw, refund, and recover functions
     */
    constructor() {
        portal = msg.sender;
    }

    /**
     * @notice Restricts function access to only the portal contract
     * @dev Ensures only the IntentSource contract can manage vault operations
     */
    modifier onlyPortal() {
        if (msg.sender != portal) {
            revert NotPortalCaller(msg.sender);
        }

        _;
    }

    /**
     * @notice Funds the vault with tokens and native currency from the reward
     * @param reward The reward structure containing token addresses, amounts, and native value
     * @param funder Address that will provide the funding
     * @param permit Optional permit contract for gasless token approvals
     * @return fullyFunded True if the vault was fully funded, false otherwise
     */
    function fundFor(
        Reward calldata reward,
        address funder,
        IPermit permit
    ) external payable onlyPortal returns (bool fullyFunded) {
        fullyFunded = address(this).balance >= reward.nativeAmount;

        uint256 rewardsLength = reward.tokens.length;
        for (uint256 i; i < rewardsLength; ++i) {
            IERC20 token = IERC20(reward.tokens[i].token);

            uint256 remaining = _fundFromPermit(
                funder,
                token,
                reward.tokens[i].amount,
                permit
            );
            remaining = _fundFrom(funder, token, remaining);

            fullyFunded = fullyFunded && remaining == 0;
        }
    }

    /**
     * @notice Withdraws rewards from the vault to the specified claimant
     * @param reward The reward structure defining what to withdraw
     * @param claimant Address that will receive the withdrawn rewards
     */
    function withdraw(
        Reward calldata reward,
        address claimant
    ) external onlyPortal {
        uint256 rewardsLength = reward.tokens.length;
        for (uint256 i; i < rewardsLength; ++i) {
            IERC20 token = IERC20(reward.tokens[i].token);
            uint256 amount = reward.tokens[i].amount.min(
                token.balanceOf(address(this))
            );

            if (amount > 0) {
                token.safeTransfer(claimant, amount);
            }
        }

        uint256 nativeAmount = address(this).balance.min(reward.nativeAmount);
        if (nativeAmount == 0) {
            return;
        }

        (bool success, ) = claimant.call{value: nativeAmount}("");
        if (!success) {
            revert NativeTransferFailed(claimant, nativeAmount);
        }
    }

    /**
     * @notice Refunds all vault contents to a specified address
     * @param reward The reward structure containing token information
     * @param refundee Address to receive the refunded rewards
     */
    function refund(Reward calldata reward, address refundee) external onlyPortal {
        uint256 rewardsLength = reward.tokens.length;
        for (uint256 i; i < rewardsLength; ++i) {
            IERC20 token = IERC20(reward.tokens[i].token);
            uint256 amount = token.balanceOf(address(this));

            if (amount > 0) {
                token.safeTransfer(refundee, amount);
            }
        }

        uint256 nativeAmount = address(this).balance;
        if (nativeAmount == 0) {
            return;
        }

        (bool success, ) = refundee.call{value: nativeAmount}("");
        if (!success) {
            revert NativeTransferFailed(refundee, nativeAmount);
        }
    }

    /**
     * @notice Recovers tokens that are not part of the reward to the creator
     * @param refundee Address to receive the recovered tokens
     * @param token Address of the token to recover (must not be a reward token)
     */
    function recover(address refundee, address token) external onlyPortal {
        IERC20 tokenContract = IERC20(token);
        uint256 balance = tokenContract.balanceOf(address(this));

        if (balance == 0) {
            revert ZeroRecoverTokenBalance(token);
        }

        tokenContract.safeTransfer(refundee, balance);
    }

    /**
     * @notice Internal function to fund vault with tokens using standard ERC20 transfers
     * @param funder Address providing the tokens
     * @param token ERC20 token contract
     * @param remainingAmount Remaining amount needed to fully fund the reward
     * @return uint256 Remaining amount needed to fully fund the reward
     */
    function _fundFrom(
        address funder,
        IERC20 token,
        uint256 remainingAmount
    ) internal returns (uint256) {
        if (remainingAmount == 0) {
            return 0;
        }

        uint256 allowance = token.allowance(funder, address(this));
        uint256 funderBalance = token.balanceOf(funder);

        uint256 transferAmount = remainingAmount.min(funderBalance).min(
            allowance
        );

        if (transferAmount > 0) {
            token.safeTransferFrom(funder, address(this), transferAmount);
        }

        return remainingAmount - transferAmount;
    }

    /**
     * @notice Internal function to fund vault using permit-based transfers
     * @param funder Address providing the tokens
     * @param token ERC20 token contract
     * @param rewardAmount Required token amount for the reward
     * @param permit Permit contract for gasless approvals
     * @return uint256 Remaining amount needed to fully fund the reward
     */
    function _fundFromPermit(
        address funder,
        IERC20 token,
        uint256 rewardAmount,
        IPermit permit
    ) internal returns (uint256) {
        uint256 balance = token.balanceOf(address(this));

        if (balance >= rewardAmount) {
            return 0;
        }

        if (address(permit) == address(0)) {
            return rewardAmount - balance;
        }

        (uint160 allowance, , ) = permit.allowance(
            funder,
            address(token),
            address(this)
        );
        uint256 funderBalance = token.balanceOf(funder);

        uint256 transferAmount = (rewardAmount - balance)
            .min(funderBalance)
            .min(uint256(allowance));

        if (transferAmount > 0) {
            permit.transferFrom(
                funder,
                address(this),
                uint160(transferAmount),
                address(token)
            );
        }

        return rewardAmount - token.balanceOf(address(this));
    }
}
