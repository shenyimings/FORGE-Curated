// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;

/**
 * @title UpgradeableProxy
 * @author Tadle Team
 * @notice Custom implementation of upgradeable proxy that allows initialization with empty logic
 * @dev This contract implements a proxy pattern that supports delayed initialization
 *      of the implementation contract. Compatible with OpenZeppelin contracts v5.1.0
 * @custom:security Implements EIP-1967 standard for proxy storage slots
 * @custom:upgrade-safety Supports safe upgrades with proper validation
 */
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

/**
 * @title UpgradeableProxy
 * @notice Custom implementation of upgradeable proxy that allows initialization with empty logic
 * @dev This contract implements a proxy pattern that supports delayed initialization
 *      of the implementation contract
 * @custom:security Uses EIP-1967 compliant storage slots to prevent storage collisions
 * @custom:access-control Only owner can upgrade implementation contracts
 */
contract UpgradeableProxy is Ownable2Step {
    // ============ Events ============

    /**
     * @dev Emitted when the proxy is initialized with an admin
     * @param admin Address of the proxy administrator
     */
    event ProxyInitialized(address indexed admin);

    /**
     * @dev Emitted when the implementation contract is upgraded
     * @param oldImplementation Address of the previous implementation
     * @param newImplementation Address of the new implementation
     */
    event ImplementationUpgraded(
        address indexed oldImplementation,
        address indexed newImplementation
    );

    // ============ Storage ============

    /// @dev Storage slot for implementation address (EIP-1967 compliant)
    /// @notice This is the keccak-256 hash of "eip1967.proxy.implementation" subtracted by 1
    /// @custom:storage-location eip1967:eip1967.proxy.implementation
    bytes32 private constant _IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    /**
     * @dev Constructor initializes the proxy with admin
     * @param _admin Address of the proxy admin with upgrade rights
     * @notice The admin has exclusive rights to upgrade the implementation
     * @custom:access-control Admin address cannot be zero address
     */
    constructor(address _admin) Ownable(_admin) {
        require(
            _admin != address(0),
            "UpgradeableProxy: admin address cannot be zero"
        );
        emit ProxyInitialized(_admin);
    }

    /**
     * @dev Sets the implementation address in the EIP-1967 storage slot
     * @param newImplementation Address of the new implementation contract
     * @notice Uses assembly for gas-efficient storage access
     * @custom:storage-access Directly writes to EIP-1967 implementation slot
     */
    function _setImplementation(address newImplementation) private {
        assembly {
            sstore(_IMPLEMENTATION_SLOT, newImplementation)
        }
    }

    /**
     * @dev Returns the current implementation address from storage
     * @return __implementation The current implementation address
     * @notice Uses assembly for gas-efficient storage access
     * @custom:storage-access Directly reads from EIP-1967 implementation slot
     */
    function _getImplementation()
        private
        view
        returns (address __implementation)
    {
        assembly {
            __implementation := sload(_IMPLEMENTATION_SLOT)
        }
    }

    /**
     * @dev Upgrades the implementation to a new address
     * @param newImplementation Address of the new implementation contract
     * @notice Only the owner can upgrade the implementation
     * @custom:access-control Restricted to contract owner only
     * @custom:validation Ensures new implementation is valid and different
     */
    function upgradeTo(address newImplementation) external onlyOwner {
        address oldImplementation = _getImplementation();
        require(
            newImplementation != address(0),
            "UpgradeableProxy: new implementation cannot be zero address"
        );
        require(
            newImplementation != oldImplementation,
            "UpgradeableProxy: new implementation must be different from current"
        );

        _setImplementation(newImplementation);
        emit ImplementationUpgraded(oldImplementation, newImplementation);
    }

    /**
     * @dev Initializes the implementation and optionally calls a function on it
     * @param newImplementation Address of the new implementation contract
     * @param data Function call data for initialization (optional)
     * @notice Can only be called once when no implementation is set
     * @custom:initialization One-time initialization function
     * @custom:payable Supports payable initialization calls
     */
    function initializeImplementation(
        address newImplementation,
        bytes memory data
    ) external payable {
        address oldImplementation = _getImplementation();
        require(
            oldImplementation == address(0),
            "UpgradeableProxy: implementation already initialized"
        );
        require(
            newImplementation != address(0),
            "UpgradeableProxy: new implementation cannot be zero address"
        );

        _setImplementation(newImplementation);

        // Execute initialization function if data is provided
        if (data.length > 0) {
            Address.functionDelegateCall(newImplementation, data);
        }

        emit ImplementationUpgraded(oldImplementation, newImplementation);
    }

    /**
     * @dev Returns the current implementation address
     * @return The address of the current implementation contract
     * @notice Public view function to check current implementation
     */
    function implementation() external view returns (address) {
        return _getImplementation();
    }

    /**
     * @dev Delegates the current call to implementation
     * @notice All function calls to this contract are forwarded to the implementation
     * @custom:payable Supports ETH transfers along with function calls
     * @custom:security Uses delegatecall to preserve caller context
     */
    fallback() external payable {
        address _impl = _getImplementation();
        require(
            _impl != address(0),
            "UpgradeableProxy: implementation not initialized"
        );

        assembly {
            // Copy msg.data. We take full control of memory in this inline assembly
            // block because it will not return to Solidity code. We overwrite the
            // Solidity scratch pad at memory position 0.
            calldatacopy(0, 0, calldatasize())

            // Call the implementation.
            // out and outsize are 0 because we don't know the size yet.
            let result := delegatecall(gas(), _impl, 0, calldatasize(), 0, 0)

            // Copy the returned data.
            returndatacopy(0, 0, returndatasize())

            switch result
            // delegatecall returns 0 on error.
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
    }

    /**
     * @dev Allows the proxy to receive ETH transfers
     * @notice Enables the proxy contract to accept plain ETH transfers
     * @custom:payable Accepts ETH without function call data
     */
    receive() external payable {}
}
