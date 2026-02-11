// SPDX-License-Identifier: BUSL-1.1
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2024.
pragma solidity ^0.8.23;

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {LibString} from "@solady/utils/LibString.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {SignedProposal, CrossChainCall} from "../interfaces/ICrossChainMultisig.sol";
import {IVersion} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IVersion.sol";

import {LibString} from "@solady/utils/LibString.sol";
import {EIP712Mainnet} from "../helpers/EIP712Mainnet.sol";

import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {ICrossChainMultisig} from "../interfaces/ICrossChainMultisig.sol";

import {AP_CROSS_CHAIN_MULTISIG} from "../libraries/ContractLiterals.sol";

contract CrossChainMultisig is EIP712Mainnet, Ownable, ReentrancyGuard, ICrossChainMultisig {
    using EnumerableSet for EnumerableSet.AddressSet;
    using EnumerableSet for EnumerableSet.Bytes32Set;
    using LibString for bytes32;
    using LibString for string;
    using LibString for uint256;

    /// @notice Meta info about contract type & version
    uint256 public constant override version = 3_10;
    bytes32 public constant override contractType = AP_CROSS_CHAIN_MULTISIG;

    // EIP-712 type hash for Proposal only
    bytes32 public constant CROSS_CHAIN_CALL_TYPEHASH =
        keccak256("CrossChainCall(uint256 chainId,address target,bytes callData)");
    bytes32 public constant PROPOSAL_TYPEHASH = keccak256("Proposal(string name,bytes32 proposalHash,bytes32 prevHash)");

    uint8 public confirmationThreshold;

    bytes32 public lastProposalHash;

    EnumerableSet.AddressSet internal _signers;

    bytes32[] internal _executedProposalHashes;

    mapping(bytes32 => EnumerableSet.Bytes32Set) internal _connectedProposalHashes;
    mapping(bytes32 => SignedProposal) internal _signedProposals;

    modifier onlyOnMainnet() {
        if (block.chainid != 1) revert CantBeExecutedOnCurrentChainException();
        _;
    }

    modifier onlyOnNotMainnet() {
        if (block.chainid == 1) revert CantBeExecutedOnCurrentChainException();
        _;
    }

    modifier onlySelf() {
        if (msg.sender != address(this)) revert OnlySelfException();
        _;
    }

    // It's deployed with the same set of parameters on all chains, so it's qddress should be the same
    // @param: initialSigners - Array of initial signers
    // @param: _confirmationThreshold - Confirmation threshold
    // @param: _owner - Owner of the contract. used on Mainnet only, however, it should be same on all chains
    // to make CREATE2 address the same on all chains
    constructor(address[] memory initialSigners, uint8 _confirmationThreshold, address _owner)
        EIP712Mainnet(contractType.fromSmallString(), version.toString())
        Ownable()
    {
        uint256 len = initialSigners.length;

        for (uint256 i = 0; i < len; ++i) {
            _addSigner(initialSigners[i]); // U:[SM-1]
        }

        _setConfirmationThreshold(_confirmationThreshold); // U:[SM-1]
        _transferOwnership(_owner); // U:[SM-1]
    }

    // @dev: Submit a new proposal
    // Executed by Gearbox DAO on Mainnet
    // @param: calls - Array of CrossChainCall structs
    // @param: prevHash - Hash of the previous proposal (zero if first proposal)
    function submitProposal(string calldata name, CrossChainCall[] calldata calls, bytes32 prevHash)
        external
        onlyOwner
        onlyOnMainnet
        nonReentrant
    {
        _verifyProposal({calls: calls, prevHash: prevHash});

        bytes32 proposalHash = hashProposal({name: name, calls: calls, prevHash: prevHash});

        // Copy proposal to storage
        SignedProposal storage signedProposal = _signedProposals[proposalHash];

        uint256 len = calls.length;
        for (uint256 i = 0; i < len; ++i) {
            signedProposal.calls.push(calls[i]);
        }
        signedProposal.prevHash = prevHash;
        signedProposal.name = name;

        _connectedProposalHashes[lastProposalHash].add(proposalHash);

        emit SubmitProposal(proposalHash);
    }

    // @dev: Sign a proposal
    // Executed by any signer to make cross-chain distribution possible
    // @param: proposalHash - Hash of the proposal to sign
    // @param: signature - Signature of the proposal
    function signProposal(bytes32 proposalHash, bytes calldata signature) external onlyOnMainnet nonReentrant {
        SignedProposal storage signedProposal = _signedProposals[proposalHash];
        if (signedProposal.prevHash != lastProposalHash) {
            revert InvalidPrevHashException();
        }
        bytes32 digest =
            _hashTypedDataV4(computeSignProposalHash(signedProposal.name, proposalHash, signedProposal.prevHash));

        address signer = ECDSA.recover(digest, signature);
        if (!_signers.contains(signer)) revert SignerDoesNotExistException();

        signedProposal.signatures.push(signature);

        uint256 validSignatures = _verifySignatures({signatures: signedProposal.signatures, digest: digest});

        emit SignProposal(proposalHash, signer);

        if (validSignatures >= confirmationThreshold) {
            _verifyProposal({calls: signedProposal.calls, prevHash: signedProposal.prevHash});
            _executeProposal({calls: signedProposal.calls, proposalHash: proposalHash});
        }
    }

    // @dev: Execute a proposal on other chain permissionlessly
    function executeProposal(SignedProposal calldata signedProposal) external onlyOnNotMainnet nonReentrant {
        bytes32 proposalHash = hashProposal(signedProposal.name, signedProposal.calls, signedProposal.prevHash);

        // Check proposal is valid
        _verifyProposal({calls: signedProposal.calls, prevHash: signedProposal.prevHash});

        bytes32 digest =
            _hashTypedDataV4(computeSignProposalHash(signedProposal.name, proposalHash, signedProposal.prevHash));

        // Check if enough signatures are valid
        uint256 validSignatures = _verifySignatures({signatures: signedProposal.signatures, digest: digest});
        if (validSignatures < confirmationThreshold) revert NotEnoughSignaturesException();

        _executeProposal({calls: signedProposal.calls, proposalHash: proposalHash});
    }

    function _verifyProposal(CrossChainCall[] memory calls, bytes32 prevHash) internal view {
        if (prevHash != lastProposalHash) revert InvalidPrevHashException();
        if (calls.length == 0) revert NoCallsInProposalException();

        uint256 len = calls.length;
        for (uint256 i = 0; i < len; ++i) {
            CrossChainCall memory call = calls[i];
            if (call.chainId != 0 && call.target == address(this)) {
                revert InconsistentSelfCallOnOtherChainException();
            }
        }
    }

    function _verifySignatures(bytes[] memory signatures, bytes32 digest)
        internal
        view
        returns (uint256 validSignatures)
    {
        address[] memory proposalSigners = new address[](signatures.length);
        // Check for duplicate signatures
        uint256 len = signatures.length;

        for (uint256 i = 0; i < len; ++i) {
            address signer = ECDSA.recover(digest, signatures[i]);

            // It's not reverted to avoid the case, when 2 proposals are submitted
            // and the first one is about removing a signer. The signer could add his signature
            // to the second proposal (it's still possible) and lock the system forever
            if (_signers.contains(signer)) {
                validSignatures++;
            }
            for (uint256 j = 0; j < i; ++j) {
                if (proposalSigners[j] == signer) {
                    revert AlreadySignedException();
                }
            }
            proposalSigners[i] = signer;
        }
    }

    // @dev: Execute proposal calls and update state
    // @param: calls - Array of cross-chain calls to execute
    // @param: proposalHash - Hash of the proposal being executed
    function _executeProposal(CrossChainCall[] memory calls, bytes32 proposalHash) internal {
        // Execute each call in the proposal
        uint256 len = calls.length;
        for (uint256 i = 0; i < len; ++i) {
            CrossChainCall memory call = calls[i];
            uint256 chainId = call.chainId;

            if (chainId == 0 || chainId == block.chainid) {
                // QUESTION: add try{} catch{} to achieve 100% execution
                Address.functionCall(call.target, call.callData, "Call execution failed");
            }
        }

        _executedProposalHashes.push(proposalHash);
        lastProposalHash = proposalHash;

        emit ExecuteProposal(proposalHash);
    }

    //
    // MULTISIG CONFIGURATION FUNCTIONS
    //

    // @notice: Add a new signer to the multisig
    // @param: newSigner - Address of the new signer
    function addSigner(address newSigner) external onlySelf {
        _addSigner(newSigner);
    }

    function _addSigner(address newSigner) internal {
        if (!_signers.add(newSigner)) revert SignerAlreadyExistsException();
        emit AddSigner(newSigner);
    }

    // @notice: Remove a signer from the multisig
    // @param: signer - Address of the signer to remove
    function removeSigner(address signer) external onlySelf {
        if (!_signers.remove(signer)) revert SignerDoesNotExistException();
        emit RemoveSigner(signer);
    }

    // @notice: Set the confirmation threshold for the multisig
    // @param: newConfirmationThreshold - New confirmation threshold
    function setConfirmationThreshold(uint8 newConfirmationThreshold) external onlySelf {
        _setConfirmationThreshold(newConfirmationThreshold);
    }

    function _setConfirmationThreshold(uint8 newConfirmationThreshold) internal {
        if (newConfirmationThreshold == 0 || newConfirmationThreshold > _signers.length()) {
            revert InvalidConfirmationThresholdValueException();
        }
        confirmationThreshold = newConfirmationThreshold; // U:[SM-1]
        emit SetConfirmationThreshold(newConfirmationThreshold); // U:[SM-1]
    }

    //
    // HELPERS
    //
    function hashProposal(string calldata name, CrossChainCall[] calldata calls, bytes32 prevHash)
        public
        pure
        returns (bytes32)
    {
        bytes32[] memory callsHash = new bytes32[](calls.length);
        uint256 len = calls.length;
        for (uint256 i = 0; i < len; ++i) {
            CrossChainCall memory call = calls[i];
            callsHash[i] = keccak256(abi.encode(CROSS_CHAIN_CALL_TYPEHASH, call.chainId, call.target, call.callData));
        }

        return keccak256(abi.encode(keccak256(bytes(name)), keccak256(abi.encodePacked(callsHash)), prevHash));
    }

    function computeSignProposalHash(string memory name, bytes32 proposalHash, bytes32 prevHash)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(PROPOSAL_TYPEHASH, keccak256(bytes(name)), proposalHash, prevHash));
    }

    //
    // GETTERS
    //
    function getCurrentProposalHashes() external view returns (bytes32[] memory) {
        return _connectedProposalHashes[lastProposalHash].values();
    }

    function getCurrentProposals() external view returns (SignedProposal[] memory result) {
        uint256 len = _connectedProposalHashes[lastProposalHash].length();
        result = new SignedProposal[](len);
        for (uint256 i = 0; i < len; ++i) {
            result[i] = _signedProposals[_connectedProposalHashes[lastProposalHash].at(i)];
        }
    }

    function getSigners() external view returns (address[] memory) {
        return _signers.values();
    }

    function getExecutedProposals() external view returns (SignedProposal[] memory result) {
        uint256 len = _executedProposalHashes.length;
        result = new SignedProposal[](len);
        for (uint256 i = 0; i < len; ++i) {
            result[i] = _signedProposals[_executedProposalHashes[i]];
        }
    }

    function getProposal(bytes32 proposalHash) external view returns (SignedProposal memory result) {
        return _signedProposals[proposalHash];
    }

    function getExecutedProposalHashes() external view returns (bytes32[] memory) {
        return _executedProposalHashes;
    }

    function isSigner(address account) external view returns (bool) {
        return _signers.contains(account);
    }

    function getSignedProposal(bytes32 proposalHash) external view returns (SignedProposal memory) {
        return _signedProposals[proposalHash];
    }

    function domainSeparatorV4() external view returns (bytes32) {
        return _domainSeparatorV4();
    }
}
