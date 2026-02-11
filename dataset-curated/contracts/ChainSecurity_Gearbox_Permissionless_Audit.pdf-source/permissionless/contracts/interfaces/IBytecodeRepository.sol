// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2024.
pragma solidity ^0.8.23;

import {IVersion} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IVersion.sol";
import {IImmutableOwnableTrait} from "./base/IImmutableOwnableTrait.sol";
import {Bytecode, AuditorSignature} from "./Types.sol";

interface IBytecodeRepository is IVersion, IImmutableOwnableTrait {
    //
    // ERRORS
    //
    error BytecodeIsNotApprovedException(bytes32 contractType, uint256 version);

    // Thrown if the deployed contract has a different contractType/version than it's indexed in the repository
    error IncorrectBytecodeException(bytes32 bytecodeHash);

    // Thrown if the bytecode provided is empty
    error EmptyBytecodeException();

    // Thrown if someone tries to deploy the contract with the same address
    error BytecodeAlreadyExistsAtAddressException(address);

    // Thrown if domain + postfix length is more than 30 symbols (doesn't fit into bytes32)
    error TooLongContractTypeException(string);

    //  Thrown if requested bytecode wasn't found in the repository
    error BytecodeIsNotUploadedException(bytes32 bytecodeHash);

    // Thrown if someone tries to replace existing bytecode with the same contact type & version
    error BytecodeAlreadyExistsException();

    // Thrown if requested bytecode wasn't found in the repository
    error BytecodeIsNotAuditedException();

    // Thrown if someone tries to deploy a contract which wasn't audited enough
    error ContractIsNotAuditedException();

    error SignerIsNotAuditorException(address signer);

    // Thrown when an attempt is made to add an auditor that already exists
    error AuditorAlreadyAddedException();

    // Thrown when an auditor is not found in the repository
    error AuditorNotFoundException();

    // Thrown if the caller is not the deployer of the bytecode
    error NotDeployerException();

    // Thrown if the caller does not have valid auditor permissions
    error NoValidAuditorPermissionsAException();

    /// @notice Thrown when trying to deploy contract with forbidden bytecode
    error BytecodeForbiddenException(bytes32 bytecodeHash);

    /// @notice Thrown when trying to deploy contract with incorrect domain ownership
    error NotDomainOwnerException();

    /// @notice Thrown when trying to deploy contract with incorrect domain ownership
    error NotAllowedSystemContractException(bytes32 bytecodeHash);

    /// @notice Thrown when trying to deploy contract with incorrect contract type
    error ContractTypeVersionAlreadyExistsException();

    error OnlyAuthorCanSyncException();

    error AuditorAlreadySignedException();

    error NoValidAuditorSignatureException();

    error InvalidAuthorSignatureException();
    //
    // EVENTS
    //

    // Emitted when new smart contract was deployed
    event DeployContract(
        address indexed addr, bytes32 indexed bytecodeHash, string contractType, uint256 indexed version
    );

    // Event emitted when a new auditor is added to the repository
    event AddAuditor(address indexed auditor, string name);

    // Event emitted when an auditor is forbidden from the repository
    event RemoveAuditor(address indexed auditor);

    // Event emitted when new bytecode is uploaded to the repository
    event UploadBytecode(
        bytes32 indexed bytecodeHash,
        string contractType,
        uint256 indexed version,
        address indexed author,
        string source
    );

    // Event emitted when bytecode is signed by an auditor
    event AuditBytecode(bytes32 indexed bytecodeHash, address indexed auditor, string reportUrl, bytes signature);

    // Event emitted when a public domain is added
    event AddPublicDomain(bytes32 indexed domain);

    // Event emitted when a public domain is removed
    event RemovePublicDomain(bytes32 indexed domain);

    // Event emitted when contract type owner is removed
    event RemoveContractTypeOwner(bytes32 indexed contractType);

    // Event emitted when bytecode is forbidden
    event ForbidBytecode(bytes32 indexed bytecodeHash);

    // Event emitted when token specific postfix is set
    event SetTokenSpecificPostfix(address indexed token, bytes32 indexed postfix);

    // Event emitted when bytecode is approved
    event ApproveContract(bytes32 indexed bytecodeHash, bytes32 indexed contractType, uint256 version);

    // Event emitted when bytecode is revoked
    event RevokeApproval(bytes32 indexed bytecodeHash, bytes32 indexed contractType, uint256 version);

    // FUNCTIONS

    function deploy(bytes32 type_, uint256 version_, bytes memory constructorParams, bytes32 salt)
        external
        returns (address);

    function computeAddress(
        bytes32 type_,
        uint256 version_,
        bytes memory constructorParams,
        bytes32 salt,
        address deployer
    ) external view returns (address);

    function getTokenSpecificPostfix(address token) external view returns (bytes32);

    function getLatestVersion(bytes32 type_) external view returns (uint256);

    function getLatestMinorVersion(bytes32 type_, uint256 majorVersion) external view returns (uint256);

    function getLatestPatchVersion(bytes32 type_, uint256 minorVersion) external view returns (uint256);

    /// @notice Computes a unique hash for bytecode metadata
    function computeBytecodeHash(Bytecode calldata bytecode) external pure returns (bytes32);

    /// @notice Uploads new bytecode to the repository
    function uploadBytecode(Bytecode calldata bytecode) external;

    /// @notice Allows auditors to sign bytecode metadata
    function signBytecodeHash(bytes32 bytecodeHash, string calldata reportUrl, bytes memory signature) external;

    /// @notice Allows owner to mark contracts as system contracts
    function allowSystemContract(bytes32 bytecodeHash) external;

    /// @notice Adds a new auditor
    function addAuditor(address auditor, string memory name) external;

    /// @notice Removes an auditor
    function removeAuditor(address auditor) external;

    /// @notice Checks if an address is an approved auditor
    function isAuditor(address auditor) external view returns (bool);

    /// @notice Returns list of all approved auditors
    function getAuditors() external view returns (address[] memory);

    /// @notice Adds a new public domain
    function addPublicDomain(bytes32 domain) external;

    /// @notice Removes a public domain
    function removePublicDomain(bytes32 domain) external;

    /// @notice Marks initCode as forbidden
    function forbidInitCode(bytes32 initCodeHash) external;

    /// @notice Sets token-specific postfix
    function setTokenSpecificPostfix(address token, bytes32 postfix) external;

    /// @notice Removes contract type owner
    function removeContractTypeOwner(bytes32 contractType) external;

    /// @notice Revokes approval for a specific bytecode
    function revokeApproval(bytes32 contractType, uint256 version, bytes32 bytecodeHash) external;

    /// @notice Checks if a contract name belongs to public domain
    function isInPublicDomain(bytes32 contractType) external view returns (bool);

    /// @notice Checks if a domain is public
    function isPublicDomain(bytes32 domain) external view returns (bool);

    /// @notice Returns list of all public domains
    function listPublicDomains() external view returns (bytes32[] memory);

    /// @notice Gets bytecode metadata by hash
    function bytecodeByHash(bytes32 hash) external view returns (Bytecode memory);

    /// @notice Gets approved bytecode hash for contract type and version
    function approvedBytecodeHash(bytes32 contractType, uint256 version) external view returns (bytes32);

    /// @notice Gets deployed contract's bytecode hash
    function deployedContracts(address contractAddress) external view returns (bytes32);

    /// @notice Checks if initCode is forbidden
    function forbiddenInitCode(bytes32 initCodeHash) external view returns (bool);

    /// @notice Checks if contract is allowed as system contract
    function allowedSystemContracts(bytes32 bytecodeHash) external view returns (bool);

    /// @notice Gets contract type owner
    function contractTypeOwner(bytes32 contractType) external view returns (address);

    /// @notice Gets auditor name
    function auditorName(address auditor) external view returns (string memory);

    /// @notice Gets auditor signatures for a bytecode hash
    function auditorSignaturesByHash(bytes32 bytecodeHash) external view returns (AuditorSignature[] memory);

    /// @notice Gets specific auditor signature for a bytecode hash
    function auditorSignaturesByHash(bytes32 bytecodeHash, uint256 index)
        external
        view
        returns (AuditorSignature memory);

    /// @notice Checks if bytecode is uploaded
    function isBytecodeUploaded(bytes32 bytecodeHash) external view returns (bool);

    /// @notice Checks if initCode is forbidden and reverts if it is
    function revertIfInitCodeForbidden(bytes memory initCode) external view;

    /// @notice Checks if bytecode is audited
    function isAuditBytecode(bytes32 bytecodeHash) external view returns (bool);

    function BYTECODE_TYPEHASH() external view returns (bytes32);
}
