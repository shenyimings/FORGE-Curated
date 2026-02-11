// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.22;

import { MerkleProof } from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { MultiSig } from "./MultiSig.sol";
import { ExecutorStore } from "./ExecutorStore.sol";

/**
 * @title OneSig
 * @author @TRileySchwarz, @Clearwood, @HansonYip, @mok-lz
 * @notice A multi-chain enabled contract that uses a Merkle tree of transaction leaves.
 *         It allows transactions to be signed once (off-chain) and then executed on multiple chains,
 *         provided the Merkle proof is valid and the threshold of signers is met.
 * @dev Inherits from MultiSig for signature threshold logic.
 */
contract OneSig is MultiSig, ReentrancyGuard, ExecutorStore {
    /// @notice The version string of the OneSig contract.
    string public constant VERSION = "0.0.1";

    uint8 public constant LEAF_ENCODING_VERSION = 1;

    /**
     * @dev EIP-191 defines the format of the signature prefix.
     *      See https://eips.ethereum.org/EIPS/eip-191
     */
    string private constant EIP191_PREFIX_FOR_EIP712 = "\x19\x01";

    /**
     * @dev EIP-712 domain separator type-hash.
     *      See https://eips.ethereum.org/EIPS/eip-712
     */
    bytes32 private constant EIP712DOMAIN_TYPE_HASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    /**
     * @dev This domain separator is used to generate a signature hash for the merkle root,
     *      specifically using chainId = 1 (Ethereum Mainnet) and verifyingContract = 0xdEaD.
     *      This ensures that the same merkle root signatures can be used across different chains
     *      because they are all signed with this consistent "fake" domain.
     *
     *      In other words, to verify the merkle root with the same signatures on different chains,
     *      we use the same chainId (1) and verifyingContract (0xdEaD) in the EIP-712 domain.
     */
    bytes32 private constant DOMAIN_SEPARATOR =
        keccak256(
            abi.encode(
                EIP712DOMAIN_TYPE_HASH,
                keccak256(bytes("OneSig")), // this contract name
                keccak256(bytes(VERSION)), // version
                1, // Ethereum mainnet chainId
                address(0xdEaD) // verifyingContract
            )
        );

    /**
     * @dev The type-hash of the data being signed to authorize a merkle root.
     */
    bytes32 private constant SIGN_MERKLE_ROOT_TYPE_HASH =
        keccak256("SignMerkleRoot(bytes32 seed,bytes32 merkleRoot,uint256 expiry)");

    /**
     * @notice The OneSig ID of the contract.
     * @dev Because the oneSigId is part of the leaf, the same signatures can be used on different chains,
     *      while leaving each transaction to be targeted towards one
     */
    uint64 public immutable ONE_SIG_ID;

    /**
     * @notice A random seed encoded into the signatures/root.
     * @dev Allows for a previously signed, but unexecuted, transaction(s) to be 'revoked' by changing the seed.
     */
    bytes32 public seed;

    /**
     * @notice A sequential nonce to prevent replay attacks and enforce transaction ordering.
     */
    uint64 public nonce;

    /// @notice Emitted when the seed is updated.
    event SeedSet(bytes32 seed);

    /// @notice Emitted when a transaction is executed.
    /// @param merkleRoot The merkle root used to authorize the transaction.
    /// @param nonce The nonce of the transaction.
    event TransactionExecuted(bytes32 merkleRoot, uint256 nonce);

    /// @notice Error thrown when a merkle proof is invalid or the nonce does not match the expected value.
    error InvalidProofOrNonce();

    /// @notice Error thrown when a merkle root has expired (past the _expiry timestamp).
    error MerkleRootExpired();

    /// @notice Error thrown when a call in the transaction array fails.
    /// @param index The index of the failing call within the transaction.
    error ExecutionFailed(uint256 index);

    /// @notice Error thrown when a function is not called from an executor or signer.
    error OnlyExecutorOrSigner();

    /**
     * @notice Call to be executed as part of a Transaction.calls.
     *  - OneSig -> [Arbitrary contract].
     *  - e.g., setPeer(dstEid, remoteAddress).
     * @param to Address of the contract for this data to be 'called' on.
     * @param value Amount of ether to send with this call.
     * @param data Encoded data to be sent to the contract (calldata).
     */
    struct Call {
        address to;
        uint256 value;
        bytes data;
    }

    /**
     * @notice Single call to the OneSig contract (address(this)).
     *  - EOA -> OneSig
     *  - This struct is 1:1 with a 'leaf' in the merkle tree.
     *  - Execution of the underlying calls are atomic.
     *  - Cannot be processed until the previous leaf (nonce-ordered) has been executed successfully.
     * @param calls List of calls to be made.
     * @param proof Merkle proof to verify the transaction.
     */
    struct Transaction {
        Call[] calls;
        bytes32[] proof;
    }

    /**
     * @dev Restricts access to functions so they can only be called via an executor, OR a multisig signer.
     */
    modifier onlyExecutorOrSigner() {
        if (!canExecuteTransaction(msg.sender)) revert OnlyExecutorOrSigner();
        _;
    }

    /**
     * @notice Constructor to initialize the OneSig contract.
     * @dev Inherits MultiSig(_signers, _threshold).
     * @param _oneSigId A unique identifier per deployment, (typically block.chainid).
     * @param _signers The list of signers authorized to sign transactions.
     * @param _threshold The initial threshold of signers required to execute a transaction.
     * @param _executors The list of executors authorized to execute transactions.
     * @param _executorRequired If executors are required to execute transactions.
     * @param _seed The random seed to encode into the signatures/root.
     */
    constructor(
        uint64 _oneSigId,
        address[] memory _signers,
        uint256 _threshold,
        address[] memory _executors,
        bool _executorRequired,
        bytes32 _seed
    ) MultiSig(_signers, _threshold) ExecutorStore(_executors, _executorRequired) {
        ONE_SIG_ID = _oneSigId;
        _setSeed(_seed);
    }

    /**
     * @notice Internal method to set the contract's seed.
     * @param _seed The new seed value.
     */
    function _setSeed(bytes32 _seed) internal virtual {
        seed = _seed;
        emit SeedSet(_seed);
    }

    /**
     * @notice Sets the contract's seed.
     * @dev Only callable via MultiSig functionality (i.e., requires threshold signatures from signers).
     * @param _seed The new seed value.
     */
    function setSeed(bytes32 _seed) public virtual onlySelfCall {
        _setSeed(_seed);
    }

    /**
     * @notice Executes a single transaction (which corresponds to a leaf in the merkle tree) if valid signatures are provided.
     * @dev '_transaction' corresponds 1:1 with a leaf. This function can be called by anyone (permissionless),
     *      provided the merkle root is verified with sufficient signatures.
     * @param _transaction The transaction data struct, including calls and proof.
     * @param _merkleRoot The merkle root that authorizes this transaction.
     * @param _expiry The timestamp after which the merkle root expires.
     * @param _signatures Signatures from signers that meet the threshold.
     */
    function executeTransaction(
        Transaction calldata _transaction,
        bytes32 _merkleRoot,
        uint256 _expiry,
        bytes calldata _signatures
    ) public payable virtual nonReentrant onlyExecutorOrSigner {
        // Verify the merkle root and signatures
        verifyMerkleRoot(_merkleRoot, _expiry, _signatures);

        // Verify that this transaction matches the merkle root (using its proof)
        verifyTransactionProof(_merkleRoot, _transaction);

        // Increment nonce before execution to prevent replay
        uint256 n = nonce++;

        // Execute all calls atomically
        for (uint256 i = 0; i < _transaction.calls.length; i++) {
            (bool success, ) = _transaction.calls[i].to.call{ value: _transaction.calls[i].value }(
                _transaction.calls[i].data
            );

            // Revert if the call fails
            if (!success) revert ExecutionFailed(i);
        }

        emit TransactionExecuted(_merkleRoot, n);
    }

    /**
     * @notice Validates the signatures on a given merkle root.
     * @dev Reverts if the merkle root is expired or signatures do not meet the threshold.
     * @param _merkleRoot The merkle root to verify.
     * @param _expiry The timestamp after which the merkle root becomes invalid.
     * @param _signatures The provided signatures.
     */
    function verifyMerkleRoot(bytes32 _merkleRoot, uint256 _expiry, bytes calldata _signatures) public view {
        // Check expiry
        if (block.timestamp > _expiry) revert MerkleRootExpired();

        // Compute the EIP-712 hash
        bytes32 digest = keccak256(
            abi.encodePacked(
                EIP191_PREFIX_FOR_EIP712,
                DOMAIN_SEPARATOR,
                keccak256(abi.encode(SIGN_MERKLE_ROOT_TYPE_HASH, seed, _merkleRoot, _expiry))
            )
        );

        // Verify the threshold signatures
        verifySignatures(digest, _signatures);
    }

    /**
     * @notice Verifies that the provided merkle proof matches the current transaction leaf under the merkle root.
     * @dev Reverts if the proof is invalid or the nonce doesn't match the expected value.
     * @param _merkleRoot The merkle root being used.
     * @param _transaction The transaction data containing proof and calls.
     */
    function verifyTransactionProof(bytes32 _merkleRoot, Transaction calldata _transaction) public view {
        bytes32 leaf = encodeLeaf(nonce, _transaction.calls);
        bool valid = MerkleProof.verifyCalldata(_transaction.proof, _merkleRoot, leaf);
        if (!valid) revert InvalidProofOrNonce();
    }

    /**
     * @notice Double encodes the transaction leaf for inclusion in the merkle tree.
     * @param _nonce The nonce of the transaction.
     * @param _calls The calls to be made in this transaction.
     * @return The keccak256 hash of the encoded leaf.
     */
    function encodeLeaf(uint64 _nonce, Call[] calldata _calls) public view returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    keccak256(
                        abi.encodePacked(
                            LEAF_ENCODING_VERSION,
                            ONE_SIG_ID,
                            bytes32(uint256(uint160(address(this)))), // convert address(this) into bytes32
                            _nonce,
                            abi.encode(_calls)
                        )
                    )
                )
            );
    }

    /**
     * @notice Checks if the a given address can execute a transaction.
     * @param _sender The address of the message sender.
     * @return True if executeTransaction can be called by the executor, otherwise false.
     */
    function canExecuteTransaction(address _sender) public view returns (bool) {
        // If the flag is set to false, then ANYONE can execute permissionlessly, otherwise the msg.sender must be a executor, or a signer
        return (!executorRequired || isExecutor(_sender) || isSigner(_sender));
    }

    /**
     * @notice Fallback function to receive ether.
     * @dev Allows the contract to accept ETH.
     */
    receive() external payable {}
}
