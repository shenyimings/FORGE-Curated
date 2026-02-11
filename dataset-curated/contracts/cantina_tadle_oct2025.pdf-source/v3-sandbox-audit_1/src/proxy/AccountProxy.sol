// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title AccountImplementations
 * @dev Interface for retrieving implementation addresses based on function signatures
 * @notice Used by proxy contracts to route function calls to appropriate implementations
 */
interface AccountImplementations {
    /**
     * @dev Returns the implementation address for a given function signature
     * @param _sig The 4-byte function signature to lookup
     * @return The address of the implementation contract for this signature
     */
    function getImplementation(bytes4 _sig) external view returns (address);
}

/**
 * @title TadleSandboxAccount
 * @dev Proxy contract that delegates calls to implementation contracts based on function signatures
 * @notice This contract provides a fallback mechanism that routes calls to appropriate implementations
 * @custom:security Uses delegatecall for implementation routing while preserving caller context
 */
contract TadleSandboxAccount {
    /// @dev Immutable reference to the implementations registry contract
    /// @notice Stores the address of the contract that maps function signatures to implementations
    AccountImplementations public immutable implementations;

    /**
     * @dev Constructor sets the implementations registry address
     * @param _implementations Address of the AccountImplementations contract
     * @notice The implementations address cannot be changed after deployment
     * @custom:security Validates that implementations address is not zero
     */
    constructor(address _implementations) {
        require(_implementations != address(0), "TadleSandboxAccount: implementations address cannot be zero");
        implementations = AccountImplementations(_implementations);
    }

    /**
     * @dev Delegates the current call to the specified implementation contract
     * @param implementation Address of the implementation contract to delegate to
     * @notice This function does not return to its internal call site, it will return directly to the external caller
     * @custom:security Uses inline assembly for efficient delegatecall execution
     */
    function _delegate(address implementation) internal {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            // Copy msg.data. We take full control of memory in this inline assembly
            // block because it will not return to Solidity code. We overwrite the
            // Solidity scratch pad at memory position 0.
            calldatacopy(0, 0, calldatasize())

            // Call the implementation.
            // out and outsize are 0 because we don't know the size yet.
            let result := delegatecall(gas(), implementation, 0, calldatasize(), 0, 0)

            // Copy the returned data.
            returndatacopy(0, 0, returndatasize())

            switch result
            // delegatecall returns 0 on error.
            case 0 { revert(0, returndatasize()) }
            default { return(0, returndatasize()) }
        }
    }

    /**
     * @dev Delegates the current call to the address returned by the implementations registry
     * @param _sig The function signature to lookup in the implementations registry
     * @notice This function does not return to its internal call site, it will return directly to the external caller
     * @custom:access-control Requires that an implementation exists for the given signature
     */
    function _fallback(bytes4 _sig) internal {
        address _implementation = implementations.getImplementation(_sig);
        require(_implementation != address(0), "TadleSandboxAccount: no implementation found for function signature");
        _delegate(_implementation);
    }

    /**
     * @dev Fallback function that delegates calls to the address returned by implementations registry
     * @notice Automatically routes function calls to appropriate implementation contracts
     * @custom:payable Accepts ETH transfers along with function calls
     */
    fallback() external payable {
        _fallback(msg.sig);
    }

    /**
     * @dev Receive function that handles plain ETH transfers and function calls
     * @notice Routes function calls through the fallback mechanism when signature is present
     * @custom:payable Accepts ETH transfers to the proxy contract
     */
    receive() external payable {
        if (msg.sig != 0x00000000) {
            _fallback(msg.sig);
        }
    }
}
