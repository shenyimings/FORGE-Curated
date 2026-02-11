// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/proxy/Proxy.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";

/**
 * @title MonUSDProxy
 * @author Tadle Team
 * @notice A proxy contract that supports upgradeable implementations for MonUSD token
 * @dev Uses EIP-1967 standard storage slots to avoid storage collision
 * @custom:security Implements secure upgrade mechanism with owner-only access
 * @custom:proxy-pattern Follows OpenZeppelin proxy implementation standards
 */
contract MonUSDProxy is Proxy, Ownable2Step {
    /// @dev Implementation contract address storage slot (EIP-1967)
    /// @notice Uses standard EIP-1967 slot to prevent storage collisions
    /// @custom:storage-location eip1967:eip1967.proxy.implementation
    bytes32 private constant IMPLEMENTATION_SLOT =
        bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);

    /**
     * @dev Contract constructor
     * @param __implementation Address of the initial implementation contract
     * @param _manager Address of the contract owner/manager
     * @notice Sets up the proxy with initial implementation and owner
     * @custom:access-control Manager becomes the owner with upgrade privileges
     * @custom:payable Supports ETH transfers during deployment
     */
    constructor(
        address __implementation,
        address _manager
    ) payable Ownable(_manager) {
        require(
            _manager != address(0),
            "MonUSDProxy: manager address cannot be zero"
        );
        _setImplementation(__implementation);
    }

    /**
     * @dev Returns the current implementation address
     * @return impl The address of the current implementation contract
     * @notice Internal function required by OpenZeppelin Proxy
     * @custom:storage-access Reads from EIP-1967 implementation slot
     */
    function _implementation() internal view override returns (address impl) {
        bytes32 slot = IMPLEMENTATION_SLOT;
        assembly {
            impl := sload(slot)
        }
    }

    /**
     * @dev Public function to get the implementation address
     * @return The current implementation contract address
     * @notice Allows external contracts to query the current implementation
     */
    function getImplementation() external view returns (address) {
        return _implementation();
    }

    /**
     * @dev Upgrades the implementation contract
     * @param newImplementation Address of the new implementation contract
     * @notice Only callable by the contract owner
     * @custom:access-control Restricted to contract owner only
     * @custom:upgrade-safety Validates new implementation before upgrade
     */
    function upgrade(address newImplementation) external onlyOwner {
        _setImplementation(newImplementation);
    }

    /**
     * @dev Internal function to set the implementation address
     * @param newImplementation Address of the new implementation contract
     * @notice Uses assembly to write to the implementation slot for gas efficiency
     * @custom:storage-access Directly writes to EIP-1967 implementation slot
     * @custom:validation Ensures implementation address is not zero
     */
    function _setImplementation(address newImplementation) private {
        require(
            newImplementation != address(0),
            "MonUSDProxy: implementation address cannot be zero"
        );
        bytes32 slot = IMPLEMENTATION_SLOT;
        assembly {
            sstore(slot, newImplementation)
        }
    }

    /**
     * @dev Allows the contract to receive ETH transfers
     * @notice Enables the proxy contract to accept plain ETH transfers
     * @custom:payable Accepts ETH without function call data
     */
    receive() external payable {}
}
