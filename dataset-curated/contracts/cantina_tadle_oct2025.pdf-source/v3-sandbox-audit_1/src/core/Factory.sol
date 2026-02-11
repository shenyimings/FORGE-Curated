// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {UpgradeableProxy} from "../proxy/UpgradeableProxy.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";

/**
 * @title IAuth
 * @dev Interface for the Auth contract
 */
interface IAuth {
    function createSandboxAdmin(address sandboxAccount, address admin) external;
}

/**
 * @title IUpgradeableProxy
 * @dev Interface for the UpgradeableProxy contract's initialization function
 */
interface IUpgradeableProxy {
    function initializeImplementation(address newImplementation, bytes memory data) external payable;
}

/**
 * @title CloneFactory
 * @dev Base contract implementing EIP-1167 minimal proxy pattern
 */
contract CloneFactory {
    /**
     * @dev Creates a clone of a deployed contract using minimal proxy pattern
     * @param _accountProxy Address of the contract to clone
     * @return result Address of the newly created clone
     */
    function createClone(address _accountProxy) internal returns (address result) {
        require(_accountProxy != address(0), "CloneFactory: invalid account proxy address");

        bytes20 targetBytes = bytes20(_accountProxy);
        // Minimal proxy creation bytecode
        // Reference: https://eips.ethereum.org/EIPS/eip-1167
        assembly {
            let clone := mload(0x40)
            mstore(clone, 0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000)
            mstore(add(clone, 0x14), targetBytes)
            mstore(add(clone, 0x28), 0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000)
            result := create(0, clone, 0x37)
        }

        require(result != address(0), "CloneFactory: failed to create clone");
    }
}

/**
 * @title TadleSandBoxFactory
 * @dev Factory contract for creating new sandbox accounts using minimal proxy pattern
 */
contract TadleSandBoxFactory is Ownable2Step, CloneFactory {
    // Auth contract address for access control
    address public auth;
    // Implementation contract to be cloned
    address public accountProxy;

    // Mapping to track if an address is a sandbox account
    mapping(address => bool) public isSandboxAccount;

    // Mapping to track the relationship between name and account address
    mapping(string => address) public contractAddrs;

    // Event emitted when a new account is created
    event LogAccountCreated(address sender, address indexed owner, address indexed account);

    /**
     * @dev Initialize factory with auth and implementation addresses
     * @param _admin Address of the factory admin
     */
    constructor(address _admin) Ownable(_admin) {}

    /**
     * @dev Initialize factory with auth and implementation addresses
     * @param _auth Address of the auth contract for access control
     * @param _accountProxy Address of the implementation to be cloned
     */
    function initialize(address _auth, address _accountProxy) external onlyOwner {
        require(_auth != address(0), "TadleSandBoxFactory: invalid auth address");
        require(_accountProxy != address(0), "TadleSandBoxFactory: invalid proxy address");

        auth = _auth;
        accountProxy = _accountProxy;
    }

    /**
     * @dev Creates a new sandbox account
     * @param _owner Address of the account owner
     * @return _account Address of the newly created account
     */
    /**
     * @dev Creates a new sandbox account
     * @param _owner Address of the account owner
     * @return _account Address of the newly created account
     */
    function build(address _owner) public returns (address _account) {
        require(auth != address(0), "TadleSandBoxFactory: not initialized");
        require(accountProxy != address(0), "TadleSandBoxFactory: not initialized");
        require(_owner != address(0), "TadleSandBoxFactory: invalid owner address");

        _account = createClone(accountProxy);
        IAuth(auth).createSandboxAdmin(_account, _owner);
        isSandboxAccount[_account] = true;

        emit LogAccountCreated(msg.sender, _owner, _account);
    }

    /**
     * @dev Creates a new upgradeable proxy contract with deterministic address
     * @param _name Name identifier for the proxy contract
     * @param _logic Address of the logic implementation (can be zero address)
     * @param _admin Address of the proxy admin
     * @param _salt Salt value for deterministic address generation
     * @param _data Initialization data for the implementation contract
     * @return _account Address of the newly created proxy contract
     */
    /**
     * @dev Creates a new upgradeable proxy contract with deterministic address
     * @param _name Name identifier for the proxy contract
     * @param _logic Address of the logic implementation (can be zero address)
     * @param _admin Address of the proxy admin
     * @param _salt Salt value for deterministic address generation
     * @param _data Initialization data for the implementation contract
     * @return _account Address of the newly created proxy contract
     */
    function createUpgradeableProxy(
        string memory _name,
        address _logic,
        address _admin,
        bytes32 _salt,
        bytes memory _data
    ) public onlyOwner returns (address _account) {
        require(bytes(_name).length > 0, "TadleSandBoxFactory: name cannot be empty");
        require(_admin != address(0), "TadleSandBoxFactory: invalid admin address");
        require(contractAddrs[_name] == address(0), "TadleSandBoxFactory: name already used");

        // Create new proxy with admin rights using CREATE2 for deterministic address
        _account = address(new UpgradeableProxy{salt: _salt}(_admin));

        // Initialize implementation if logic address is provided
        if (_logic != address(0)) {
            IUpgradeableProxy(_account).initializeImplementation(_logic, _data);
        }

        // Record the mapping between name and account address
        contractAddrs[_name] = _account;

        // Emit account creation event
        emit LogAccountCreated(msg.sender, _admin, _account);

        return _account;
    }
}
