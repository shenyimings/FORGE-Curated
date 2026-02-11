// SPDX-FileCopyrightText: 2025 P2P Validator <info@p2p.org>
// SPDX-License-Identifier: MIT

// Copy and rename of OpenZeppelin Contracts (last updated v5.0.0) (access/Ownable.sol)

pragma solidity 0.8.30;

/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an P2pOperator) that can be granted exclusive access to
 * specific functions.
 *
 * The initial P2pOperator is set to the address provided by the deployer. This can
 * later be changed with {transferP2pOperator}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyP2pOperator`, which can be applied to your functions to restrict their use to
 * the P2pOperator.
 */
abstract contract P2pOperator {
    address private s_p2pOperator;

    /**
     * @dev The caller account is not authorized to perform an operation.
     */
    error P2pOperator__UnauthorizedAccount(address _account);

    /**
     * @dev The P2pOperator is not a valid P2pOperator account. (eg. `address(0)`)
     */
    error P2pOperator__InvalidP2pOperator(address _p2pOperator);

    event P2pOperator__P2pOperatorTransferred(address indexed _previousP2pOperator, address indexed _newP2pOperator);

    /**
     * @dev Initializes the contract setting the address provided by the deployer as the initial P2pOperator.
     */
    constructor(address _initialP2pOperator) {
        if (_initialP2pOperator == address(0)) {
            revert P2pOperator__InvalidP2pOperator(address(0));
        }
        _transferP2pOperator(_initialP2pOperator);
    }

    /**
     * @dev Throws if called by any account other than the P2pOperator.
     */
    modifier onlyP2pOperator() {
        _checkP2pOperator();
        _;
    }

    /**
     * @dev Returns the address of the current P2pOperator.
     */
    function getP2pOperator() public view virtual returns (address) {
        return s_p2pOperator;
    }

    /**
     * @dev Throws if the sender is not the P2pOperator.
     */
    function _checkP2pOperator() internal view virtual {
        if (s_p2pOperator != msg.sender) {
            revert P2pOperator__UnauthorizedAccount(msg.sender);
        }
    }

    /**
     * @dev Transfers P2pOperator of the contract to a new account (`_newP2pOperator`).
     * Can only be called by the current P2pOperator.
     */
    function transferP2pOperator(address _newP2pOperator) public virtual onlyP2pOperator {
        if (_newP2pOperator == address(0)) {
            revert P2pOperator__InvalidP2pOperator(address(0));
        }
        _transferP2pOperator(_newP2pOperator);
    }

    /**
     * @dev Transfers P2pOperator of the contract to a new account (`_newP2pOperator`).
     * Internal function without access restriction.
     */
    function _transferP2pOperator(address _newP2pOperator) internal virtual {
        address oldP2pOperator = s_p2pOperator;
        s_p2pOperator = _newP2pOperator;
        emit P2pOperator__P2pOperatorTransferred(oldP2pOperator, _newP2pOperator);
    }
}
