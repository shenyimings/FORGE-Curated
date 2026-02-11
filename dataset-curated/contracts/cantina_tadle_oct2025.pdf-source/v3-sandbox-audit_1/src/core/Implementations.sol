// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";

/**
 * @title IAuth
 * @dev Interface for authentication contract
 */
interface IAuth {
    function isAdmin(address account) external view returns (bool);
}

/**
 * @title Setup
 * @dev Base contract for implementation management
 * Stores mappings between function signatures and their implementation addresses
 */
abstract contract Setup {
    /// @dev Initialization flag to prevent multiple initialization calls
    bool internal _initialized;

    /// @dev Auth contract instance for access control
    IAuth public auth;

    /// @dev Default implementation address for fallback when signature not found
    address public defaultImplementation;

    /// @dev Mapping of function signatures to their implementation addresses
    mapping(bytes4 => address) internal sigImplementations;

    /// @dev Mapping of implementation addresses to their function signatures
    /// @notice This allows efficient removal of all signatures for an implementation
    mapping(address => bytes4[]) internal implementationSigs;
}

/**
 * @title Implementations
 * @dev Contract for managing implementation addresses and their function signatures
 */
abstract contract Implementations is Setup {
    // Events for implementation management
    event LogSetDefaultImplementation(address indexed oldImplementation, address indexed newImplementation);
    event LogAddImplementation(address indexed implementation, bytes4[] sigs);
    event LogRemoveImplementation(address indexed implementation, bytes4[] sigs);

    /**
     * @dev Modifier to restrict function access to admin users only
     * @notice Reverts if caller is not an admin in the auth contract
     */
    modifier isAdmin() {
        require(auth.isAdmin(msg.sender), "Implementations: not admin");
        _;
    }

    /**
     * @dev Modifier to ensure contract is only initialized once
     * @notice Prevents multiple initialization calls that could reset contract state
     */
    modifier initializer() {
        require(!_initialized, "Implementations: already initialized");
        _;
        _initialized = true;
    }

    /**
     * @dev Sets the default implementation address used when no specific implementation is found
     * @param _defaultImplementation Address of the new default implementation
     */
    function setDefaultImplementation(address _defaultImplementation) external isAdmin {
        require(_defaultImplementation != address(0), "Implementations: invalid default implementation address");
        require(_defaultImplementation != defaultImplementation, "Implementations: new implementation same as current");

        emit LogSetDefaultImplementation(defaultImplementation, _defaultImplementation);
        defaultImplementation = _defaultImplementation;
    }

    /**
     * @dev Add new implementation with its function signatures
     * @param _implementation Address of the implementation contract
     * @param _sigs Array of function signatures supported by the implementation
     */
    function addImplementation(address _implementation, bytes4[] calldata _sigs) external isAdmin {
        require(_implementation != address(0), "Implementations: invalid implementation address");
        require(implementationSigs[_implementation].length == 0, "Implementations: implementation already registered");
        require(_sigs.length > 0, "Implementations: empty signatures array");

        for (uint256 i = 0; i < _sigs.length; i++) {
            bytes4 _sig = _sigs[i];
            require(_sig != bytes4(0), "Implementations: invalid function signature");
            require(sigImplementations[_sig] == address(0), "Implementations: signature already registered");
            sigImplementations[_sig] = _implementation;
        }

        implementationSigs[_implementation] = _sigs;
        emit LogAddImplementation(_implementation, _sigs);
    }

    /**
     * @dev Remove an implementation and its associated function signatures
     * @param _implementation Address of the implementation to remove
     */
    function removeImplementation(address _implementation) external isAdmin {
        require(_implementation != address(0), "Implementations: invalid implementation address");
        require(implementationSigs[_implementation].length != 0, "Implementations: implementation not found");
        require(_implementation != defaultImplementation, "Implementations: cannot remove default implementation");

        bytes4[] memory sigs = implementationSigs[_implementation];
        for (uint256 i = 0; i < sigs.length; i++) {
            bytes4 sig = sigs[i];
            delete sigImplementations[sig];
        }

        delete implementationSigs[_implementation];
        emit LogRemoveImplementation(_implementation, sigs);
    }
}

/**
 * @title TadleImplementations
 * @dev Implementation registry contract with getter functions
 */
contract TadleImplementations is Ownable2Step, Implementations {
    constructor() Ownable(msg.sender) {}

    /**
     * @dev Initialize the contract with auth contract address
     * @param _auth Address of the auth contract for access control
     */
    function initialize(address _auth) external onlyOwner initializer {
        require(_auth != address(0), "TadleImplementations: invalid auth address");
        auth = IAuth(_auth);
    }

    /**
     * @dev Get implementation address for a function signature
     * @param _sig Function signature to lookup
     * @return Implementation address or default implementation if not found
     */
    function getImplementation(bytes4 _sig) external view returns (address) {
        address _implementation = sigImplementations[_sig];
        return _implementation == address(0) ? defaultImplementation : _implementation;
    }

    /**
     * @dev Get all function signatures for an implementation
     * @param _impl Implementation address to lookup
     * @return Array of function signatures
     */
    function getImplementationSigs(address _impl) external view returns (bytes4[] memory) {
        return implementationSigs[_impl];
    }

    /**
     * @dev Get specific implementation for a function signature
     * @param _sig Function signature to lookup
     * @return Implementation address (returns zero address if not found)
     */
    function getSigImplementation(bytes4 _sig) external view returns (address) {
        return sigImplementations[_sig];
    }
}
