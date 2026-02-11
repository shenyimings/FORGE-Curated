// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";

/**
 * @title Auth
 * @dev Contract for managing system and sandbox administrators
 * This contract handles authentication and authorization for the Tadle system
 * and provides management of sandbox account administrators.
 * It maintains separate registries for system admins and sandbox-specific admins.
 */
contract Auth is Ownable2Step {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @dev Set of system administrators with global privileges
    EnumerableSet.AddressSet private admins;

    /// @dev Initialization flag to prevent multiple initialization calls
    bool private _initialized;

    /// @dev Factory contract address authorized to create sandbox accounts
    address public factory;

    /// @dev Mapping of sandbox accounts to their administrators
    mapping(address => EnumerableSet.AddressSet) private sandboxAdmins;

    // Events for tracking administrative changes
    /**
     * @dev Emitted when a system administrator is added
     * @param account Address that was added as admin
     */
    event AdminAdded(address indexed account);

    /**
     * @dev Emitted when a system administrator is removed
     * @param account Address that was removed from admins
     */
    event AdminRemoved(address indexed account);

    /**
     * @dev Emitted when a sandbox administrator is added
     * @param sandboxAccount The sandbox account address
     * @param admin Address that was added as admin for the sandbox
     */
    event SandboxAdminAdded(address indexed sandboxAccount, address indexed admin);

    /**
     * @dev Emitted when a sandbox administrator is removed
     * @param sandboxAccount The sandbox account address
     * @param admin Address that was removed from sandbox admins
     */
    event SandboxAdminRemoved(address indexed sandboxAccount, address indexed admin);

    /**
     * @dev Emitted when the factory contract address is updated
     * @param oldFactory Previous factory contract address
     * @param newFactory New factory contract address
     */
    event FactoryUpdated(address indexed oldFactory, address indexed newFactory);

    /**
     * @dev Modifier to ensure contract is only initialized once
     * @notice Prevents multiple initialization calls that could reset contract state
     */
    modifier initializer() {
        require(!_initialized, "Auth: already initialized");
        _;
        _initialized = true;
    }

    /**
     * @dev Initialize contract with deployer as admin and factory
     */
    constructor() Ownable(msg.sender) {}

    /**
     * @dev Modifier to restrict access to system administrators
     */
    modifier onlyAdmin() {
        require(admins.contains(msg.sender), "Auth: caller is not an admin");
        _;
    }

    /**
     * @dev Initialize the contract with the first admin
     * @param _admin Address to be set as the first system administrator
     */
    function initialize(address _admin) external onlyOwner initializer {
        require(_admin != address(0), "Auth: invalid admin address");
        admins.add(_admin);
        emit AdminAdded(_admin);
    }

    /**
     * @dev Update factory contract address
     * @param _factory New factory contract address
     */
    function setFactory(address _factory) external onlyAdmin {
        require(_factory != address(0), "Auth: invalid factory address");
        address oldFactory = factory;
        factory = _factory;
        emit FactoryUpdated(oldFactory, _factory);
    }

    /**
     * @dev Initialize sandbox account with its first admin
     * @param sandboxAccount Address of the sandbox account
     * @param admin Address of the initial admin
     */
    function createSandboxAdmin(address sandboxAccount, address admin) external {
        require(msg.sender == factory, "Auth: only factory can create sandbox admin");
        require(sandboxAdmins[sandboxAccount].length() == 0, "Auth: sandbox already exists");
        require(admin != address(0), "Auth: invalid admin address");

        sandboxAdmins[sandboxAccount].add(admin);

        emit SandboxAdminAdded(sandboxAccount, admin);
    }

    /**
     * @dev Add a new admin to the sandbox account
     * @param admin Address to be added as admin
     * @notice Only callable by existing sandbox admins
     */
    function addSandboxAdmin(address admin) external {
        require(sandboxAdmins[msg.sender].length() > 0, "Auth: sandbox not initialized");
        require(admin != address(0), "Auth: invalid admin address");
        require(!sandboxAdmins[msg.sender].contains(admin), "Auth: admin already exists");

        sandboxAdmins[msg.sender].add(admin);
        emit SandboxAdminAdded(msg.sender, admin);
    }

    /**
     * @dev Remove an admin from the sandbox account
     * @param admin Address to be removed from admins
     * @notice Only callable by existing sandbox admins
     * @notice Cannot remove the last admin to prevent lockout
     */
    function removeSandboxAdmin(address admin) external {
        require(sandboxAdmins[msg.sender].length() > 1, "Auth: cannot remove last admin");
        require(sandboxAdmins[msg.sender].contains(admin), "Auth: admin not found");

        sandboxAdmins[msg.sender].remove(admin);
        emit SandboxAdminRemoved(msg.sender, admin);
    }

    /**
     * @dev Check if an address is admin for a sandbox account
     * @param sandboxAccount The sandbox account to check
     * @param admin The address to verify
     * @return bool True if address is admin
     */
    function isSandboxAdmin(address sandboxAccount, address admin) external view returns (bool) {
        return sandboxAdmins[sandboxAccount].contains(admin);
    }

    /**
     * @dev Get all admins for a sandbox account
     * @param sandboxAccount The sandbox account to query
     * @return Array of admin addresses
     */
    function getSandboxAdmins(address sandboxAccount) external view returns (address[] memory) {
        return sandboxAdmins[sandboxAccount].values();
    }

    /**
     * @dev Add a new system administrator
     * @param account Address to be granted admin role
     * @notice Only callable by existing system admins
     */
    function addAdmin(address account) external onlyAdmin {
        require(account != address(0), "Auth: invalid admin address");
        require(!admins.contains(account), "Auth: admin already exists");

        admins.add(account);
        emit AdminAdded(account);
    }

    /**
     * @dev Remove a system administrator
     * @param account Address to be revoked admin role
     * @notice Only callable by existing system admins
     * @notice Cannot remove the last admin to prevent lockout
     */
    function removeAdmin(address account) external onlyAdmin {
        require(admins.length() > 1, "Auth: cannot remove last admin");
        require(admins.contains(account), "Auth: admin not found");

        admins.remove(account);
        emit AdminRemoved(account);
    }

    /**
     * @dev Check if an address is a system administrator
     * @param account Address to check
     * @return bool True if address is admin
     */
    function isAdmin(address account) external view returns (bool) {
        return admins.contains(account);
    }

    /**
     * @dev Get all system administrators
     * @return Array of admin addresses
     */
    function getAdmins() external view returns (address[] memory) {
        return admins.values();
    }
}
