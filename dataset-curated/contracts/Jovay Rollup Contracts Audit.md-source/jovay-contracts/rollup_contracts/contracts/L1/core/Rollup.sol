// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../interfaces/IRollup.sol";
import "../libraries/codec/BatchHeaderCodec.sol";
import "../libraries/verifier/ITeeRollupVerifier.sol";
import "../libraries/verifier/IZkRollupVerifier.sol";

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {IL1MailQueue} from "../interfaces/IL1MailQueue.sol";


contract Rollup is IRollup, OwnableUpgradeable, PausableUpgradeable {

    error NotSupportZkProof();

    /// @notice The max number of txs in a chunk, fill by bytes32(0) if not enough.
    uint32 public maxTxsInChunk;

    /// @notice The max number of blocks in a chunk, not need fill by (0) if not enough.
    uint32 public maxBlockInChunk;

    /// @notice The max tx data size in a chunk;
    uint32 public maxCallDataInChunk;

    /// @notice The max zk circle in a chunk;
    uint32 public maxZkCircleInChunk;

    /// @notice The max tx data (byte) limit in L1;
    uint32 public l1BlobNumberLimit;

    /// @notice Time limit between two rollups;
    uint64 public rollupTimeLimit;

    /// @notice The chain id of the corresponding layer 2 chain.
    uint64 public layer2ChainId;

    // The batch index that has been committed;
    uint256 public lastCommittedBatch;

    // The batch index that has been zk verified;
    uint256 public lastZkVerifiedBatch;

    // The batch index that has been tee verified;
    uint256 public lastTeeVerifiedBatch;

    // Record the batchhash corresponding to the batch
    mapping(uint256 => bytes32) public committedBatches;

    // Record the stateroot corresponding to each batch of L2 and the stateroot of the last block of the batch
    mapping(uint256 => bytes32) public finalizedStateRoots;

    // batchindex corresponds to the root of the L2withroot message tree; it is used to verify L2 transactions;
    mapping(uint256 => bytes32) public l2MsgRoots;

    // total pop l1msg of batch;
    mapping(uint256 => uint256) public l1MsgCount;

    address public zk_verifier;  // zk_verifier contract address, compatibility operations such as upgrades are handled by the verifier contract
    address public tee_verifier;  // tee_verifier contract address, compatibility operations such as upgrades are handled by the verifier contract
    address public l1_mail_box;   // mail box address; L1 Msg Rolling hash storage in it

    /// @notice Whether an account is a relayer.
    mapping(address => bool) public isRelayer;

    /**********************
     * Function Modifiers *
     **********************/

    modifier OnlyRelayer() {
        // @note In the decentralized mode, it should be only called by a list of validator.
        require(isRelayer[_msgSender()], "INVALID_PERMISSION : sender is not relayer");
        _;
    }

    /***************
     * Constructor *
     ***************/

//    /// @notice Constructor implementation .
    constructor(
    ) {
        _disableInitializers();
    }

    function initialize(
        uint64 _chainId,
        address _zk_verifier,
        address _tee_verifier,
        address _l1_mail_box,
        uint32 _maxTxsInChunk,
        uint32 _maxBlockInChunk,
        uint32 _maxCallDataInChunk,
        uint32 _maxZkCircleInChunk,
        uint32 _l1BlobNumberLimit,
        uint32 _rollupTimeLimit
    ) public initializer {
        OwnableUpgradeable.__Ownable_init();
        PausableUpgradeable.__Pausable_init();

        require(_zk_verifier != address(0) || _tee_verifier != address(0), "INVALID_PARAMETER : must specify one verifier address");
        layer2ChainId = _chainId;
        zk_verifier = _zk_verifier;
        tee_verifier = _tee_verifier;
        l1_mail_box = _l1_mail_box;
        maxTxsInChunk = _maxTxsInChunk;
        maxBlockInChunk = _maxBlockInChunk;
        maxCallDataInChunk = _maxCallDataInChunk;
        maxZkCircleInChunk = _maxZkCircleInChunk;
        l1BlobNumberLimit = _l1BlobNumberLimit;
        rollupTimeLimit = _rollupTimeLimit;
    }

    /*****************************
     * Public Mutating Functions *
     *****************************/
    /// @notice Import layer 2 genesis block
    /// @param _batchHeader The header of the genesis batch.
    /// @param _stateRoot The state root of the genesis block.
    function importGenesisBatch(bytes calldata _batchHeader, bytes32 _stateRoot) external onlyOwner {
        // check genesis batch header length
        require(_stateRoot != bytes32(0), "INVALID_PARAMETER : state root is zero");

        // check whether the genesis batch is imported
        require(finalizedStateRoots[0] == bytes32(0), "INVALID_PARAMETER : genesis batch is imported");

        (uint256 memPtr, , bytes32 _batchHash, ) = _loadBatchHeader(_batchHeader);

        // check all fields except `dataHash` and `lastBlockHash` are zero
        unchecked {
            uint256 sum = BatchHeaderCodec.version(memPtr) +
                                BatchHeaderCodec.batchIndex(memPtr);
            require(sum == 0, "INVALID_PARAMETER : genesis batch has no zero field");
            require(BatchHeaderCodec.l1RollingHash(memPtr) == bytes32(0), "INVALID_PARAMETER : genesis batch rolling hash must be zero");
            require(BatchHeaderCodec.dataHash(memPtr) != bytes32(0), "INVALID_PARAMETER : genesis batch data hash is zero");
            require(BatchHeaderCodec.parentBatchHash(memPtr) == bytes32(0), "INVALID_PARAMETER : genesis parent batch hash must be zero");
        }
        committedBatches[0] = _batchHash;
        finalizedStateRoots[0] = _stateRoot;
        lastCommittedBatch = 0;
        lastZkVerifiedBatch = 0;
        lastTeeVerifiedBatch = 0;
        l1MsgCount[0] = 0;
        l2MsgRoots[0] = bytes32(0);
        emit CommitBatch( 0, _batchHash);
    }

    /// @inheritdoc IRollup
    function commitBatch(
        uint8 _version,
        uint256 _batchIndex,
        uint256 _totalL1MessagePopped
    ) external override OnlyRelayer whenNotPaused {
        require(_batchIndex == lastCommittedBatch + 1, "INVALID_PARAMETER : commit batch one by one");

        uint256 BATCH_HEADER_LENGTH = BatchHeaderCodec.BATCH_HEADER_FIXED_LENGTH;
        // init empty batch
        uint256 batchPtr;
        assembly {
            batchPtr := mload(0x40)
            mstore(0x40, add(batchPtr, BATCH_HEADER_LENGTH))
        }

        BatchHeaderCodec.storeVersion(batchPtr, _version);
        BatchHeaderCodec.storeBatchIndex(batchPtr, _batchIndex);
        BatchHeaderCodec.storeL1RollingHash(
            batchPtr,
            IL1MailQueue(l1_mail_box).getMsg(_totalL1MessagePopped)
        );
        BatchHeaderCodec.storeDataHash(batchPtr, _getBlobDataHash());
        BatchHeaderCodec.storeParentBatchHash(batchPtr, committedBatches[_batchIndex - 1]);
        // compute batch hash
        bytes32 _batchHash = BatchHeaderCodec.computeBatchHash(
            batchPtr,
            BatchHeaderCodec.BATCH_HEADER_FIXED_LENGTH
        );

        committedBatches[_batchIndex] = _batchHash;
        lastCommittedBatch =  _batchIndex;
        l1MsgCount[_batchIndex] = _totalL1MessagePopped;
        emit CommitBatch(_batchIndex, _batchHash);
    }

    /// @inheritdoc IRollup
    function verifyBatch(
        uint8 _prove_type,
        bytes calldata _batchHeader,
        bytes32 _postStateRoot,
        bytes32 _l2MsgRoot,
        bytes calldata _proof
    ) external override OnlyRelayer whenNotPaused {
        require(_prove_type == 0 || _prove_type == 1, "INVALID_PARAMETER : invalid prove type");
        require(_postStateRoot != bytes32(0), "INVALID_PARAMETER : invalid state root");
        uint256 _verifiedBatchIndex = _prove_type == 0 ? lastZkVerifiedBatch : lastTeeVerifiedBatch;

        // compute pending batch hash and verify
        (
            ,
            uint256 _batchIndex,
            bytes32 _batchHash,
        ) = _loadBatchHeader(_batchHeader);
        require(_batchIndex == _verifiedBatchIndex + 1, "INVALID_PARAMETER : invalid verify batch index, must one by one");
        require(committedBatches[_batchIndex] != bytes32(0) && committedBatches[_batchIndex] ==  _batchHash, "INVALID_PARAMETER : invalid commit batch hash");
        require(finalizedStateRoots[_batchIndex] == bytes32(0) || finalizedStateRoots[_batchIndex] == _postStateRoot, "INVALID_PARAMETER : invalid verify state root");
        bytes memory _publicInput = abi.encodePacked(
            layer2ChainId,
            finalizedStateRoots[_verifiedBatchIndex], // _prevStateRoot
            _postStateRoot,
            _batchHash,
            _l2MsgRoot
        );
        if (_prove_type == 0) {
            revert NotSupportZkProof();
        } else if (_prove_type == 1) {
            _verifyTeeProof(_proof, _publicInput);
        }

        // TODO : add finalize check
//        if ((_prove_type == 0 && lastTeeVerifiedBatch >= _batchIndex) || (_prove_type == 1 && lastZkVerifiedBatch >= _batchIndex)) {
        // after verify update contract storage
        if (finalizedStateRoots[_batchIndex] == bytes32(0)) {
            finalizedStateRoots[_batchIndex] = _postStateRoot;
        }
        l2MsgRoots[_batchIndex] = _l2MsgRoot;
        IL1MailQueue(l1_mail_box).popMsgs(l1MsgCount[_batchIndex]);
//        }
        emit VerifyBatch(_prove_type, _batchIndex, _batchHash, _postStateRoot, _l2MsgRoot);
    }

    /// @inheritdoc IRollup
    /// @dev If the owner want to revert a sequence of batches by sending multiple transactions,
    ///      make sure to revert recent batches first.
    /// can only revert L2; L1 can not be revert;
    function revertBatches(uint256 _newLastBatchIndex) external override onlyOwner {
        require(_newLastBatchIndex < lastCommittedBatch, "INVALID_PARAMETER : revert lastCommitBatchIndex must smaller than current");
        require(lastCommittedBatch - _newLastBatchIndex <= 100, "INVALID_PARAMETER : revert block number must smaller than 100 for gas limit");
        require(_newLastBatchIndex >= lastZkVerifiedBatch, "INVALID_PARAMETER : revert block number bigger than last zk verify block number");
        require(_newLastBatchIndex >= lastTeeVerifiedBatch, "INVALID_PARAMETER : revert block number bigger than last tee verify block number");

        // actual revert
        for (uint256 _batchIndex = lastCommittedBatch; _batchIndex > _newLastBatchIndex; --_batchIndex) {
            committedBatches[_batchIndex] = bytes32(0);
        }
        lastCommittedBatch = _newLastBatchIndex;
    }

    function getL2MsgRoot(uint256 batch_index) external view override returns (bytes32) {
        return l2MsgRoots[batch_index];
    }

    function _getBlobDataHash() internal virtual returns (bytes32 _blobDataHash) {
        uint32 blobNumberLimit = l1BlobNumberLimit;
        assembly {
            let dataStart := mload(0x40)
            let offset := 0
            let i := 0
            for {} lt(i, blobNumberLimit) { i := add(i, 1) } {
                let hash := blobhash(i)
                if iszero(hash) {
                    break
                }
                mstore(add(dataStart, offset), hash)
                offset := add(offset, 0x20)
            }
            _blobDataHash := keccak256(dataStart, offset)
            mstore(0x40, add(dataStart, offset))
        }
        emit BlobDataHash(_blobDataHash);
    }

    /// @dev Internal function to load batch header from calldata to memory.
    /// @param _batchHeader The batch header in calldata.
    /// @return memPtr The start memory offset of loaded batch header.
    /// @return _batchIndex The index of the loaded batch header.
    /// @return _batchHash The hash of the loaded batch header.
    /// @return _l1MsgRollingHash The rolling hash of L1 msg on this batch.
    function _loadBatchHeader(
        bytes calldata _batchHeader
    ) internal pure returns (uint256 memPtr, uint256 _batchIndex, bytes32 _batchHash, bytes32 _l1MsgRollingHash) {
        // load to memory
        uint256 _length;
        (memPtr, _length) = BatchHeaderCodec.loadAndValidate(_batchHeader);
        // compute batch hash
        _batchHash = BatchHeaderCodec.computeBatchHash(memPtr, _length);
        _batchIndex = BatchHeaderCodec.batchIndex(memPtr);
        _l1MsgRollingHash = BatchHeaderCodec.l1RollingHash(memPtr);
    }

    function _verifyTeeProof(bytes memory _proof, bytes memory _publicInput) internal {
        bytes32 _commitment = keccak256(_publicInput);
        (uint32 error_code, bytes32 commitment) = ITeeRollupVerifier(tee_verifier).verifyProof(_proof);
        require(error_code == 0, "ERROR : verify failed");
        require(commitment == _commitment, "ERROR : error tee commitment for verify");
        lastTeeVerifiedBatch = lastTeeVerifiedBatch + 1;
    }

    /************************
     * Restricted Functions *
     ************************/

    /// @notice Add an account to the relayer list.
    /// @param _account The address of account to add.
    function addRelayer(address _account) external onlyOwner {
        // @note Currently many external services rely on EOA sequencer to decode metadata directly from tx.calldata.
        // So we explicitly make sure the account is EOA.
        require(_account.code.length == 0, "INVALID_PERMISSION : relayer account must be a eoa");

        isRelayer[_account] = true;
    }

    /// @notice Remove an account from the relayer list.
    /// @param _account The address of account to remove.
    function removeRelayer(address _account) external onlyOwner {
        isRelayer[_account] = false;
    }

    /// @notice Pause the contract
    /// @param _status The pause status to update.
    function setPause(bool _status) external onlyOwner {
        if (_status) {
            _pause();
        } else {
            _unpause();
        }
    }

    /// @notice Set maxTxsInChunk of tx size in a chunk.
    /// @param _maxTxsInChunk The number of tx size in a chunk.
    function setMaxTxsInChunk(uint32 _maxTxsInChunk) external onlyOwner {
        maxTxsInChunk = _maxTxsInChunk;
    }

    /// @notice Set maxBlockInChunk of block size in a chunk.
    /// @param _maxBlockInChunk The number of block size in a chunk.
    function setMaxBlockInChunk(uint32 _maxBlockInChunk) external onlyOwner {
        maxBlockInChunk = _maxBlockInChunk;
    }

    /// @notice Set maxCallDataInChunk of tx data size in a chunk.
    /// @param _maxCallDataInChunk The number of tx data size in a chunk.
    function setMaxCallDataInChunk(uint32 _maxCallDataInChunk) external onlyOwner {
        maxCallDataInChunk = _maxCallDataInChunk;
    }

    /// @notice Set l1BlobNumberLimit of the limit of l1 tx data size.
    /// @param _l1BlobNumberLimit The limit of L1 tx data size.
    function setL1BlobNumberLimit(uint32 _l1BlobNumberLimit) external onlyOwner {
        l1BlobNumberLimit = _l1BlobNumberLimit;
    }

    /// @notice Set rollupTimeLimit of the limit of l1 tx data size.
    /// @param _rollupTimeLimit The limit of L1 tx data size.
    function setRollupTimeLimit(uint32 _rollupTimeLimit) external onlyOwner {
        rollupTimeLimit = _rollupTimeLimit;
    }

    /// @notice Set setL2ChainId
    /// @param _layer2ChainId The chain Id of L2.
    function setL2ChainId(uint64 _layer2ChainId) external onlyOwner {
        layer2ChainId = _layer2ChainId;
    }

    /// @notice Set tee_verifier
    /// @param _teeVerifierAddress The verifier address of tee.
    function setTeeVerifierAddress(address _teeVerifierAddress) external onlyOwner whenPaused {
        require(_teeVerifierAddress != address(0), "INVALID_PARAMETER : must specify one verifier address");
        tee_verifier = _teeVerifierAddress;
    }

    /// @notice Set zk_verifier
    /// @param _zkVerifierAddress The verifier address of tee.
    function setZkVerifierAddress(address _zkVerifierAddress) external onlyOwner whenPaused {
        require(_zkVerifierAddress != address(0), "INVALID_PARAMETER : must specify one verifier address");
        zk_verifier = _zkVerifierAddress;
    }
}