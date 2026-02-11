// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

// Dependency imports
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {BeaconProxy} from "@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol";
import {UpgradeableBeacon} from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

// Internal imports
import {IBeaconProxyFactory} from "src/interfaces/IBeaconProxyFactory.sol";

/**
 * @dev Implementation of a factory that allows for deterministic deployment of BeaconProxys from an UpgradeableBeacon
 * using the Create2 opcode. The salt used for the Create2 deployment is the hash of the sender and the base salt.
 *
 * @custom:contact security@seamlessprotocol.com
 */
contract BeaconProxyFactory is IBeaconProxyFactory, UpgradeableBeacon {
    /// @inheritdoc IBeaconProxyFactory
    uint256 public numProxies;

    /// @notice Creates a new BeaconProxyFactory
    /// @param _implementation The implementation contract for the beacon that will be used by BeaconProxys created
    /// by this factory
    /// @param _owner The owner of this factory, allowed to update the beacon implementation
    constructor(address _implementation, address _owner) UpgradeableBeacon(_implementation, _owner) {}

    /// @inheritdoc IBeaconProxyFactory
    function computeProxyAddress(address sender, bytes memory data, bytes32 baseSalt)
        external
        view
        returns (address proxy)
    {
        return
            Create2.computeAddress(_getDeploySalt(sender, baseSalt), keccak256(_getCreationCode(data)), address(this));
    }

    /// @inheritdoc IBeaconProxyFactory
    function createProxy(bytes memory data, bytes32 baseSalt) external returns (address proxy) {
        proxy = Create2.deploy(0, _getDeploySalt(msg.sender, baseSalt), _getCreationCode(data));

        numProxies++;

        // Emit an event for the newly created proxy
        emit BeaconProxyCreated(proxy, data, baseSalt);
    }

    /// @dev Returns the deploy salt for the BeaconProxy, which is the hash of the sender and the base salt
    /// @param sender The address that will deploy the beacon proxy using the factory
    /// @param baseSalt The base salt used for deterministic deployment
    /// @return salt The deploy salt for the BeaconProxy
    function _getDeploySalt(address sender, bytes32 baseSalt) internal pure returns (bytes32 salt) {
        return keccak256(abi.encode(sender, baseSalt));
    }

    /// @dev Returns the creation code for the BeaconProxy
    /// @param data The initialization data for the BeaconProxy
    /// @return bytecode The creation code for the BeaconProxy
    function _getCreationCode(bytes memory data) internal view returns (bytes memory bytecode) {
        bytecode = abi.encodePacked(
            type(BeaconProxy).creationCode, // BeaconProxy's runtime bytecode
            abi.encode(address(this), data) // Constructor arguments: beacon address and initialization data
        );
    }
}
