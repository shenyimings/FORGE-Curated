// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";

/**
 * @title IAuth
 * @dev Interface for authentication contract
 * Used to verify admin privileges for validator management
 */
interface IAuth {
    /**
     * @dev Checks if an account has admin privileges
     * @param account Address to check for admin status
     * @return True if the account is an admin, false otherwise
     */
    function isAdmin(address account) external view returns (bool);
}

/**
 * @title Validator
 * @dev Contract for managing and verifying validators
 * This contract maintains a registry of validators that can be used
 * to verify permissions for specific operations identified by keys.
 * Validators can be added or removed by admins, and their status can be
 * verified for specific operation keys.
 */
contract Validator is Ownable2Step {
    /// @dev Initialization flag to prevent multiple initialization calls
    bool private _initialized;

    /// @dev Auth contract instance for access control
    IAuth public auth;

    /// @dev Mapping to store validator status by key and address
    /// @notice Maps a key (bytes32) and validator address to a boolean status
    /// @notice True indicates the address is a valid validator for the key
    mapping(bytes32 => mapping(address => bool)) public validator;

    // Events
    /**
     * @dev Emitted when a validator's status is set
     * @param key The key associated with the validator
     * @param validator The address of the validator
     * @param status The status that was set (true/false)
     */
    event ValidatorSet(bytes32 indexed key, address indexed validator, bool status);

    /**
     * @dev Emitted when multiple validators' statuses are set in batch
     * @param key The key associated with the validators
     * @param validators Array of validator addresses
     * @param status The status that was set for all validators (true/false)
     */
    event ValidatorBatchSet(bytes32 indexed key, address[] validators, bool status);

    /**
     * @dev Modifier to check if caller has admin privileges
     */
    modifier isAdmin() {
        require(auth.isAdmin(msg.sender), "Validator: caller is not an admin");
        _;
    }

    /**
     * @dev Modifier to ensure contract is only initialized once
     * @notice Prevents multiple initialization calls that could reset contract state
     */
    modifier initializer() {
        require(!_initialized, "Validator: already initialized");
        _;
        _initialized = true;
    }

    /**
     * @dev Initialize contract with deployer as owner
     */
    constructor() Ownable(msg.sender) {}

    /**
     * @dev Initialize the contract with auth contract address
     * @param _auth Address of the Auth contract for admin verification
     */
    function initialize(address _auth) external onlyOwner initializer {
        require(_auth != address(0), "Validator: invalid auth address");
        auth = IAuth(_auth);
    }

    /**
     * @dev Sets the status of a validator for a specific key
     * @param _key The key associated with the validator
     * @param _validator The address of the validator
     * @param _status The status to set (true/false)
     */
    function setValidator(bytes32 _key, address _validator, bool _status) external isAdmin {
        validator[_key][_validator] = _status;
        emit ValidatorSet(_key, _validator, _status);
    }

    /**
     * @dev Verifies if an address is a validator for a specific key
     * @param _key The key to check
     * @param _validator The address to verify
     * @return bool True if the address is a validator, false otherwise
     */
    function verify(bytes32 _key, address _validator) external view returns (bool) {
        return validator[_key][_validator];
    }

    /**
     * @dev Batch sets the status of multiple validators for a specific key
     * @param _key The key associated with the validators
     * @param _validators Array of validator addresses
     * @param _status The status to set for all validators (true/false)
     */
    function batchSetValidator(bytes32 _key, address[] calldata _validators, bool _status) external isAdmin {
        require(_key != bytes32(0), "Validator: invalid key");
        require(_validators.length > 0, "Validator: empty validators array");

        for (uint256 i = 0; i < _validators.length; i++) {
            require(_validators[i] != address(0), "Validator: invalid validator address");
            validator[_key][_validators[i]] = _status;
        }

        emit ValidatorBatchSet(_key, _validators, _status);
    }
}
