/* -*- c-basic-offset: 4 -*- */
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IIntentSource} from "./interfaces/IIntentSource.sol";
import {IVault} from "./interfaces/IVault.sol";
import {IPermit} from "./interfaces/IPermit.sol";

import {Reward} from "./types/Intent.sol";

/**
 * @title Vault
 * @notice A self-destructing contract that handles reward distribution for intents
 * @dev Created by IntentSource for each intent, handles token and native currency transfers,
 * then self-destructs after distributing rewards
 */
contract Vault is IVault {
    using SafeERC20 for IERC20;

    /**
     * @notice Creates and immediately executes reward distribution
     * @dev Contract self-destructs after execution
     */
    constructor(bytes32 intentHash, Reward memory reward) {
        IIntentSource intentSource = IIntentSource(msg.sender);
        VaultState memory state = intentSource.getVaultState(intentHash);

        if (state.mode == uint8(VaultMode.Fund)) {
            _fundIntent(intentSource, intentHash, state, reward);
        } else if (state.mode == uint8(VaultMode.Claim)) {
            _processRewardTokens(reward, state.target);
            _processNativeReward(reward, state.target);
        } else if (state.mode == uint8(VaultMode.Refund)) {
            _processRewardTokens(reward, reward.creator);
        } else if (state.mode == uint8(VaultMode.RecoverToken)) {
            _recoverToken(state.target, reward.creator);
        }

        selfdestruct(payable(reward.creator));
    }

    /**
     * @dev Funds the intent with required tokens
     */
    function _fundIntent(
        IIntentSource intentSource,
        bytes32 intentHash,
        VaultState memory state,
        Reward memory reward
    ) internal {
        // Get the address that is providing the tokens for funding
        address fundingSource = state.target;
        uint256 rewardsLength = reward.tokens.length;
        address permitContract;

        if (state.usePermit == 1) {
            permitContract = intentSource.getPermitContract(intentHash);
        }

        // Iterate through each token in the reward structure
        for (uint256 i; i < rewardsLength; ++i) {
            // Get token address and required amount for current reward
            address token = reward.tokens[i].token;
            uint256 amount = reward.tokens[i].amount;
            uint256 balance = IERC20(token).balanceOf(address(this));

            // Only proceed if vault needs more tokens and we have permission to transfer them
            if (amount > balance) {
                // Calculate how many more tokens the vault needs to be fully funded
                uint256 remainingAmount = amount - balance;

                if (permitContract != address(0)) {
                    remainingAmount = _transferFromPermit(
                        IPermit(permitContract),
                        fundingSource,
                        token,
                        remainingAmount
                    );
                }

                if (remainingAmount > 0) {
                    _transferFrom(
                        fundingSource,
                        token,
                        remainingAmount,
                        state.allowPartialFunding
                    );
                }
            }
        }
    }

    /**
     * @dev Processes all reward tokens
     */
    function _processRewardTokens(
        Reward memory reward,
        address claimant
    ) internal {
        uint256 rewardsLength = reward.tokens.length;

        for (uint256 i; i < rewardsLength; ++i) {
            address token = reward.tokens[i].token;
            uint256 amount = reward.tokens[i].amount;
            uint256 balance = IERC20(token).balanceOf(address(this));

            if (claimant == reward.creator || balance < amount) {
                if (claimant != reward.creator) {
                    emit RewardTransferFailed(token, claimant, amount);
                }
                if (balance > 0) {
                    _tryTransfer(token, claimant, balance);
                }
            } else {
                _tryTransfer(token, claimant, amount);

                // Return excess balance to creator
                if (balance > amount) {
                    _tryTransfer(token, reward.creator, balance - amount);
                }
            }
        }
    }

    /**
     * @dev Processes native token reward
     */
    function _processNativeReward(
        Reward memory reward,
        address claimant
    ) internal {
        if (reward.nativeValue > 0) {
            uint256 amount = reward.nativeValue;
            if (address(this).balance < reward.nativeValue) {
                emit RewardTransferFailed(address(0), claimant, amount);
                amount = address(this).balance;
            }

            (bool success, ) = payable(claimant).call{value: amount}("");
            if (!success) {
                emit RewardTransferFailed(address(0), claimant, amount);
            }
        }
    }

    /**
     * @dev Processes refund token if specified
     */
    function _recoverToken(address refundToken, address creator) internal {
        uint256 refundAmount = IERC20(refundToken).balanceOf(address(this));
        if (refundAmount > 0) {
            IERC20(refundToken).safeTransfer(creator, refundAmount);
        }
    }

    /**
     * @notice Attempts to transfer tokens to a recipient, emitting an event on failure
     * @param token Address of the token being transferred
     * @param to Address of the recipient
     * @param amount Amount of tokens to transfer
     */
    function _tryTransfer(address token, address to, uint256 amount) internal {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20.transfer.selector, to, amount)
        );

        if (!success || (data.length > 0 && !abi.decode(data, (bool)))) {
            emit RewardTransferFailed(token, to, amount);
        }
    }

    /**
     * @notice Transfers tokens from funding source to vault
     * @param fundingSource Address that is providing the tokens for funding
     * @param token Address of the token being transferred
     * @param amount Amount of tokens to transfer
     * @param allowPartialFunding Whether to allow partial funding
     */
    function _transferFrom(
        address fundingSource,
        address token,
        uint256 amount,
        uint8 allowPartialFunding
    ) internal {
        // Check how many tokens this contract is allowed to transfer from funding source
        uint256 allowance = IERC20(token).allowance(
            fundingSource,
            address(this)
        );

        uint256 transferAmount;
        // Calculate transfer amount as minimum of what's needed and what's allowed
        if (allowance >= amount) {
            transferAmount = amount;
        } else if (allowPartialFunding == 1) {
            transferAmount = allowance;
        } else {
            revert InsufficientTokenAllowance(token, fundingSource, amount);
        }

        if (transferAmount > 0) {
            // Transfer tokens from funding source to vault using safe transfer
            IERC20(token).safeTransferFrom(
                fundingSource,
                address(this),
                transferAmount
            );
        }
    }

    /**
     * @notice Transfers tokens from funding source to vault using external Permit contract
     * @param permit Permit2 like contract to use for token transfer
     * @param fundingSource Address that is providing the tokens for funding
     * @param token Address of the token being transferred
     * @param amount Amount of tokens to transfer
     * @return remainingAmount Amount of tokens that still need to be transferred
     */
    function _transferFromPermit(
        IPermit permit,
        address fundingSource,
        address token,
        uint256 amount
    ) internal returns (uint256 remainingAmount) {
        // Check how many tokens this contract is allowed to transfer from funding source
        (uint160 allowance, , ) = permit.allowance(
            fundingSource,
            token,
            address(this)
        );

        uint256 transferAmount;
        // Calculate transfer amount as minimum of what's needed and what's allowed
        if (allowance >= amount) {
            transferAmount = amount;
            remainingAmount = 0;
        } else {
            transferAmount = allowance;
            remainingAmount = amount - allowance;
        }

        if (transferAmount > 0) {
            // Transfer tokens from funding source to vault using Permit.transferFrom
            permit.transferFrom(
                fundingSource,
                address(this),
                uint160(transferAmount),
                token
            );
        }
    }
}
