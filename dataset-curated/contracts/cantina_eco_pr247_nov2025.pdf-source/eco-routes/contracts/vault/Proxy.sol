/* -*- c-basic-offset: 4 -*- */
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/**
 * @title Proxy
 * @notice Minimal proxy contract that forwards all calls to an implementation contract
 * @dev Uses delegatecall to preserve caller context while executing implementation logic
 *      Implementation address is immutable and set during construction
 *      Supports both function calls (via fallback) and native token transfers (via receive)
 */
contract Proxy {
    /// @dev Implementation contract address (private for gas optimization)
    address private immutable implementation;

    /**
     * @notice Creates a new proxy pointing to the specified implementation
     * @param _implementation Address of the contract to delegate calls to
     */
    constructor(address _implementation) {
        implementation = _implementation;
    }

    /**
     * @notice Forwards all function calls to the implementation contract
     * @dev Uses delegatecall to preserve msg.sender and msg.value context
     *      Reverts if the delegatecall fails, preserving the original revert reason
     */
    fallback() external payable {
        address _implementation = implementation;

        assembly {
            // Copy msg.data to memory
            calldatacopy(0, 0, calldatasize())
            // Delegatecall into the implementation
            let result := delegatecall(
                gas(),
                _implementation,
                0,
                calldatasize(),
                0,
                0
            )
            // Copy the returned data
            returndatacopy(0, 0, returndatasize())
            // Return or revert based on result
            switch result
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
    }

    /**
     * @notice Accepts native token transfers to the proxy
     * @dev Required for the proxy to receive ETH transfers
     */
    receive() external payable {}
}
