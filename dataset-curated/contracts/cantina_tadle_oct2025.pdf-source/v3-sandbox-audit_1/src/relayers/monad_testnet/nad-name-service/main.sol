// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title INadNameRegistration Interface
 * @dev Interface for NAD name registration operations
 */
interface INadNameRegistration {
    /**
     * @dev Registration parameters structure
     */
    struct RegistrationParams {
        string name;
        address nameOwner;
        bool setAsPrimaryName;
        address referrer;
        bytes32 discountKey;
        bytes discountClaimProof;
        uint256 nonce;
        uint256 deadline;
    }

    /**
     * @dev Registers a name with signature verification
     * @param params Registration parameters
     * @param signature Signature for verification
     */
    function registerWithSignature(RegistrationParams calldata params, bytes calldata signature) external payable;
}

interface INadNameManager {
    /**
     * @dev Sets the primary name for an address
     * @param addr Address to set primary name for
     * @param name Name to set as primary
     */
    function setPrimaryNameForAddress(address addr, string calldata name) external;

    /**
     * @dev Safely transfers the ownership of a given token ID to another address
     * @param from Current owner of the token
     * @param to Address to receive the ownership of the given token ID
     * @param tokenId uint256 ID of the token to be transferred
     */
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
}

/**
 * @title INadNamePricing Interface
 * @dev Interface for NAD name pricing operations
 */
interface INadNamePricing {
    /**
     * @dev Price structure containing base and premium components
     */
    struct Price {
        uint256 base;
        uint256 premium;
    }

    /**
     * @dev Gets the registration price for a name
     * @param name Name to check price for
     * @return Price structure with base and premium components
     */
    function getRegisteringPrice(string calldata name) external view returns (Price memory);
}

/**
 * @title NadNameServiceResolver
 * @dev Contract for handling NAD Name Service operations
 * @notice Provides functionality for name registration and pricing queries
 */
contract NadNameServiceResolver {
    // ============ Storage ============
    /// @dev Reference to the NAD name registration contract
    INadNameRegistration public immutable nadNameRegistration;
    /// @dev Reference to the NAD name pricing contract
    INadNamePricing public immutable nadNamePricing;
    /// @dev Reference to the NAD name manager contract for primary name operations
    INadNameManager public immutable nadNameManager;

    /**
     * @dev Initializes the contract with required service addresses
     * @param _nadNameRegistration Address of the NAD name registration contract
     * @param _nadNamePricing Address of the NAD name pricing contract
     * @param _nadNameManager Address of the NAD name manager contract
     */
    constructor(address _nadNameRegistration, address _nadNamePricing, address _nadNameManager) {
        require(
            _nadNameRegistration != address(0) && _nadNamePricing != address(0) && _nadNameManager != address(0),
            "Invalid contract address"
        );

        nadNameRegistration = INadNameRegistration(_nadNameRegistration);
        nadNamePricing = INadNamePricing(_nadNamePricing);
        nadNameManager = INadNameManager(_nadNameManager);
    }

    /**
     * @dev Sets the primary name for the contract address
     * @notice Updates the primary name association in the NAD Name Service
     * @param name The name to be set as primary for this contract
     * @return _eventName Name of the event to be logged
     * @return _eventParam Encoded event parameters
     */
    function setPrimaryNameForAddress(string calldata name)
        external
        returns (string memory _eventName, bytes memory _eventParam)
    {
        // Update primary name in the manager contract
        nadNameManager.setPrimaryNameForAddress(address(this), name);

        // Return event data for external logging
        _eventName = "LogSetPrimaryNameForAddress(address,string)";
        _eventParam = abi.encode(address(this), name);
    }

    /**
     * @dev Registers a new name with signature verification
     * @notice Handles name registration including price calculation and payment
     * @param params Registration parameters including name and owner details
     * @param signature Cryptographic signature for verification
     * @return _eventName Name of the event to be logged
     * @return _eventParam Encoded event parameters
     */
    function registerName(INadNameRegistration.RegistrationParams calldata params, bytes calldata signature)
        external
        returns (string memory _eventName, bytes memory _eventParam)
    {
        // Get registration price
        uint256 namePrice = nadNamePricing.getRegisteringPrice(params.name).base;

        // Verify sufficient balance
        require(address(this).balance >= namePrice, "Insufficient payment");

        // Execute registration
        nadNameRegistration.registerWithSignature{value: namePrice}(params, signature);

        // Return event data
        _eventName = "LogRegisterName(string,address)";
        _eventParam = abi.encode(params.name, params.nameOwner);
    }

    /**
     * @dev Transfers ownership of a NAD name NFT to a new owner
     * @param name Name associated with the NFT
     * @param newOwner Address of the new owner
     * @param tokenId ID of the NFT to transfer
     * @return _eventName Name of the event to be logged
     * @return _eventParam Encoded event parameters
     */
    function transferOwnership(string calldata name, address newOwner, uint256 tokenId)
        external
        returns (string memory _eventName, bytes memory _eventParam)
    {
        // Transfer NFT ownership safely
        nadNameManager.safeTransferFrom(address(this), newOwner, tokenId);

        // Return event data
        _eventName = "LogTransferOwnership(string,address,address,uint256)";
        _eventParam = abi.encode(name, address(this), newOwner, tokenId);
    }
}

/**
 * @title ConnectV1NadNameService
 * @dev Connector implementation for NAD Name Service v1
 * @notice Entry point for NAD Name Service interactions
 */
contract ConnectV1NadNameService is NadNameServiceResolver {
    /// @dev Version identifier for the connector
    string public constant name = "NadNameService-v1.0.0";

    constructor(address _nadNameRegistration, address _nadNamePricing, address _nadNameManager)
        NadNameServiceResolver(_nadNameRegistration, _nadNamePricing, _nadNameManager)
    {}
}
