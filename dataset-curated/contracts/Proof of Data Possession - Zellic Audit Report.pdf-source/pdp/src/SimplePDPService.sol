// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {PDPVerifier, PDPListener} from "./PDPVerifier.sol";
import "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import "../lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import "../lib/openzeppelin-contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";

// PDPRecordKeeper tracks PDP operations.  It is used as a base contract for PDPListeners
// in order to give users the capability to consume events async.
/// @title PDPRecordKeeper
/// @dev This contract is unused by the SimplePDPService as it is too expensive. 
/// we've kept it here for future reference and testing.
contract PDPRecordKeeper {
    enum OperationType {
        NONE,
        CREATE,
        DELETE,
        ADD,
        REMOVE_SCHEDULED,
        PROVE_POSSESSION,
        NEXT_PROVING_PERIOD
    }

    // Struct to store event details
    struct EventRecord {
        uint64 epoch;
        uint256 proofSetId;
        OperationType operationType;
        bytes extraData;
    }

    // Eth event emitted when a new record is added
    event RecordAdded(uint256 indexed proofSetId, uint64 epoch, OperationType operationType);

    // Mapping to store events for each proof set
    mapping(uint256 => EventRecord[]) public proofSetEvents;

    function receiveProofSetEvent(uint256 proofSetId, OperationType operationType, bytes memory extraData ) internal returns(uint256) {
        uint64 epoch = uint64(block.number);
        EventRecord memory newRecord = EventRecord({
            epoch: epoch,
            proofSetId: proofSetId,
            operationType: operationType,
            extraData: extraData
        });
        proofSetEvents[proofSetId].push(newRecord);
        emit RecordAdded(proofSetId, epoch, operationType);
        return proofSetEvents[proofSetId].length - 1;
    }

    // Function to get the number of events for a proof set
    function getEventCount(uint256 proofSetId) external view returns (uint256) {
        return proofSetEvents[proofSetId].length;
    }

    // Function to get a specific event for a proof set
    function getEvent(uint256 proofSetId, uint256 eventIndex)
        external
        view
        returns (EventRecord memory)
    {
        require(eventIndex < proofSetEvents[proofSetId].length, "Event index out of bounds");
        return proofSetEvents[proofSetId][eventIndex];
    }

    // Function to get all events for a proof set
    function listEvents(uint256 proofSetId) external view returns (EventRecord[] memory) {
        return proofSetEvents[proofSetId];
    }
}

/// @title SimplePDPService
/// @notice A default implementation of a PDP Listener.
/// @dev This contract only supports one PDP service caller, set in the constructor,
/// The primary purpose of this contract is to 
/// 1. Enforce a proof count of 5 proofs per proof set proving period.
/// 2. Provide a reliable way to report faults to users.
contract SimplePDPService is PDPListener, Initializable, UUPSUpgradeable, OwnableUpgradeable {
    event FaultRecord(uint256 indexed proofSetId, uint256 periodsFaulted, uint256 deadline);

    uint256 public constant NO_CHALLENGE_SCHEDULED = 0;
    uint256 public constant NO_PROVING_DEADLINE = 0;

    // The address of the PDP verifier contract that is allowed to call this contract
    address public pdpVerifierAddress;
    mapping(uint256 => uint256) public provingDeadlines;
    mapping(uint256 => bool) public provenThisPeriod;

     /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
     _disableInitializers();
    }

    function initialize(address _pdpVerifierAddress) public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        require(_pdpVerifierAddress != address(0), "PDP verifier address cannot be zero");
        pdpVerifierAddress = _pdpVerifierAddress;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // Modifier to ensure only the PDP verifier contract can call certain functions
    modifier onlyPDPVerifier() {
        require(msg.sender == pdpVerifierAddress, "Caller is not the PDP verifier");
        _;
    }

    // SLA specification functions setting values for PDP service providers
    // Max number of epochs between two consecutive proofs
    function getMaxProvingPeriod() public pure returns (uint64) {
        return 2880;
    }

    // Number of epochs at the end of a proving period during which a
    // proof of possession can be submitted
    function challengeWindow() public pure returns (uint256) {
        return 60;
    }

    // Initial value for challenge window start
    // Can be used for first call to nextProvingPeriod
    function initChallengeWindowStart() public view returns (uint256) {
        return block.number + getMaxProvingPeriod() - challengeWindow();
    }

    // The start of the challenge window for the current proving period
    function thisChallengeWindowStart(uint256 setId) public view returns (uint256) {
        if (provingDeadlines[setId] == NO_PROVING_DEADLINE) {
            revert("Proving period not yet initialized");
        }

        uint256 periodsSkipped;
        // Proving period is open 0 skipped periods
        if (block.number <= provingDeadlines[setId]) {
            periodsSkipped = 0;
        } else { // Proving period has closed possibly some skipped periods
            periodsSkipped = 1 + (block.number - (provingDeadlines[setId] + 1)) / getMaxProvingPeriod();
        }
        return provingDeadlines[setId] + periodsSkipped*getMaxProvingPeriod() - challengeWindow();
    }

    // The start of the NEXT OPEN proving period's challenge window
    // Useful for querying before nextProvingPeriod to determine challengeEpoch to submit for nextProvingPeriod
    function nextChallengeWindowStart(uint256 setId) public view returns (uint256) {
        if (provingDeadlines[setId] == NO_PROVING_DEADLINE) {
            revert("Proving period not yet initialized");
        }
        // If the current period is open this is the next period's challenge window
        if (block.number <= provingDeadlines[setId]) {
            return thisChallengeWindowStart(setId) + getMaxProvingPeriod();
        }
        // If the current period is not yet open this is the current period's challenge window
        return thisChallengeWindowStart(setId);
    }

    // Challenges / merkle inclusion proofs provided per proof set
    function getChallengesPerProof() public pure returns (uint64) {
        return 5;
    }

    // Listener interface methods
    // Note many of these are noops as they are not important for the SimplePDPService's functionality
    // of enforcing proof contraints and reporting faults.
    // Note we generally just drop the user defined extraData as this contract has no use for it
    function proofSetCreated(uint256 proofSetId, address creator, bytes calldata) external onlyPDPVerifier {}

    function proofSetDeleted(uint256 proofSetId, uint256 deletedLeafCount, bytes calldata) external onlyPDPVerifier {}

    function rootsAdded(uint256 proofSetId, uint256 firstAdded, PDPVerifier.RootData[] memory rootData, bytes calldata) external onlyPDPVerifier {}

    function rootsScheduledRemove(uint256 proofSetId, uint256[] memory rootIds, bytes calldata) external onlyPDPVerifier {}

    // possession proven checks for correct challenge count and reverts if too low
    // it also checks that proofs are not late and emits a fault record if so
    function possessionProven(uint256 proofSetId, uint256 /*challengedLeafCount*/, uint256 /*seed*/, uint256 challengeCount) external onlyPDPVerifier {
        if (provenThisPeriod[proofSetId]) {
            revert("Only one proof of possession allowed per proving period. Open a new proving period.");
        }
        if (challengeCount < getChallengesPerProof()) {
            revert("Invalid challenge count < 5");
        }
        if (provingDeadlines[proofSetId] == NO_PROVING_DEADLINE) {
            revert("Proving not yet started");
        }
        // check for proof outside of challenge window
        if (provingDeadlines[proofSetId] < block.number) {
            revert("Current proving period passed. Open a new proving period.");
        }

        if (provingDeadlines[proofSetId] - challengeWindow() > block.number) {
            revert("Too early. Wait for challenge window to open");
        }
        provenThisPeriod[proofSetId] = true;
    }

    // nextProvingPeriod checks for unsubmitted proof in which case it emits a fault event
    // Additionally it enforces constraints on the update of its state: 
    // 1. One update per proving period.
    // 2. Next challenge epoch must fall within the challenge window in the last challengeWindow()
    //    epochs of the proving period.
    function nextProvingPeriod(uint256 proofSetId, uint256 challengeEpoch, uint256 /*leafCount*/, bytes calldata) external onlyPDPVerifier {
        // initialize state for new proofset
        if (provingDeadlines[proofSetId] == NO_PROVING_DEADLINE) {
            uint256 firstDeadline = block.number + getMaxProvingPeriod();
            if (challengeEpoch < firstDeadline - challengeWindow() || challengeEpoch > firstDeadline) {
                revert("Next challenge epoch must fall within the next challenge window");
            }
            provingDeadlines[proofSetId] = firstDeadline;
            provenThisPeriod[proofSetId] = false;
            return;
        }

        // Revert when proving period not yet open
        // Can only get here if calling nextProvingPeriod multiple times within the same proving period
        uint256 prevDeadline = provingDeadlines[proofSetId] - getMaxProvingPeriod();
        if (block.number <= prevDeadline) {
            revert("One call to nextProvingPeriod allowed per proving period");
        }

        uint256 periodsSkipped;
        // Proving period is open 0 skipped periods
        if (block.number <= provingDeadlines[proofSetId]) {
            periodsSkipped = 0;
        } else { // Proving period has closed possibly some skipped periods
            periodsSkipped = (block.number - (provingDeadlines[proofSetId] + 1)) / getMaxProvingPeriod();
        }

        uint256 nextDeadline;
        // the proofset has become empty and provingDeadline is set inactive
        if (challengeEpoch == NO_CHALLENGE_SCHEDULED) {
            nextDeadline = NO_PROVING_DEADLINE;
        } else {
            nextDeadline = provingDeadlines[proofSetId] + getMaxProvingPeriod()*(periodsSkipped+1);
            if (challengeEpoch < nextDeadline - challengeWindow() || challengeEpoch > nextDeadline) {
                revert("Next challenge epoch must fall within the next challenge window");
            }
        }
        uint256 faultPeriods = periodsSkipped;
        if (!provenThisPeriod[proofSetId]) {
            // include previous unproven period
            faultPeriods += 1;
        }
        if (faultPeriods > 0) {
            emit FaultRecord(proofSetId, faultPeriods, provingDeadlines[proofSetId]);
        }
        provingDeadlines[proofSetId] = nextDeadline;
        provenThisPeriod[proofSetId] = false;
    }
}
