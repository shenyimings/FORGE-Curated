// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {SecureMerkleTrie} from "@eth-optimism/contracts-bedrock/src/libraries/trie/SecureMerkleTrie.sol";
import {RLPReader} from "@eth-optimism/contracts-bedrock/src/libraries/rlp/RLPReader.sol";
import {RLPWriter} from "@eth-optimism/contracts-bedrock/src/libraries/rlp/RLPWriter.sol";
import {IL1Block} from "../interfaces/IL1Block.sol";
import {BaseProver} from "./BaseProver.sol";
import {Semver} from "../libs/Semver.sol";

/**
 * @title Prover
 * @notice Validates cross-chain intent execution through storage proofs and Bedrock/Cannon L2 proving
 * @dev Inherits from BaseProver to provide core proving functionality. Supports both storage-based
 * proofs and optimistic rollup verification through various proving mechanisms
 */
contract Prover is BaseProver, Semver {
    ProofType public constant PROOF_TYPE = ProofType.Storage;

    // Output slot for Bedrock L2_OUTPUT_ORACLE where Settled Batches are stored
    uint256 public constant L2_OUTPUT_SLOT_NUMBER = 3;

    uint256 public constant L2_OUTPUT_ROOT_VERSION_NUMBER = 0;

    // L2OutputOracle on Ethereum used for Bedrock (Base) Proving
    // address public immutable l1OutputOracleAddress;

    // Cannon Data
    // FaultGameFactory on Ethereum used for Cannon (Optimism) Proving
    // address public immutable faultGameFactoryAddress;

    // Output slot for Cannon DisputeGameFactory where FaultDisputeGames gameId's are stored
    uint256 public constant L2_DISPUTE_GAME_FACTORY_LIST_SLOT_NUMBER = 104;

    // Output slot for the root claim (used as the block number settled is part of the root claim)
    uint256 public constant L2_FAULT_DISPUTE_GAME_ROOT_CLAIM_SLOT =
        0x405787fa12a823e0f2b7631cc41b3ba8828b3321ca811111fa75cd3aa3bb5ad1;

    // Output slot for the game status (fixed)
    uint256 public constant L2_FAULT_DISPUTE_GAME_STATUS_SLOT = 0;

    // Number of blocks to wait before Settlement Layer can be proven again
    uint256 public immutable SETTLEMENT_BLOCKS_DELAY;

    // This contract lives on an L2 and contains the data for the 'current' L1 block.
    // there is a delay between this contract and L1 state - the block information found here is usually a few blocks behind the most recent block on L1.
    // But optimism maintains a service that posts L1 block data on L2.
    IL1Block public l1BlockhashOracle;

    /**
     * @notice Configuration data for a chain's proving mechanism
     * @param provingMechanism Type of proving used (e.g., Bedrock, Cannon)
     * @param settlementChainId ID of chain where proofs are settled
     * @param settlementContract Address of contract handling proof settlement
     * @param blockhashOracle Address of oracle providing block data
     * @param outputRootVersionNumber Version of output root format
     * @param finalityDelaySeconds Required delay before finalizing proofs
     */
    struct ChainConfiguration {
        uint8 provingMechanism;
        uint256 settlementChainId;
        address settlementContract;
        address blockhashOracle;
        uint256 outputRootVersionNumber;
        uint256 finalityDelaySeconds;
    }

    /**
     * @notice Helper struct for constructor chain configuration
     * @param chainId ID of chain being configured
     * @param chainConfiguration Configuration parameters for the chain
     */
    struct ChainConfigurationConstructor {
        uint256 chainId;
        ChainConfiguration chainConfiguration;
    }

    /**
     * @notice Maps chain IDs to their proving configurations
     */
    mapping(uint256 => ChainConfiguration) public chainConfigurations;

    /**
     * @notice Stores proven block data for a chain
     * @param blockNumber Number of the proven block
     * @param blockHash Hash of the proven block
     * @param stateRoot State root of the proven block
     */
    struct BlockProof {
        uint256 blockNumber;
        bytes32 blockHash;
        bytes32 stateRoot;
    }

    /**
     * @notice Maps chain IDs to their latest proven block state
     */
    mapping(uint256 => BlockProof) public provenStates;

    /**
     * @notice Proof data required for dispute game factory verification
     * @param messagePasserStateRoot Root of the message passer state
     * @param latestBlockHash Hash of latest block
     * @param gameIndex Index in the dispute game factory
     * @param gameId Unique identifier of the dispute game
     * @param disputeFaultGameStorageProof Proof of storage for dispute game
     * @param rlpEncodedDisputeGameFactoryData RLP encoded factory contract data
     * @param disputeGameFactoryAccountProof Proof of factory contract account
     */
    struct DisputeGameFactoryProofData {
        bytes32 messagePasserStateRoot;
        bytes32 latestBlockHash;
        uint256 gameIndex;
        bytes32 gameId;
        bytes[] disputeFaultGameStorageProof;
        bytes rlpEncodedDisputeGameFactoryData;
        bytes[] disputeGameFactoryAccountProof;
    }

    /**
     * @notice Status data for a fault dispute game
     * @param createdAt Timestamp of game creation
     * @param resolvedAt Timestamp of game resolution
     * @param gameStatus Current status of the game
     * @param initialized Whether game is initialized
     * @param l2BlockNumberChallenged Whether block number was challenged
     */
    struct FaultDisputeGameStatusSlotData {
        uint64 createdAt;
        uint64 resolvedAt;
        uint8 gameStatus;
        bool initialized;
        bool l2BlockNumberChallenged;
    }

    /**
     * @notice Proof data for fault dispute game verification
     * @param faultDisputeGameStateRoot State root of dispute game
     * @param faultDisputeGameRootClaimStorageProof Proof of root claim storage
     * @param faultDisputeGameStatusSlotData Status data of the game
     * @param faultDisputeGameStatusStorageProof Proof of game status storage
     * @param rlpEncodedFaultDisputeGameData RLP encoded game contract data
     * @param faultDisputeGameAccountProof Proof of game contract account
     */
    struct FaultDisputeGameProofData {
        bytes32 faultDisputeGameStateRoot;
        bytes[] faultDisputeGameRootClaimStorageProof;
        FaultDisputeGameStatusSlotData faultDisputeGameStatusSlotData;
        bytes[] faultDisputeGameStatusStorageProof;
        bytes rlpEncodedFaultDisputeGameData;
        bytes[] faultDisputeGameAccountProof;
    }

    /**
     * @notice Emitted when L1 world state is successfully proven
     * @param _blockNumber Block number of proven state
     * @param _L1WorldStateRoot World state root that was proven
     */
    event L1WorldStateProven(
        uint256 indexed _blockNumber,
        bytes32 _L1WorldStateRoot
    );

    /**
     * @notice Emitted when L2 world state is successfully proven
     * @param _destinationChainID Chain ID of the L2
     * @param _blockNumber Block number of proven state
     * @param _L2WorldStateRoot World state root that was proven
     */
    event L2WorldStateProven(
        uint256 indexed _destinationChainID,
        uint256 indexed _blockNumber,
        bytes32 _L2WorldStateRoot
    );

    /**
     * @notice Block number is too recent to prove
     * @param _inputBlockNumber Block attempted to prove
     * @param _nextProvableBlockNumber Next valid block number
     */
    error NeedLaterBlock(
        uint256 _inputBlockNumber,
        uint256 _nextProvableBlockNumber
    );

    /**
     * @notice Block number is older than currently proven block
     * @param _inputBlockNumber Block attempted to prove
     * @param _latestBlockNumber Current proven block
     */
    error OutdatedBlock(uint256 _inputBlockNumber, uint256 _latestBlockNumber);

    /**
     * @notice RLP encoded block data hash mismatch
     * @param _expectedBlockHash Expected hash
     * @param _calculatedBlockHash Actual hash
     */
    error InvalidRLPEncodedBlock(
        bytes32 _expectedBlockHash,
        bytes32 _calculatedBlockHash
    );

    /**
     * @notice Failed storage proof verification
     * @param _key Storage key
     * @param _val Storage value
     * @param _proof Merkle proof
     * @param _root Expected root
     */
    error InvalidStorageProof(
        bytes _key,
        bytes _val,
        bytes[] _proof,
        bytes32 _root
    );

    /**
     * @notice Failed account proof verification
     * @param _address Account address
     * @param _data Account data
     * @param _proof Merkle proof
     * @param _root Expected root
     */
    error InvalidAccountProof(
        bytes _address,
        bytes _data,
        bytes[] _proof,
        bytes32 _root
    );

    /**
     * @notice Settlement chain state not yet proven
     * @param _blockProofStateRoot State root attempted to prove
     * @param _l1WorldStateRoot Current proven state root
     */
    error SettlementChainStateRootNotProved(
        bytes32 _blockProofStateRoot,
        bytes32 _l1WorldStateRoot
    );

    /**
     * @notice Destination chain state not yet proven
     * @param _blockProofStateRoot State root attempted to prove
     * @param _l2WorldStateRoot Current proven state root
     */
    error DestinationChainStateRootNotProved(
        bytes32 _blockProofStateRoot,
        bytes32 _l2WorldStateRoot
    );

    /**
     * @notice Block timestamp before finality period
     * @param _blockTimeStamp Block timestamp
     * @param _finalityDelayTimeStamp Required timestamp including delay
     */
    error BlockBeforeFinalityPeriod(
        uint256 _blockTimeStamp,
        uint256 _finalityDelayTimeStamp
    );

    /**
     * @notice Invalid output oracle state root encoding
     * @param _outputOracleStateRoot Invalid state root
     */
    error IncorrectOutputOracleStateRoot(bytes _outputOracleStateRoot);

    /**
     * @notice Invalid dispute game factory state root encoding
     * @param _disputeGameFactoryStateRoot Invalid state root
     */
    error IncorrectDisputeGameFactoryStateRoot(
        bytes _disputeGameFactoryStateRoot
    );

    /**
     * @notice Invalid inbox state root encoding
     * @param _inboxStateRoot Invalid state root
     */
    error IncorrectInboxStateRoot(bytes _inboxStateRoot);

    /**
     * @notice Fault dispute game not yet resolved
     * @param _gameStatus Current game status
     */
    error FaultDisputeGameUnresolved(uint8 _gameStatus);

    /**
     * @notice Validates RLP encoded block data matches expected hash
     * @param _rlpEncodedBlockData Encoded block data
     * @param _expectedBlockHash Expected block hash
     */
    modifier validRLPEncodeBlock(
        bytes calldata _rlpEncodedBlockData,
        bytes32 _expectedBlockHash
    ) {
        bytes32 calculatedBlockHash = keccak256(_rlpEncodedBlockData);
        if (calculatedBlockHash == _expectedBlockHash) {
            _;
        } else {
            revert InvalidRLPEncodedBlock(
                _expectedBlockHash,
                calculatedBlockHash
            );
        }
    }

    /**
     * @notice Initializes prover with chain configurations
     * @param _settlementBlocksDelay Minimum blocks between settlement proofs
     * @param _chainConfigurations Array of chain configurations
     */
    constructor(
        uint256 _settlementBlocksDelay,
        ChainConfigurationConstructor[] memory _chainConfigurations
    ) {
        SETTLEMENT_BLOCKS_DELAY = _settlementBlocksDelay;
        for (uint256 i = 0; i < _chainConfigurations.length; ++i) {
            _setChainConfiguration(
                _chainConfigurations[i].chainId,
                _chainConfigurations[i].chainConfiguration
            );
        }
    }

    /**
     * @notice Returns the proof type used by this prover
     */
    function getProofType() external pure override returns (ProofType) {
        return PROOF_TYPE;
    }
    /**
     * @notice Configures proving mechanism for a chain
     * @dev Sets blockhash oracle if configuring current chain
     * @param chainId Chain to configure
     * @param chainConfiguration Configuration parameters
     */
    function _setChainConfiguration(
        uint256 chainId,
        ChainConfiguration memory chainConfiguration
    ) internal {
        chainConfigurations[chainId] = chainConfiguration;
        if (block.chainid == chainId) {
            l1BlockhashOracle = IL1Block(chainConfiguration.blockhashOracle);
        }
    }

    /**
     * @notice Validates a storage proof against a root
     * @dev Uses SecureMerkleTrie for verification
     * @param _key Storage slot key
     * @param _val Expected value
     * @param _proof Merkle proof
     * @param _root Expected root
     */
    function proveStorage(
        bytes memory _key,
        bytes memory _val,
        bytes[] memory _proof,
        bytes32 _root
    ) public pure {
        if (!SecureMerkleTrie.verifyInclusionProof(_key, _val, _proof, _root)) {
            revert InvalidStorageProof(_key, _val, _proof, _root);
        }
    }

    /**
     * @notice Validates a bytes32 storage value against a root
     * @dev Encodes value as RLP before verification
     * @param _key Storage slot key
     * @param _val Expected bytes32 value
     * @param _proof Merkle proof
     * @param _root Expected root
     */
    function proveStorageBytes32(
        bytes memory _key,
        bytes32 _val,
        bytes[] memory _proof,
        bytes32 _root
    ) public pure {
        // `RLPWriter.writeUint` properly encodes values by removing any leading zeros.
        bytes memory rlpEncodedValue = RLPWriter.writeUint(uint256(_val));
        if (
            !SecureMerkleTrie.verifyInclusionProof(
                _key,
                rlpEncodedValue,
                _proof,
                _root
            )
        ) {
            revert InvalidStorageProof(_key, rlpEncodedValue, _proof, _root);
        }
    }

    /**
     * @notice Validates an account proof against a root
     * @dev Uses SecureMerkleTrie for verification
     * @param _address Account address
     * @param _data Expected account data
     * @param _proof Merkle proof
     * @param _root Expected root
     */
    function proveAccount(
        bytes memory _address,
        bytes memory _data,
        bytes[] memory _proof,
        bytes32 _root
    ) public pure {
        if (
            !SecureMerkleTrie.verifyInclusionProof(
                _address,
                _data,
                _proof,
                _root
            )
        ) {
            revert InvalidAccountProof(_address, _data, _proof, _root);
        }
    }

    /**
     * @notice Generates an output root for Bedrock and Cannon proving
     * @param outputRootVersion Version number (usually 0)
     * @param worldStateRoot State root
     * @param messagePasserStateRoot Message passer state root
     * @param latestBlockHash Latest block hash
     * @return Output root hash
     */
    function generateOutputRoot(
        uint256 outputRootVersion,
        bytes32 worldStateRoot,
        bytes32 messagePasserStateRoot,
        bytes32 latestBlockHash
    ) public pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    outputRootVersion,
                    worldStateRoot,
                    messagePasserStateRoot,
                    latestBlockHash
                )
            );
    }

    /**
     * @notice RLP encodes a list of data elements
     * @dev Helper function for batch encoding
     * @param dataList List of data elements to encode
     * @return RLP encoded bytes
     */
    function rlpEncodeDataLibList(
        bytes[] memory dataList
    ) external pure returns (bytes memory) {
        for (uint256 i = 0; i < dataList.length; ++i) {
            dataList[i] = RLPWriter.writeBytes(dataList[i]);
        }

        return RLPWriter.writeList(dataList);
    }

    /**
     * @notice Packs game metadata into a 32-byte GameId
     * @dev Combines type, timestamp, and proxy address into single identifier
     * @param _gameType Game type identifier
     * @param _timestamp Creation timestamp
     * @param _gameProxy Proxy contract address
     * @return gameId_ Packed game identifier
     */
    function pack(
        uint32 _gameType,
        uint64 _timestamp,
        address _gameProxy
    ) public pure returns (bytes32 gameId_) {
        assembly {
            gameId_ := or(
                or(shl(224, _gameType), shl(160, _timestamp)),
                _gameProxy
            )
        }
    }

    /**
     * @notice Unpacks a 32-byte GameId into its components
     * @param _gameId Packed game identifier
     * @return gameType_ Game type identifier
     * @return timestamp_ Creation timestamp
     * @return gameProxy_ Proxy contract address
     */
    function unpack(
        bytes32 _gameId
    )
        public
        pure
        returns (uint32 gameType_, uint64 timestamp_, address gameProxy_)
    {
        assembly {
            gameType_ := shr(224, _gameId)
            timestamp_ := and(shr(160, _gameId), 0xFFFFFFFFFFFFFFFF)
            gameProxy_ := and(
                _gameId,
                0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF
            )
        }
    }

    /**
     * @notice Converts bytes to uint256
     * @dev Manual byte-by-byte conversion
     * @param b Bytes to convert
     * @return Converted uint256 value
     */
    function _bytesToUint(bytes memory b) internal pure returns (uint256) {
        uint256 number;
        for (uint256 i = 0; i < b.length; i++) {
            number =
                number +
                uint256(uint8(b[i])) *
                (2 ** (8 * (b.length - (i + 1))));
        }
        return number;
    }

    /**
     * @notice Assembles game status storage slot data
     * @dev Packs status fields into a single bytes32
     * @param createdAt Creation timestamp
     * @param resolvedAt Resolution timestamp
     * @param gameStatus Game status code
     * @param initialized Initialization status
     * @param l2BlockNumberChallenged Block number challenge status
     * @return gameStatusStorageSlotRLP Packed status data
     */
    function assembleGameStatusStorage(
        uint64 createdAt,
        uint64 resolvedAt,
        uint8 gameStatus,
        bool initialized,
        bool l2BlockNumberChallenged
    ) public pure returns (bytes32 gameStatusStorageSlotRLP) {
        // Packed data is 64 + 64 + 8 + 8 + 8 = 152 bits / 19 bytes.
        // Need to convert to `uint152` to preserve right alignment.
        return
            bytes32(
                uint256(
                    uint152(
                        bytes19(
                            abi.encodePacked(
                                l2BlockNumberChallenged,
                                initialized,
                                gameStatus,
                                resolvedAt,
                                createdAt
                            )
                        )
                    )
                )
            );
    }

    /**
     * @notice Proves L1 settlement layer state against oracle
     * @dev Validates block data against L1 blockhash oracle and updates proven state
     * @param rlpEncodedBlockData RLP encoded block data
     */
    function proveSettlementLayerState(
        bytes calldata rlpEncodedBlockData
    )
        public
        validRLPEncodeBlock(rlpEncodedBlockData, l1BlockhashOracle.hash())
    {
        uint256 settlementChainId = chainConfigurations[block.chainid]
            .settlementChainId;
        // not necessary because we already confirm that the data is correct by ensuring that it hashes to the block hash
        // require(l1WorldStateRoot.length <= 32); // ensure lossless casting to bytes32

        // Extract block proof from encoded data
        BlockProof memory blockProof = BlockProof({
            blockNumber: _bytesToUint(
                RLPReader.readBytes(RLPReader.readList(rlpEncodedBlockData)[8])
            ),
            blockHash: keccak256(rlpEncodedBlockData),
            stateRoot: bytes32(
                RLPReader.readBytes(RLPReader.readList(rlpEncodedBlockData)[3])
            )
        });

        // Verify block delay and update state
        BlockProof memory existingBlockProof = provenStates[settlementChainId];
        if (
            existingBlockProof.blockNumber + SETTLEMENT_BLOCKS_DELAY <
            blockProof.blockNumber
        ) {
            provenStates[settlementChainId] = blockProof;
            emit L1WorldStateProven(
                blockProof.blockNumber,
                blockProof.stateRoot
            );
        } else {
            revert NeedLaterBlock(
                blockProof.blockNumber,
                existingBlockProof.blockNumber + SETTLEMENT_BLOCKS_DELAY
            );
        }
    }

    /**
     * @notice Handles Bedrock L2 world state validation
     * @dev Verifies L2 output root against L1 oracle and updates proven state
     * @param chainId Destination chain ID
     * @param rlpEncodedBlockData RLP encoded block data
     * @param l2WorldStateRoot L2 state root
     * @param l2MessagePasserStateRoot L2 message passer state root
     * @param l2OutputIndex Batch number
     * @param l1StorageProof L1 storage proof for L2OutputOracle
     * @param rlpEncodedOutputOracleData RLP encoded L2OutputOracle data
     * @param l1AccountProof L1 account proof for L2OutputOracle
     * @param l1WorldStateRoot Proven L1 world state root
     */
    function proveWorldStateBedrock(
        uint256 chainId,
        bytes calldata rlpEncodedBlockData,
        bytes32 l2WorldStateRoot,
        bytes32 l2MessagePasserStateRoot,
        uint256 l2OutputIndex,
        bytes[] calldata l1StorageProof,
        bytes calldata rlpEncodedOutputOracleData,
        bytes[] calldata l1AccountProof,
        bytes32 l1WorldStateRoot
    ) public virtual {
        // could set a more strict requirement here to make the L1 block number greater than something corresponding to the intent creation
        // can also use timestamp instead of block when this is proven for better crosschain knowledge
        // failing the need for all that, change the mapping to map to bool
        ChainConfiguration memory chainConfiguration = chainConfigurations[
            chainId
        ];
        BlockProof memory existingSettlementBlockProof = provenStates[
            chainConfiguration.settlementChainId
        ];

        // Verify settlement chain state root
        if (existingSettlementBlockProof.stateRoot != l1WorldStateRoot) {
            revert SettlementChainStateRootNotProved(
                existingSettlementBlockProof.stateRoot,
                l1WorldStateRoot
            );
        }

        // Verify block timestamp meets finality delay
        uint256 endBatchBlockTimeStamp = _bytesToUint(
            RLPReader.readBytes(RLPReader.readList(rlpEncodedBlockData)[11])
        );

        if (
            block.timestamp <=
            endBatchBlockTimeStamp + chainConfiguration.finalityDelaySeconds
        ) {
            revert BlockBeforeFinalityPeriod(
                block.timestamp,
                endBatchBlockTimeStamp + chainConfiguration.finalityDelaySeconds
            );
        }

        // Generate and verify output root
        bytes32 blockHash = keccak256(rlpEncodedBlockData);
        bytes32 outputRoot = generateOutputRoot(
            L2_OUTPUT_ROOT_VERSION_NUMBER,
            l2WorldStateRoot,
            l2MessagePasserStateRoot,
            blockHash
        );

        // Calculate storage slot and verify output root
        bytes32 outputRootStorageSlot = bytes32(
            (uint256(keccak256(abi.encode(L2_OUTPUT_SLOT_NUMBER))) +
                l2OutputIndex *
                2)
        );

        bytes memory outputOracleStateRoot = RLPReader.readBytes(
            RLPReader.readList(rlpEncodedOutputOracleData)[2]
        );

        if (outputOracleStateRoot.length > 32) {
            revert IncorrectOutputOracleStateRoot(outputOracleStateRoot);
        }

        proveStorageBytes32(
            abi.encodePacked(outputRootStorageSlot),
            outputRoot,
            l1StorageProof,
            bytes32(outputOracleStateRoot)
        );

        proveAccount(
            abi.encodePacked(chainConfiguration.settlementContract),
            rlpEncodedOutputOracleData,
            l1AccountProof,
            l1WorldStateRoot
        );

        // Update proven state if newer block
        BlockProof memory existingBlockProof = provenStates[chainId];
        BlockProof memory blockProof = BlockProof({
            blockNumber: _bytesToUint(
                RLPReader.readBytes(RLPReader.readList(rlpEncodedBlockData)[8])
            ),
            blockHash: blockHash,
            stateRoot: l2WorldStateRoot
        });

        if (existingBlockProof.blockNumber < blockProof.blockNumber) {
            provenStates[chainId] = blockProof;
            emit L2WorldStateProven(
                chainId,
                blockProof.blockNumber,
                blockProof.stateRoot
            );
        } else {
            if (existingBlockProof.blockNumber > blockProof.blockNumber) {
                revert OutdatedBlock(
                    blockProof.blockNumber,
                    existingBlockProof.blockNumber
                );
            }
        }
    }

    /**
     * @notice Validates fault dispute game from factory configuration
     * @dev Internal helper for Cannon proving
     * @param disputeGameFactoryAddress Factory contract address
     * @param l2WorldStateRoot L2 state root to verify
     * @param disputeGameFactoryProofData Proof data for factory validation
     * @param l1WorldStateRoot Proven L1 world state root
     * @return faultDisputeGameProxyAddress Address of game proxy
     * @return rootClaim Generated root claim
     */
    function _faultDisputeGameFromFactory(
        address disputeGameFactoryAddress,
        bytes32 l2WorldStateRoot,
        DisputeGameFactoryProofData calldata disputeGameFactoryProofData,
        bytes32 l1WorldStateRoot
    )
        internal
        pure
        returns (address faultDisputeGameProxyAddress, bytes32 rootClaim)
    {
        // Generate root claim from state data
        bytes32 _rootClaim = generateOutputRoot(
            L2_OUTPUT_ROOT_VERSION_NUMBER,
            l2WorldStateRoot,
            disputeGameFactoryProofData.messagePasserStateRoot,
            disputeGameFactoryProofData.latestBlockHash
        );

        // Verify game exists in factory
        bytes32 disputeGameFactoryStorageSlot = bytes32(
            abi.encode(
                (uint256(
                    keccak256(
                        abi.encode(L2_DISPUTE_GAME_FACTORY_LIST_SLOT_NUMBER)
                    )
                ) + disputeGameFactoryProofData.gameIndex)
            )
        );

        bytes memory disputeGameFactoryStateRoot = RLPReader.readBytes(
            RLPReader.readList(
                disputeGameFactoryProofData.rlpEncodedDisputeGameFactoryData
            )[2]
        );

        if (disputeGameFactoryStateRoot.length > 32) {
            revert IncorrectDisputeGameFactoryStateRoot(
                disputeGameFactoryStateRoot
            );
        }

        // Verify storage and account proofs
        proveStorageBytes32(
            abi.encodePacked(disputeGameFactoryStorageSlot),
            disputeGameFactoryProofData.gameId,
            disputeGameFactoryProofData.disputeFaultGameStorageProof,
            bytes32(disputeGameFactoryStateRoot)
        );

        proveAccount(
            abi.encodePacked(disputeGameFactoryAddress),
            disputeGameFactoryProofData.rlpEncodedDisputeGameFactoryData,
            disputeGameFactoryProofData.disputeGameFactoryAccountProof,
            l1WorldStateRoot
        );

        // Get proxy address from game ID
        (, , address _faultDisputeGameProxyAddress) = unpack(
            disputeGameFactoryProofData.gameId
        );

        return (_faultDisputeGameProxyAddress, _rootClaim);
    }

    /**
     * @notice Verifies fault dispute game resolution
     * @dev Verifies game status and root claim
     * @param rootClaim Expected root claim value
     * @param faultDisputeGameProxyAddress Game proxy contract
     * @param faultDisputeGameProofData Proof data for game verification
     * @param l1WorldStateRoot Proven L1 world state root
     */
    function _faultDisputeGameIsResolved(
        bytes32 rootClaim,
        address faultDisputeGameProxyAddress,
        FaultDisputeGameProofData memory faultDisputeGameProofData,
        bytes32 l1WorldStateRoot
    ) internal pure {
        // Verify game is resolved
        if (
            faultDisputeGameProofData
                .faultDisputeGameStatusSlotData
                .gameStatus != 2
        ) {
            revert FaultDisputeGameUnresolved(
                faultDisputeGameProofData
                    .faultDisputeGameStatusSlotData
                    .gameStatus
            );
        }

        // ensure faultDisputeGame is resolved
        // Prove that the FaultDispute game has been settled
        // storage proof for FaultDisputeGame rootClaim (means block is valid)
        proveStorageBytes32(
            abi.encodePacked(uint256(L2_FAULT_DISPUTE_GAME_ROOT_CLAIM_SLOT)),
            rootClaim,
            faultDisputeGameProofData.faultDisputeGameRootClaimStorageProof,
            bytes32(faultDisputeGameProofData.faultDisputeGameStateRoot)
        );

        // Assemble and verify game status
        bytes32 faultDisputeGameStatusStorage = assembleGameStatusStorage(
            faultDisputeGameProofData.faultDisputeGameStatusSlotData.createdAt,
            faultDisputeGameProofData.faultDisputeGameStatusSlotData.resolvedAt,
            faultDisputeGameProofData.faultDisputeGameStatusSlotData.gameStatus,
            faultDisputeGameProofData
                .faultDisputeGameStatusSlotData
                .initialized,
            faultDisputeGameProofData
                .faultDisputeGameStatusSlotData
                .l2BlockNumberChallenged
        );

        // Verify game status storage proof
        proveStorageBytes32(
            abi.encodePacked(uint256(L2_FAULT_DISPUTE_GAME_STATUS_SLOT)),
            faultDisputeGameStatusStorage,
            faultDisputeGameProofData.faultDisputeGameStatusStorageProof,
            bytes32(
                RLPReader.readBytes(
                    RLPReader.readList(
                        faultDisputeGameProofData.rlpEncodedFaultDisputeGameData
                    )[2]
                )
            )
        );

        // Verify game contract account proof
        proveAccount(
            abi.encodePacked(faultDisputeGameProxyAddress),
            faultDisputeGameProofData.rlpEncodedFaultDisputeGameData,
            faultDisputeGameProofData.faultDisputeGameAccountProof,
            l1WorldStateRoot
        );
    }

    /**
     * @notice Proves L2 world state using Cannon verification
     * @dev Verifies through fault dispute game resolution
     * @param chainId ID of destination chain
     * @param rlpEncodedBlockData RLP encoded block data
     * @param l2WorldStateRoot L2 state root to verify
     * @param disputeGameFactoryProofData Proof data for factory verification
     * @param faultDisputeGameProofData Proof data for game verification
     * @param l1WorldStateRoot Proven L1 world state root
     */
    function proveWorldStateCannon(
        uint256 chainId,
        bytes calldata rlpEncodedBlockData,
        bytes32 l2WorldStateRoot,
        DisputeGameFactoryProofData calldata disputeGameFactoryProofData,
        FaultDisputeGameProofData memory faultDisputeGameProofData,
        bytes32 l1WorldStateRoot
    )
        public
        validRLPEncodeBlock(
            rlpEncodedBlockData,
            disputeGameFactoryProofData.latestBlockHash
        )
    {
        ChainConfiguration memory chainConfiguration = chainConfigurations[
            chainId
        ];

        // Verify settlement chain state root
        BlockProof memory existingSettlementBlockProof = provenStates[
            chainConfiguration.settlementChainId
        ];
        if (existingSettlementBlockProof.stateRoot != l1WorldStateRoot) {
            revert SettlementChainStateRootNotProved(
                existingSettlementBlockProof.stateRoot,
                l1WorldStateRoot
            );
        }
        // prove that the FaultDisputeGame was created by the Dispute Game Factory

        // Verify dispute game creation and resolution
        bytes32 rootClaim;
        address faultDisputeGameProxyAddress;
        (
            faultDisputeGameProxyAddress,
            rootClaim
        ) = _faultDisputeGameFromFactory(
            chainConfiguration.settlementContract,
            l2WorldStateRoot,
            disputeGameFactoryProofData,
            l1WorldStateRoot
        );

        _faultDisputeGameIsResolved(
            rootClaim,
            faultDisputeGameProxyAddress,
            faultDisputeGameProofData,
            l1WorldStateRoot
        );

        // Update proven state if newer block
        BlockProof memory existingBlockProof = provenStates[chainId];
        BlockProof memory blockProof = BlockProof({
            blockNumber: _bytesToUint(
                RLPReader.readBytes(RLPReader.readList(rlpEncodedBlockData)[8])
            ),
            blockHash: keccak256(rlpEncodedBlockData),
            stateRoot: l2WorldStateRoot
        });

        if (existingBlockProof.blockNumber < blockProof.blockNumber) {
            provenStates[chainId] = blockProof;
            emit L2WorldStateProven(
                chainId,
                blockProof.blockNumber,
                blockProof.stateRoot
            );
        } else {
            if (existingBlockProof.blockNumber > blockProof.blockNumber) {
                revert OutdatedBlock(
                    blockProof.blockNumber,
                    existingBlockProof.blockNumber
                );
            }
        }
    }

    /**
     * @notice Proves an intent's execution on destination chain
     * @dev Verifies storage proof of intent fulfillment
     * @param chainId Destination chain ID
     * @param claimant Address eligible to claim rewards
     * @param inboxContract Inbox contract address
     * @param intermediateHash Partial intent hash
     * @param l2StorageProof Storage proof for intent mapping
     * @param rlpEncodedInboxData RLP encoded inbox contract data
     * @param l2AccountProof Account proof for inbox contract
     * @param l2WorldStateRoot L2 world state root
     */
    function proveIntent(
        uint256 chainId,
        address claimant,
        address inboxContract,
        bytes32 intermediateHash,
        bytes[] calldata l2StorageProof,
        bytes calldata rlpEncodedInboxData,
        bytes[] calldata l2AccountProof,
        bytes32 l2WorldStateRoot
    ) public {
        // Verify L2 state root is proven
        BlockProof memory existingBlockProof = provenStates[chainId];
        if (existingBlockProof.stateRoot != l2WorldStateRoot) {
            revert DestinationChainStateRootNotProved(
                existingBlockProof.stateRoot,
                l2WorldStateRoot
            );
        }

        // Calculate full intent hash
        bytes32 intentHash = keccak256(
            abi.encode(inboxContract, intermediateHash)
        );

        // Calculate storage slot for intent mapping
        bytes32 messageMappingSlot = keccak256(
            abi.encode(
                intentHash,
                1 // storage position of the intents mapping is the first slot
            )
        );

        // Verify inbox state root
        bytes memory inboxStateRoot = RLPReader.readBytes(
            RLPReader.readList(rlpEncodedInboxData)[2]
        );

        if (inboxStateRoot.length > 32) {
            revert IncorrectInboxStateRoot(inboxStateRoot);
        }

        // Verify storage proof for claimant mapping
        proveStorageBytes32(
            abi.encodePacked(messageMappingSlot),
            bytes32(uint256(uint160(claimant))),
            l2StorageProof,
            bytes32(inboxStateRoot)
        );

        // Verify inbox contract account proof
        proveAccount(
            abi.encodePacked(inboxContract),
            rlpEncodedInboxData,
            l2AccountProof,
            l2WorldStateRoot
        );

        // Record proven intent and emit event
        provenIntents[intentHash] = claimant;
        emit IntentProven(intentHash, claimant);
    }
}
