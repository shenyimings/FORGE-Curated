// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2024.
pragma solidity ^0.8.23;

import {CrossChainCall, SignedProposal} from "./Types.sol";
import {IVersion} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IVersion.sol";

interface ICrossChainMultisig is IVersion {
    //
    // Events
    //
    /// @notice Emitted when a new signer is added to the multisig
    /// @param signer Address of the newly added signer
    event AddSigner(address indexed signer);

    /// @notice Emitted when a signer is removed from the multisig
    /// @param signer Address of the removed signer
    event RemoveSigner(address indexed signer);

    /// @notice Emitted when the confirmation threshold is updated
    /// @param newconfirmationThreshold New number of required signatures
    event SetConfirmationThreshold(uint8 newconfirmationThreshold);

    /// @notice Emitted when a new proposal is submitted
    /// @param proposalHash Hash of the submitted proposal
    event SubmitProposal(bytes32 indexed proposalHash);

    /// @notice Emitted when a signer signs a proposal
    /// @param proposalHash Hash of the signed proposal
    /// @param signer Address of the signer
    event SignProposal(bytes32 indexed proposalHash, address indexed signer);

    /// @notice Emitted when a proposal is successfully executed
    /// @param proposalHash Hash of the executed proposal
    event ExecuteProposal(bytes32 indexed proposalHash);

    // Errors

    /// @notice Thrown when an invalid confirmation threshold is set
    error InvalidconfirmationThresholdException();

    /// @notice Thrown when a signer attempts to sign a proposal multiple times
    error AlreadySignedException();

    /// @notice Thrown when the previous proposal hash doesn't match the expected value
    error InvalidPrevHashException();

    /// @notice Thrown when trying to interact with a non-existent proposal
    error ProposalDoesNotExistException();

    /// @notice Thrown when trying to add a signer that already exists
    error SignerAlreadyExistsException();

    /// @notice Thrown when trying to remove a non-existent signer
    error SignerDoesNotExistException();

    /// @notice Thrown when trying to execute a proposal on the wrong chain
    error CantBeExecutedOnCurrentChainException();

    /// @notice Thrown when a restricted function is called by non-multisig address
    error OnlySelfException();

    /// @notice Thrown when submitting a proposal with no calls
    error NoCallsInProposalException();

    /// @notice Thrown when trying to execute a proposal with insufficient signatures
    error NotEnoughSignaturesException();

    /// @notice Thrown when self-calls are inconsistent with the target chain
    error InconsistentSelfCallOnOtherChainException();

    /// @notice Thrown when setting an invalid confirmation threshold value
    error InvalidConfirmationThresholdValueException();

    /// @notice Submits a new proposal to the multisig
    /// @param calls Array of cross-chain calls to be executed
    /// @param prevHash Hash of the previous proposal (for ordering)
    function submitProposal(string calldata name, CrossChainCall[] calldata calls, bytes32 prevHash) external;

    /// @notice Allows a signer to sign a submitted proposal
    /// @param proposalHash Hash of the proposal to sign
    /// @param signature Signature of the signer
    function signProposal(bytes32 proposalHash, bytes calldata signature) external;

    /// @notice Executes a proposal once it has enough signatures
    /// @param proposal The signed proposal to execute
    function executeProposal(SignedProposal calldata proposal) external;

    /// @notice Adds a new signer to the multisig
    /// @param signer Address of the signer to add
    function addSigner(address signer) external;

    /// @notice Removes a signer from the multisig
    /// @param signer Address of the signer to remove
    function removeSigner(address signer) external;

    /// @notice Sets a new confirmation threshold
    /// @param newThreshold New threshold value
    function setConfirmationThreshold(uint8 newThreshold) external;

    /// @notice Hashes a proposal according to EIP-712
    /// @param name Name of the proposal
    /// @param calls Array of cross-chain calls
    /// @param prevHash Hash of the previous proposal
    /// @return bytes32 Hash of the proposal
    function hashProposal(string calldata name, CrossChainCall[] calldata calls, bytes32 prevHash)
        external
        view
        returns (bytes32);

    //
    // GETTERS
    //

    /// @notice Returns the current confirmation threshold
    function confirmationThreshold() external view returns (uint8);

    /// @notice Returns the hash of the last executed proposal
    function lastProposalHash() external view returns (bytes32);

    /// @notice Returns the signed proposal details for a given hash
    function getSignedProposal(bytes32 proposalHash) external view returns (SignedProposal memory);

    /// @notice Returns all currently pending proposals
    function getCurrentProposals() external view returns (SignedProposal[] memory);

    /// @notice Returns all executed proposals
    function getExecutedProposals() external view returns (SignedProposal[] memory);

    /// @notice Returns the array of executed proposal hashes
    function getExecutedProposalHashes() external view returns (bytes32[] memory);

    /// @notice Returns a single executed proposal
    function getProposal(bytes32 proposalHash) external view returns (SignedProposal memory);

    /// @notice Returns the list of current signers
    function getSigners() external view returns (address[] memory);

    /// @notice Checks if an address is a signer
    /// @param account Address to check
    function isSigner(address account) external view returns (bool);

    /// @notice Returns the domain separator used for EIP-712 signing
    function domainSeparatorV4() external view returns (bytes32);
}
