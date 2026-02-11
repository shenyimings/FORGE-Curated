// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

// Copy and rename of OpenZeppelin Contracts (last updated v5.0.0) (access/Ownable2Step.sol)

pragma solidity 0.8.30;

import {P2pOperator} from "./P2pOperator.sol";

/**
 * @dev Contract module which provides access control mechanism, where
 * there is an account (a P2pOperator) that can be granted exclusive access to
 * specific functions.
 *
 * This extension of the {P2pOperator.sol} contract includes a two-step mechanism to transfer
 * P2pOperator, where the new P2pOperator must call {acceptP2pOperator} in order to replace the
 * old one. This can help prevent common mistakes, such as transfers of P2pOperator to
 * incorrect accounts, or to contracts that are unable to interact with the
 * permission system.
 *
 * The initial P2pOperator is specified at deployment time in the constructor for `P2pOperator.sol`. This
 * can later be changed with {transferP2pOperator} and {acceptP2pOperator}.
 *
 * This module is used through inheritance. It will make available all functions
 * from parent (P2pOperator.sol).
 */
abstract contract P2pOperator2Step is P2pOperator {
    address private s_pendingP2pOperator;

    event P2pOperator2Step__P2pOperatorTransferStarted(address indexed _previousP2pOperator, address indexed _newP2pOperator);

    /**
     * @dev Returns the address of the pending P2pOperator.
     */
    function getPendingP2pOperator() public view virtual returns (address) {
        return s_pendingP2pOperator;
    }

    /**
     * @dev Starts the P2pOperator transfer of the contract to a new account. Replaces the pending transfer if there is one.
     * Can only be called by the current P2pOperator.
     *
     * Setting `_newP2pOperator` to the zero address is allowed; this can be used to cancel an initiated P2pOperator transfer.
     */
    function transferP2pOperator(address _newP2pOperator) public virtual override onlyP2pOperator {
        s_pendingP2pOperator = _newP2pOperator;
        emit P2pOperator2Step__P2pOperatorTransferStarted(getP2pOperator(), _newP2pOperator);
    }

    /**
     * @dev Transfers P2pOperator of the contract to a new account (`_newP2pOperator`) and deletes any pending P2pOperator.
     * Internal function without access restriction.
     */
    function _transferP2pOperator(address _newP2pOperator) internal virtual override {
        delete s_pendingP2pOperator;
        super._transferP2pOperator(_newP2pOperator);
    }

    /**
     * @dev The new P2pOperator accepts the P2pOperator transfer.
     */
    function acceptP2pOperator() public virtual {
        address sender = msg.sender;
        if (s_pendingP2pOperator != sender) {
            revert P2pOperator__UnauthorizedAccount(sender);
        }
        _transferP2pOperator(sender);
    }
}
