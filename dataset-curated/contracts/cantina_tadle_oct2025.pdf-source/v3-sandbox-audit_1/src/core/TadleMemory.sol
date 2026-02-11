// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";

/**
 * @title TadleMemory
 * @dev Storage contract for managing temporary data in cast operations
 * This contract provides functionality to store and retrieve temporary data
 * (bytes32, uint256, address) for accounts during cross-contract operations.
 * Data is stored per account and identified by a numeric ID.
 * All data is cleared after retrieval to prevent storage bloat.
 */
contract TadleMemory is Ownable2Step {
    // ============ Storage ============

    /// @dev Temporary bytes storage (Account => ID => Bytes)
    /// @notice Maps an account address and ID to a bytes32 value
    mapping(address => mapping(uint256 => bytes32)) internal mbytes;

    /// @dev Temporary uint storage (Account => ID => Uint)
    /// @notice Maps an account address and ID to a uint256 value
    mapping(address => mapping(uint256 => uint256)) internal muint;

    /// @dev Temporary address storage (Account => ID => Address)
    /// @notice Maps an account address and ID to an address value
    mapping(address => mapping(uint256 => address)) internal maddr;

    // ============ Events ============
    /**
     * @dev Emitted when data is stored in the contract
     * @param account The address that stored the data
     * @param id The storage identifier
     * @param dataType The type of data stored ("bytes", "uint", or "address")
     */
    event DataStored(address indexed account, uint256 indexed id, string dataType);

    /**
     * @dev Emitted when data is retrieved from the contract
     * @param account The address that retrieved the data
     * @param id The storage identifier
     * @param dataType The type of data retrieved ("bytes", "uint", or "address")
     */
    event DataRetrieved(address indexed account, uint256 indexed id, string dataType);

    // ============ Functions ============

    /**
     * @dev Initialize contract with deployer as owner
     */
    constructor() Ownable(msg.sender) {}

    /**
     * @dev Store bytes32 data for the caller
     * @param _id Storage identifier
     * @param _byte Data to store
     * @notice The storage slot must be empty before storing new data
     */
    function setBytes(uint256 _id, bytes32 _byte) public {
        require(mbytes[msg.sender][_id] == bytes32(0), "TadleMemory: storage slot not empty");
        mbytes[msg.sender][_id] = _byte;
        emit DataStored(msg.sender, _id, "bytes");
    }

    /**
     * @dev Retrieve and clear bytes32 data for the caller
     * @param _id Storage identifier
     * @return _byte Stored data (returns bytes32(0) if no data was stored)
     * @notice The storage slot is cleared after retrieval regardless of whether data existed
     */
    function getBytes(uint256 _id) public returns (bytes32 _byte) {
        _byte = mbytes[msg.sender][_id];
        delete mbytes[msg.sender][_id];
        emit DataRetrieved(msg.sender, _id, "bytes");
    }

    /**
     * @dev Store uint256 data for the caller
     * @param _id Storage identifier
     * @param _num Data to store
     * @notice The storage slot must be empty before storing new data
     * @notice If you need to store the value 0, use a different storage slot
     */
    function setUint(uint256 _id, uint256 _num) public {
        require(muint[msg.sender][_id] == 0, "TadleMemory: Storage slot not empty");
        muint[msg.sender][_id] = _num;
        emit DataStored(msg.sender, _id, "uint");
    }

    /**
     * @dev Retrieve and clear uint256 data for the caller
     * @param _id Storage identifier
     * @return _num Stored data (returns 0 if no data was stored)
     * @notice The storage slot is cleared after retrieval regardless of whether data existed
     */
    function getUint(uint256 _id) public returns (uint256 _num) {
        _num = muint[msg.sender][_id];
        delete muint[msg.sender][_id];
        emit DataRetrieved(msg.sender, _id, "uint");
    }

    /**
     * @dev Store address data for the caller
     * @param _id Storage identifier
     * @param _addr Data to store
     * @notice The storage slot must be empty before storing new data
     * @notice Cannot store the zero address
     */
    function setAddr(uint256 _id, address _addr) public {
        require(maddr[msg.sender][_id] == address(0), "TadleMemory: Storage slot not empty");
        maddr[msg.sender][_id] = _addr;
        emit DataStored(msg.sender, _id, "address");
    }

    /**
     * @dev Retrieve and clear address data for the caller
     * @param _id Storage identifier
     * @return _addr Stored data (returns address(0) if no data was stored)
     * @notice The storage slot is cleared after retrieval regardless of whether data existed
     */
    function getAddr(uint256 _id) public returns (address _addr) {
        _addr = maddr[msg.sender][_id];
        delete maddr[msg.sender][_id];
        emit DataRetrieved(msg.sender, _id, "address");
    }
}
