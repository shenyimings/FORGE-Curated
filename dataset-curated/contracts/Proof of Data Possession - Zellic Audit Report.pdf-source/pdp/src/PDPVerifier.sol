// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {BitOps} from "./BitOps.sol";
import {Cids} from "./Cids.sol";
import {MerkleVerify} from "./Proofs.sol";
import {PDPFees} from "./Fees.sol";
import "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import "../lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";
import "@pythnetwork/pyth-sdk-solidity/IPyth.sol";
import "@pythnetwork/pyth-sdk-solidity/PythStructs.sol";

/// @title PDPListener
/// @notice Interface for PDP Service applications managing data storage.
/// @dev This interface exists to provide an extensible hook for applications to use the PDP verification contract
/// to implement data storage applications.
interface PDPListener {
    function proofSetCreated(uint256 proofSetId, address creator, bytes calldata extraData) external;
    function proofSetDeleted(uint256 proofSetId, uint256 deletedLeafCount, bytes calldata extraData) external;
    function rootsAdded(uint256 proofSetId, uint256 firstAdded, PDPVerifier.RootData[] memory rootData, bytes calldata extraData) external;
    function rootsScheduledRemove(uint256 proofSetId, uint256[] memory rootIds, bytes calldata extraData) external;
    // Note: extraData not included as proving messages conceptually always originate from the SP
    function possessionProven(uint256 proofSetId, uint256 challengedLeafCount, uint256 seed, uint256 challengeCount) external;
    function nextProvingPeriod(uint256 proofSetId, uint256 challengeEpoch, uint256 leafCount, bytes calldata extraData) external;
}

contract PDPVerifier is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    // Constants
    address public constant BURN_ACTOR = 0xff00000000000000000000000000000000000063;
    uint256 public constant LEAF_SIZE = 32;
    uint256 public constant MAX_ROOT_SIZE = 1 << 50;
    uint256 public constant MAX_ENQUEUED_REMOVALS = 2000;
    address public constant RANDOMNESS_PRECOMPILE = 0xfE00000000000000000000000000000000000006;
    uint256 public constant EXTRA_DATA_MAX_SIZE = 2048;
    uint256 public constant SECONDS_IN_DAY = 86400;
    IPyth public constant PYTH = IPyth(0xA2aa501b19aff244D90cc15a4Cf739D2725B5729);

    // FIL/USD price feed query ID on the Pyth network
    bytes32 public constant FIL_USD_PRICE_FEED_ID = 0x150ac9b959aee0051e4091f0ef5216d941f590e1c5e7f91cf7635b5c11628c0e;
    uint256 public constant NO_CHALLENGE_SCHEDULED = 0;
    uint256 public constant NO_PROVEN_EPOCH = 0;


    // Events
    event ProofSetCreated(uint256 indexed setId, address indexed owner);
    event ProofSetOwnerChanged(uint256 indexed setId, address indexed oldOwner, address indexed newOwner);
    event ProofSetDeleted(uint256 indexed setId, uint256 deletedLeafCount);
    event ProofSetEmpty(uint256 indexed setId);

    event RootsAdded(uint256 indexed setId, uint256[] rootIds);
    event RootsRemoved(uint256 indexed setId, uint256[] rootIds);
   
    event ProofFeePaid(uint256 indexed setId, uint256 fee, uint64 price, int32 expo);


    event PossessionProven(uint256 indexed setId, RootIdAndOffset[] challenges);
    event NextProvingPeriod(uint256 indexed setId, uint256 challengeEpoch, uint256 leafCount);

    // Types
    // State fields
     event Debug(string message, uint256 value);

    /*
    A proof set is the metadata required for tracking data for proof of possession.
    It maintains a list of CIDs of data to be proven and metadata needed to
    add and remove data to the set and prove possession efficiently.

    ** logical structure of the proof set**
    /*
    struct ProofSet {
        Cid[] roots;
        uint256[] leafCounts;
        uint256[] sumTree;
        uint256 leafCount;
        address owner;
        address proposed owner;
        nextRootID uint64;
        nextChallengeEpoch: uint64;
        listenerAddress: address;
        challengeRange: uint256
        enqueuedRemovals: uint256[]
    }
    ** PDP Verifier contract tracks many possible proof sets **
    []ProofSet proofsets

    To implement this logical structure in the solidity data model we have
    arrays tracking the singleton fields and two dimensional arrays
    tracking linear proof set data.  The first index is the proof set id
    and the second index if any is the index of the data in the array.

    Invariant: rootCids.length == rootLeafCount.length == sumTreeCounts.length
    */

    // Network epoch delay between last proof of possession and next
    // randomness sampling for challenge generation.
    //
    // The purpose of this delay is to prevent SPs from biasing randomness by running forking attacks.
    // Given a small enough challengeFinality an SP can run several trials of challenge sampling and 
    // fork around samples that don't suit them, grinding the challenge randomness.
    // For the filecoin L1, a safe value is 150 using the same analysis setting 150 epochs between
    // PoRep precommit and PoRep provecommit phases.
    //
    // We keep this around for future portability to a variety of environments with different assumptions
    // behind their challenge randomness sampling methods.
    uint256 challengeFinality;

    // TODO PERF: https://github.com/FILCAT/pdp/issues/16#issuecomment-2329838769
    uint64 nextProofSetId;
    // The CID of each root. Roots and all their associated data can be appended and removed but not modified.
    mapping(uint256 => mapping(uint256 => Cids.Cid)) rootCids;
    // The leaf count of each root
    mapping(uint256 => mapping(uint256 => uint256)) rootLeafCounts;
    // The sum tree array for finding the root id of a given leaf index.
    mapping(uint256 => mapping(uint256 => uint256)) sumTreeCounts;
    mapping(uint256 => uint256) nextRootId;
    // The number of leaves (32 byte chunks) in the proof set when tallying up all roots.
    // This includes the leaves in roots that have been added but are not yet eligible for proving.
    mapping(uint256 => uint256) proofSetLeafCount;
    // The epoch for which randomness is sampled for challenge generation while proving possession this proving period.
    mapping(uint256 => uint256) nextChallengeEpoch;
    // Each proof set notifies a configurable listener to implement extensible applications managing data storage.
    mapping(uint256 => address) proofSetListener;
    // The first index that is not challenged in prove possession calls this proving period.
    // Updated to include the latest added leaves when starting the next proving period.
    mapping(uint256 => uint256) challengeRange;
    // Enqueued root ids for removal when starting the next proving period
    mapping(uint256 => uint256[]) scheduledRemovals;
    // ownership of proof set is initialized upon creation to create message sender
    // proofset owner has exclusive permission to add and remove roots and delete the proof set
    mapping(uint256 => address) proofSetOwner;
    mapping(uint256 => address) proofSetProposedOwner;
    mapping(uint256 => uint256) proofSetLastProvenEpoch;

    // Methods

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
     _disableInitializers();
    }

    function initialize(uint256 _challengeFinality) public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        challengeFinality = _challengeFinality;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function burnFee(uint256 amount) internal {
        require(msg.value >= amount, "Incorrect fee amount");
        (bool success, ) = BURN_ACTOR.call{value: amount}("");
        require(success, "Burn failed");
    }

    // Returns the current challenge finality value
    function getChallengeFinality() public view returns (uint256) {
        return challengeFinality;
    }

    // Returns the next proof set ID
    function getNextProofSetId() public view returns (uint64) {
        return nextProofSetId;
    }

    // Returns false if the proof set is 1) not yet created 2) deleted
    function proofSetLive(uint256 setId) public view returns (bool) {
        return setId < nextProofSetId && proofSetOwner[setId] != address(0);
    }

    // Returns false if the proof set is not live or if the root id is 1) not yet created 2) deleted
    function rootLive(uint256 setId, uint256 rootId) public view returns (bool) {
        return proofSetLive(setId) && rootId < nextRootId[setId] && rootLeafCounts[setId][rootId] > 0;
    }

    // Returns false if the root is not live or if the root id is not yet in challenge range
    function rootChallengable(uint256 setId, uint256 rootId) public view returns (bool) {
        uint256 top = 256 - BitOps.clz(nextRootId[setId]);
        RootIdAndOffset memory ret = findOneRootId(setId, challengeRange[setId]-1, top);
        require(ret.offset == rootLeafCounts[setId][ret.rootId] - 1, "challengeRange -1 should align with the very last leaf of a root");
        return rootLive(setId, rootId) && rootId <= ret.rootId;
    }

    // Returns the leaf count of a proof set
    function getProofSetLeafCount(uint256 setId) public view returns (uint256) {
        require(proofSetLive(setId), "Proof set not live");
        return proofSetLeafCount[setId];
    }

    // Returns the next root ID for a proof set
    function getNextRootId(uint256 setId) public view returns (uint256) {
        require(proofSetLive(setId), "Proof set not live");
        return nextRootId[setId];
    }

    // Returns the next challenge epoch for a proof set
    function getNextChallengeEpoch(uint256 setId) public view returns (uint256) {
        require(proofSetLive(setId), "Proof set not live");
        return nextChallengeEpoch[setId];
    }

    // Returns the listener address for a proof set
    function getProofSetListener(uint256 setId) public view returns (address) {
        require(proofSetLive(setId), "Proof set not live");
        return proofSetListener[setId];
    }

    // Returns the owner of a proof set and the proposed owner if any
    function getProofSetOwner(uint256 setId) public view returns (address, address) {
        require(proofSetLive(setId), "Proof set not live");
        return (proofSetOwner[setId], proofSetProposedOwner[setId]);
    }

    function getProofSetLastProvenEpoch(uint256 setId) public view returns (uint256) {
        require(proofSetLive(setId), "Proof set not live");
        return proofSetLastProvenEpoch[setId];
    }

    // Returns the root CID for a given proof set and root ID
    function getRootCid(uint256 setId, uint256 rootId) public view returns (Cids.Cid memory) {
        require(proofSetLive(setId), "Proof set not live");
        return rootCids[setId][rootId];
    }

    // Returns the root leaf count for a given proof set and root ID
    function getRootLeafCount(uint256 setId, uint256 rootId) public view returns (uint256) {
        require(proofSetLive(setId), "Proof set not live");
        return rootLeafCounts[setId][rootId];
    }

    // Returns the index of the most recently added leaf that is challengeable in the current proving period
    function getChallengeRange(uint256 setId) public view returns (uint256) {
        require(proofSetLive(setId), "Proof set not live");
        return challengeRange[setId];
    }

    // Returns the root ids of the roots scheduled for removal at the start of the next proving period
    function getScheduledRemovals(uint256 setId) public view returns (uint256[] memory) {
        require(proofSetLive(setId), "Proof set not live");
        uint256[] storage removals = scheduledRemovals[setId];
        uint256[] memory result = new uint256[](removals.length);
        for (uint256 i = 0; i < removals.length; i++) {
            result[i] = removals[i];
        }
        return result;
    }

    // owner proposes new owner.  If the owner proposes themself delete any outstanding proposed owner
    function proposeProofSetOwner(uint256 setId, address newOwner) public {
        require(proofSetLive(setId), "Proof set not live");
        address owner = proofSetOwner[setId];
        require(owner == msg.sender, "Only the current owner can propose a new owner");
        if (owner == newOwner) {
            // If the owner proposes themself delete any outstanding proposed owner
            delete proofSetProposedOwner[setId];
        } else {
            proofSetProposedOwner[setId] = newOwner;
        }
    }

    function claimProofSetOwnership(uint256 setId) public {
        require(proofSetLive(setId), "Proof set not live");
        require(proofSetProposedOwner[setId] == msg.sender, "Only the proposed owner can claim ownership");
        address oldOwner = proofSetOwner[setId];
        proofSetOwner[setId] = msg.sender;
        delete proofSetProposedOwner[setId];
        emit ProofSetOwnerChanged(setId, oldOwner, msg.sender);
    }

    // A proof set is created empty, with no roots. Creation yields a proof set ID
    // for referring to the proof set later.
    // Sender of create message is proof set owner.
    function createProofSet(address listenerAddr, bytes calldata extraData) public payable returns (uint256) {
        require(extraData.length <= EXTRA_DATA_MAX_SIZE, "Extra data too large");
        uint256 sybilFee = PDPFees.sybilFee();
        require(msg.value >= sybilFee, "sybil fee not met");
        burnFee(sybilFee);
        if (msg.value > sybilFee) {
            // Return the overpayment
            payable(msg.sender).transfer(msg.value - sybilFee);
        }

        uint256 setId = nextProofSetId++;
        proofSetLeafCount[setId] = 0;
        nextChallengeEpoch[setId] = NO_CHALLENGE_SCHEDULED;  // Initialized on first call to NextProvingPeriod
        proofSetOwner[setId] = msg.sender;
        proofSetListener[setId] = listenerAddr;
        proofSetLastProvenEpoch[setId] = NO_PROVEN_EPOCH;

        if (listenerAddr != address(0)) {
            PDPListener(listenerAddr).proofSetCreated(setId, msg.sender, extraData);
        }
        emit ProofSetCreated(setId, msg.sender);
        return setId;
    }

    // Removes a proof set. Must be called by the contract owner.
    function deleteProofSet(uint256 setId, bytes calldata extraData) public {
        require(extraData.length <= EXTRA_DATA_MAX_SIZE, "Extra data too large");
        if (setId >= nextProofSetId) {
            revert("proof set id out of bounds");
        }

        require(proofSetOwner[setId] == msg.sender, "Only the owner can delete proof sets");
        uint256 deletedLeafCount = proofSetLeafCount[setId];
        proofSetLeafCount[setId] = 0;
        proofSetOwner[setId] = address(0);
        nextChallengeEpoch[setId] = 0;
        proofSetLastProvenEpoch[setId] = NO_PROVEN_EPOCH;

        address listenerAddr = proofSetListener[setId];
        if (listenerAddr != address(0)) {
            PDPListener(listenerAddr).proofSetDeleted(setId, deletedLeafCount, extraData);
        }
        emit ProofSetDeleted(setId, deletedLeafCount);
    }

    // Struct for tracking root data
    struct RootData {
        Cids.Cid root;
        uint256 rawSize;
    }

    // Appends new roots to the collection managed by a proof set.
    // These roots won't be challenged until the next proving period is 
    // started by calling nextProvingPeriod.
    function addRoots(uint256 setId, RootData[] calldata rootData, bytes calldata extraData) public returns (uint256) {
        require(extraData.length <= EXTRA_DATA_MAX_SIZE, "Extra data too large");
        require(proofSetLive(setId), "Proof set not live");
        require(rootData.length > 0, "Must add at least one root");
        require(proofSetOwner[setId] == msg.sender, "Only the owner can add roots");
        uint256 firstAdded = nextRootId[setId];
        uint256[] memory rootIds = new uint256[](rootData.length);


        for (uint256 i = 0; i < rootData.length; i++) {
            addOneRoot(setId, i, rootData[i].root, rootData[i].rawSize);
            rootIds[i] = firstAdded + i;
        }
        emit RootsAdded(setId, rootIds);

        address listenerAddr = proofSetListener[setId];
        if (listenerAddr != address(0)) {
            PDPListener(listenerAddr).rootsAdded(setId, firstAdded, rootData, extraData);
        }

        return firstAdded;
    }

    error IndexedError(uint256 idx, string msg);

    function addOneRoot(uint256 setId, uint256 callIdx, Cids.Cid calldata root, uint256 rawSize) internal returns (uint256) {
        if (rawSize % LEAF_SIZE != 0) {
            revert IndexedError(callIdx, "Size must be a multiple of 32");
        }
        if (rawSize == 0) {
            revert IndexedError(callIdx, "Size must be greater than 0");
        }
        if (rawSize > MAX_ROOT_SIZE) {
            revert IndexedError(callIdx, "Root size must be less than 2^50");
        }

        uint256 leafCount = rawSize / LEAF_SIZE;
        uint256 rootId = nextRootId[setId]++;
        sumTreeAdd(setId, leafCount, rootId);
        rootCids[setId][rootId] = root;
        rootLeafCounts[setId][rootId] = leafCount;
        proofSetLeafCount[setId] += leafCount;
        return rootId;
    }

    // scheduleRemovals scheduels removal of a batch of roots from a proof set for the start of the next
    // proving period. It must be called by the proof set owner.
    function scheduleRemovals(uint256 setId, uint256[] calldata rootIds, bytes calldata extraData) public {
        require(extraData.length <= EXTRA_DATA_MAX_SIZE, "Extra data too large");
        require(proofSetLive(setId), "Proof set not live");
        require(proofSetOwner[setId] == msg.sender, "Only the owner can schedule removal of roots");
        require(rootIds.length + scheduledRemovals[setId].length <= MAX_ENQUEUED_REMOVALS, "Too many removals wait for next proving period to schedule");

        for (uint256 i = 0; i < rootIds.length; i++){
            require(rootIds[i] < nextRootId[setId], "Can only schedule removal of existing roots");
            scheduledRemovals[setId].push(rootIds[i]);
        }

        address listenerAddr = proofSetListener[setId];
        if (listenerAddr != address(0)) {
            PDPListener(listenerAddr).rootsScheduledRemove(setId, rootIds, extraData);
        }
    }

    struct Proof {
        bytes32 leaf;
        bytes32[] proof;
    }

    // Verifies and records that the provider proved possession of the
    // proof set Merkle roots at some epoch. The challenge seed is determined
    // by the epoch of the previous proof of possession.
    // Note that this method is not restricted to the proof set owner.
    function provePossession(uint256 setId, Proof[] calldata proofs) public payable{
        uint256 initialGas = gasleft();
        require(msg.sender == proofSetOwner[setId], "only the owner can move to next proving period");
        uint256 challengeEpoch = nextChallengeEpoch[setId];
        require(block.number >= challengeEpoch, "premature proof");
        require(proofs.length > 0, "empty proof");
        require(challengeEpoch != NO_CHALLENGE_SCHEDULED, "no challenge scheduled");
        RootIdAndOffset[] memory challenges = new RootIdAndOffset[](proofs.length);
        
        uint256 seed = drawChallengeSeed(setId);
        uint256 leafCount = challengeRange[setId];
        uint256 sumTreeTop = 256 - BitOps.clz(nextRootId[setId]);
        for (uint64 i = 0; i < proofs.length; i++) {
            // Hash (SHA3) the seed,  proof set id, and proof index to create challenge.
            // Note -- there is a slight deviation here from the uniform distribution.
            // Some leaves are challenged with probability p and some have probability p + deviation. 
            // This deviation is bounded by leafCount / 2^256 given a 256 bit hash.
            // Deviation grows with proofset leaf count.
            // Assuming a 1000EiB = 1 ZiB network size ~ 2^70 bytes of data or 2^65 leaves
            // This deviation is bounded by 2^65 / 2^256 = 2^-191 which is negligible.            
            //   If modifying this code to use a hash function with smaller output size 
            //   this deviation will increase and caution is advised.
            // To remove this deviation we could use the standard solution of rejection sampling
            //   This is complicated and slightly more costly at one more hash on average for maximally misaligned proofsets
            //   and comes at no practical benefit given how small the deviation is.
            bytes memory payload = abi.encodePacked(seed, setId, i);
            uint256 challengeIdx = uint256(keccak256(payload)) % leafCount;

            // Find the root that has this leaf, and the offset of the leaf within that root.
            challenges[i] = findOneRootId(setId, challengeIdx, sumTreeTop);
            bytes32 rootHash = Cids.digestFromCid(getRootCid(setId, challenges[i].rootId));
            bool ok = MerkleVerify.verify(proofs[i].proof, rootHash, proofs[i].leaf, challenges[i].offset);
            require(ok, "proof did not verify");
        }

     
        // Note: We don't want to include gas spent on the listener call in the fee calculation
        // to only account for proof verification fees and avoid gamability by getting the listener
        // to do extraneous work just to inflate the gas fee.
        //
        // (add 32 bytes to the `callDataSize` to also account for the `setId` calldata param)
        uint256 gasUsed = (initialGas - gasleft()) + ((calculateCallDataSize(proofs) + 32) * 1300);
        calculateAndBurnProofFee(setId, gasUsed);

        address listenerAddr = proofSetListener[setId];
        if (listenerAddr != address(0)) {
            PDPListener(listenerAddr).possessionProven(setId, proofSetLeafCount[setId], seed, proofs.length);
        }
        proofSetLastProvenEpoch[setId] = block.number;
        emit PossessionProven(setId, challenges);
    }

    function calculateProofFee(uint256 setId, uint256 estimatedGasFee) public view returns (uint256) {
        uint256 rawSize = 32 * challengeRange[setId];
        (uint64 filUsdPrice, int32 filUsdPriceExpo) = getFILUSDPrice();

        return PDPFees.proofFeeWithGasFeeBound(
            estimatedGasFee,
            filUsdPrice,
            filUsdPriceExpo,
            rawSize,
            block.number - proofSetLastProvenEpoch[setId]
        );
    }

    function calculateAndBurnProofFee(uint256 setId, uint256 gasUsed) internal {
        uint256 estimatedGasFee = gasUsed * block.basefee;
        uint256 rawSize = 32 * challengeRange[setId];
        (uint64 filUsdPrice, int32 filUsdPriceExpo) = getFILUSDPrice();

        uint256 proofFee = PDPFees.proofFeeWithGasFeeBound(
            estimatedGasFee,
            filUsdPrice,
            filUsdPriceExpo,
            rawSize,
            block.number - proofSetLastProvenEpoch[setId]
        );        
        burnFee(proofFee);
        if (msg.value > proofFee) {
            // Return the overpayment
            payable(msg.sender).transfer(msg.value - proofFee);
        }
        emit ProofFeePaid(setId, proofFee, filUsdPrice, filUsdPriceExpo);
    }

    function calculateCallDataSize(Proof[] calldata proofs) internal pure returns (uint256) {
        uint256 callDataSize = 0;
        for (uint256 i = 0; i < proofs.length; i++) {
            // 64 for the (leaf + abi encoding overhead ) + each element in the proof is 32 bytes
            callDataSize += 64 + (proofs[i].proof.length * 32);
        }
        return callDataSize;
    }

    function getRandomness(uint256 epoch) public view returns (uint256) {
        // Call the precompile
        (bool success, bytes memory result) = RANDOMNESS_PRECOMPILE.staticcall(abi.encodePacked(epoch));

        // Check if the call was successful
        require(success, "Randomness precompile call failed");

        // Decode and return the result
        return abi.decode(result, (uint256));
    }


    function drawChallengeSeed(uint256 setId) internal view returns (uint256) {
        return getRandomness(nextChallengeEpoch[setId]);
    }

    // Roll over to the next proving period
    //
    // This method updates the collection of provable roots in the proof set by
    // 1. Actually removing the roots that have been scheduled for removal
    // 2. Updating the challenge range to now include leaves added in the last proving period
    // So after this method is called roots scheduled for removal are no longer eligible for challenging
    // and can be deleted.  And roots added in the last proving period must be available for challenging.
    //
    // Additionally this method forces sampling of a new challenge.  It enforces that the new
    // challenge epoch is at least `challengeFinality` epochs in the future.
    //
    // Note that this method can be called at any time but the pdpListener will likely consider it
    // a "fault" or other penalizeable behavior to call this method before calling provePossesion.
    function nextProvingPeriod(uint256 setId, uint256 challengeEpoch, bytes calldata extraData) public {
        require(extraData.length <= EXTRA_DATA_MAX_SIZE, "Extra data too large");
        require(msg.sender == proofSetOwner[setId], "only the owner can move to next proving period");
        require(proofSetLeafCount[setId] > 0, "can only start proving once leaves are added");
        
        if (proofSetLastProvenEpoch[setId] == NO_PROVEN_EPOCH) {
            proofSetLastProvenEpoch[setId] = block.number;
        }

        // Take removed roots out of proving set
        uint256[] storage removals = scheduledRemovals[setId];
        uint256[] memory removalsToProcess = new uint256[](removals.length);

        for (uint256 i = 0; i < removalsToProcess.length; i++) {
            removalsToProcess[i] = removals[removals.length - 1];
            removals.pop();
        }

        removeRoots(setId, removalsToProcess);
        emit RootsRemoved(setId, removalsToProcess);
        
        // Bring added roots into proving set
        challengeRange[setId] = proofSetLeafCount[setId];
        if (challengeEpoch < block.number + challengeFinality) {
            revert("challenge epoch must be at least challengeFinality epochs in the future");
        }
        nextChallengeEpoch[setId] = challengeEpoch;

        // Clear next challenge epoch if the set is now empty.
        // It will be re-set after new data is added and nextProvingPeriod is called.
        if (proofSetLeafCount[setId] == 0) {
            emit ProofSetEmpty(setId);
            proofSetLastProvenEpoch[setId] = NO_PROVEN_EPOCH;
            nextChallengeEpoch[setId] = NO_CHALLENGE_SCHEDULED;
        }

        address listenerAddr = proofSetListener[setId];
        if (listenerAddr != address(0)) {
            PDPListener(listenerAddr).nextProvingPeriod(setId, nextChallengeEpoch[setId], proofSetLeafCount[setId], extraData);
        }
        emit NextProvingPeriod(setId, challengeEpoch, proofSetLeafCount[setId]);
    }

    // removes roots from a proof set's state.
    function removeRoots(uint256 setId, uint256[] memory rootIds) internal {
        require(proofSetLive(setId), "Proof set not live");
        uint256 totalDelta = 0;
        for (uint256 i = 0; i < rootIds.length; i++){
            totalDelta += removeOneRoot(setId, rootIds[i]);
        }
        proofSetLeafCount[setId] -= totalDelta;
    }

    // removeOneRoot removes a root's array entries from the proof sets state and returns
    // the number of leafs by which to reduce the total proof set leaf count.
    function removeOneRoot(uint256 setId, uint256 rootId) internal returns (uint256) {
        uint256 delta = rootLeafCounts[setId][rootId];
        sumTreeRemove(setId, rootId, delta);
        delete rootLeafCounts[setId][rootId];
        delete rootCids[setId][rootId];
        return delta;
    }

    /* Sum tree functions */
    /*
    A sumtree is a variant of a Fenwick or binary indexed tree.  It is a binary
    tree where each node is the sum of its children. It is designed to support
    efficient query and update operations on a base array of integers. Here
    the base array is the roots leaf count array.  Asymptotically the sum tree
    has logarithmic search and update functions.  Each slot of the sum tree is
    logically a node in a binary tree.

    The node’s height from the leaf depth is defined as -1 + the ruler function
    (https://oeis.org/A001511 [0,1,0,2,0,1,0,3,0,1,0,2,0,1,0,4,...]) applied to
    the slot’s index + 1, i.e. the number of trailing 0s in the binary representation
    of the index + 1.  Each slot in the sum tree array contains the sum of a range
    of the base array.  The size of this range is defined by the height assigned
    to this slot in the binary tree structure of the sum tree, i.e. the value of
    the ruler function applied to the slot’s index.  The range for height d and
    current index j is [j + 1 - 2^d : j] inclusive.  For example if the node’s
    height is 0 its value is set to the base array’s value at the same index and
    if the node’s height is 3 then its value is set to the sum of the last 2^3 = 8
    values of the base array. The reason to do things with recursive partial sums
    is to accommodate O(log len(base array)) updates for add and remove operations
    on the base array.
    */

    // Perform sumtree addition
    //
    function sumTreeAdd(uint256 setId, uint256 count, uint256 rootId) internal {
        uint256 index = rootId;
        uint256 h = heightFromIndex(index);

        uint256 sum = count;
        // Sum BaseArray[j - 2^i] for i in [0, h)
        for (uint256 i = 0; i < h; i++) {
            uint256 j = index - (1 << i);
            sum += sumTreeCounts[setId][j];
        }
        sumTreeCounts[setId][rootId] = sum;
    }

    // Perform sumtree removal
    //
    function sumTreeRemove(uint256 setId, uint256 index, uint256 delta) internal {
        uint256 top = uint256(256 - BitOps.clz(nextRootId[setId]));
        uint256 h = uint256(heightFromIndex(index));

        // Deletion traversal either terminates at
        // 1) the top of the tree or
        // 2) the highest node right of the removal index
        while (h <= top && index < nextRootId[setId]) {
            sumTreeCounts[setId][index] -= delta;
            index += 1 << h;
            h = heightFromIndex(index);
        }
    }

    struct RootIdAndOffset {
        uint256 rootId;
        uint256 offset;
    }

    // Perform sumtree find
    function findOneRootId(uint256 setId, uint256 leafIndex, uint256 top) internal view returns (RootIdAndOffset memory) {
        require(leafIndex < proofSetLeafCount[setId], "Leaf index out of bounds");
        uint256 searchPtr = (1 << top) - 1;
        uint256 acc = 0;

        // Binary search until we find the index of the sumtree leaf covering the index range
        uint256 candidate;
        for (uint256 h = top; h > 0; h--) {
            // Search has taken us past the end of the sumtree
            // Only option is to go left
            if (searchPtr >= nextRootId[setId]) {
                searchPtr -= 1 << (h - 1);
                continue;
            }

            candidate = acc + sumTreeCounts[setId][searchPtr];
            // Go right
            if (candidate <= leafIndex) {
                acc += sumTreeCounts[setId][searchPtr];
                searchPtr += 1 << (h - 1);
            } else {
                // Go left
                searchPtr -= 1 << (h - 1);
            }
        }
        candidate = acc + sumTreeCounts[setId][searchPtr];
        if (candidate <= leafIndex) {
            // Choose right
            return RootIdAndOffset(searchPtr + 1, leafIndex - candidate);
        } // Choose left
        return RootIdAndOffset(searchPtr, leafIndex - acc);
    }

    // findRootIds is a batched version of findOneRootId
    function findRootIds(uint256 setId, uint256[] calldata leafIndexs) public view returns (RootIdAndOffset[] memory) {
        // The top of the sumtree is the largest power of 2 less than the number of roots
        uint256 top = 256 - BitOps.clz(nextRootId[setId]);
        RootIdAndOffset[] memory result = new RootIdAndOffset[](leafIndexs.length);
        for (uint256 i = 0; i < leafIndexs.length; i++) {
            result[i] = findOneRootId(setId, leafIndexs[i], top);
        }
        return result;
    }

    // Return height of sumtree node at given index
    // Calculated by taking the trailing zeros of 1 plus the index
    function heightFromIndex(uint256 index) internal pure returns (uint256) {
        return BitOps.ctz(index + 1);
    }

    // Add function to get FIL/USD price
    function getFILUSDPrice() public view returns (uint64, int32) {
        // Get FIL/USD price no older than 1 day
        PythStructs.Price memory priceData = PYTH.getPriceNoOlderThan(
            FIL_USD_PRICE_FEED_ID,
            SECONDS_IN_DAY
        );
        require(priceData.price > 0, "failed to validate: price must be greater than 0");

        // Return the price and exponent representing USD per FIL
        return (uint64(priceData.price), priceData.expo);
    }
}
