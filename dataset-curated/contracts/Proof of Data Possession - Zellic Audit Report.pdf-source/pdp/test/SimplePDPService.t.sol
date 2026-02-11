// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {PDPListener, PDPVerifier} from "../src/PDPVerifier.sol";
import {SimplePDPService, PDPRecordKeeper} from "../src/SimplePDPService.sol";
import {MyERC1967Proxy} from "../src/ERC1967Proxy.sol";
import {Cids} from "../src/Cids.sol";


contract SimplePDPServiceTest is Test {
    SimplePDPService public pdpService;
    address public pdpVerifierAddress;
    bytes empty = new bytes(0);
    uint256 public proofSetId;
    uint256 public leafCount;
    uint256 public seed;

    function setUp() public {
        pdpVerifierAddress = address(this);
        SimplePDPService pdpServiceImpl = new SimplePDPService();
        bytes memory initializeData = abi.encodeWithSelector(SimplePDPService.initialize.selector, address(pdpVerifierAddress));
        MyERC1967Proxy pdpServiceProxy = new MyERC1967Proxy(address(pdpServiceImpl), initializeData);
        pdpService = SimplePDPService(address(pdpServiceProxy));
        proofSetId = 1;
        leafCount = 100;
        seed = 12345;

    }

    function testInitialState() public view {
        assertEq(pdpService.pdpVerifierAddress(), pdpVerifierAddress, "PDP verifier address should be set correctly");
    }


    function testOnlyPDPVerifierCanAddRecord() public {
        vm.prank(address(0xdead));
        vm.expectRevert("Caller is not the PDP verifier");
        pdpService.proofSetCreated(proofSetId, address(this), empty);
    }

    function testGetMaxProvingPeriod() public view {
        uint64 maxPeriod = pdpService.getMaxProvingPeriod();
        assertEq(maxPeriod, 2880, "Max proving period should be 2880");
    }

    function testGetChallengesPerProof() public view{
        uint64 challenges = pdpService.getChallengesPerProof();
        assertEq(challenges, 5, "Challenges per proof should be 5");
    }

    function testInitialProvingPeriodHappyPath() public {
        pdpService.rootsAdded(proofSetId, 0, new PDPVerifier.RootData[](0), empty);
        uint256 challengeEpoch = pdpService.initChallengeWindowStart();

        pdpService.nextProvingPeriod(proofSetId, challengeEpoch, leafCount, empty);

        assertEq(
            pdpService.provingDeadlines(proofSetId),
            block.number + pdpService.getMaxProvingPeriod(),
            "Deadline should be set to current block + max period"
        );
        assertFalse(pdpService.provenThisPeriod(proofSetId));
    }

    function testInitialProvingPeriodInvalidChallengeEpoch() public {
        pdpService.rootsAdded(proofSetId, 0, new PDPVerifier.RootData[](0), empty);
        uint256 firstDeadline = block.number + pdpService.getMaxProvingPeriod();

        // Test too early
        uint256 tooEarly = firstDeadline - pdpService.challengeWindow() - 1;
        vm.expectRevert("Next challenge epoch must fall within the next challenge window");
        pdpService.nextProvingPeriod(proofSetId, tooEarly, leafCount, empty);

        // Test too late
        uint256 tooLate = firstDeadline + 1;
        vm.expectRevert("Next challenge epoch must fall within the next challenge window");
        pdpService.nextProvingPeriod(proofSetId, tooLate, leafCount, empty);
    }

    function testInactivateProofSetHappyPath() public {
        // Setup initial state
        pdpService.rootsAdded(proofSetId, 0, new PDPVerifier.RootData[](0), empty);
        pdpService.nextProvingPeriod(proofSetId, pdpService.initChallengeWindowStart(), leafCount, empty);

        // Prove possession in first period
        vm.roll(block.number + pdpService.getMaxProvingPeriod() - pdpService.challengeWindow());
        pdpService.possessionProven(proofSetId, leafCount, seed, 5);

        // Inactivate the proof set
        pdpService.nextProvingPeriod(proofSetId, pdpService.NO_CHALLENGE_SCHEDULED(), leafCount, empty);

        assertEq(
            pdpService.provingDeadlines(proofSetId),
            pdpService.NO_PROVING_DEADLINE(),
            "Proving deadline should be set to NO_PROVING_DEADLINE"
        );
        assertEq(
            pdpService.provenThisPeriod(proofSetId),
            false,
            "Proven this period should now be false"
        );
    }
}

contract SimplePDPServiceFaultsTest is Test {
    SimplePDPService public pdpService;
    address public pdpVerifierAddress;
    uint256 public proofSetId;
    uint256 public leafCount;
    uint256 public seed;
    uint256 public challengeCount;
    bytes empty = new bytes(0);

    function setUp() public {
        pdpVerifierAddress = address(this);
        SimplePDPService pdpServiceImpl = new SimplePDPService();
        bytes memory initializeData = abi.encodeWithSelector(SimplePDPService.initialize.selector, address(pdpVerifierAddress));
        MyERC1967Proxy pdpServiceProxy = new MyERC1967Proxy(address(pdpServiceImpl), initializeData);
        pdpService = SimplePDPService(address(pdpServiceProxy));
        proofSetId = 1;
        leafCount = 100;
        seed = 12345;
        challengeCount = 5;
    }

    function testPossessionProvenOnTime() public {
        // Set up the proving deadline
        pdpService.rootsAdded(proofSetId, 0, new PDPVerifier.RootData[](0), empty);
        pdpService.nextProvingPeriod(proofSetId, pdpService.initChallengeWindowStart(), leafCount, empty);
        vm.roll(block.number + pdpService.getMaxProvingPeriod() - pdpService.challengeWindow());
        pdpService.possessionProven(proofSetId, leafCount, seed, challengeCount);
        assertTrue(pdpService.provenThisPeriod(proofSetId));

        pdpService.nextProvingPeriod(proofSetId, pdpService.nextChallengeWindowStart(proofSetId), leafCount, empty);
        vm.roll(block.number + pdpService.getMaxProvingPeriod());
        pdpService.possessionProven(proofSetId, leafCount, seed, challengeCount);
    }

    function testNextProvingPeriodCalledLastMinuteOK() public {
        pdpService.rootsAdded(proofSetId, 0, new PDPVerifier.RootData[](0), empty);
        pdpService.nextProvingPeriod(proofSetId, pdpService.initChallengeWindowStart(), leafCount, empty);
        vm.roll(block.number + pdpService.getMaxProvingPeriod());
        pdpService.possessionProven(proofSetId, leafCount, seed, challengeCount);

        // wait until almost the end of proving period 2
        // this should all work fine
        vm.roll(block.number + pdpService.getMaxProvingPeriod());
        pdpService.nextProvingPeriod(proofSetId, pdpService.nextChallengeWindowStart(proofSetId), leafCount, empty);
        pdpService.possessionProven(proofSetId, leafCount, seed, challengeCount);
    }

    function testFirstEpochLateToProve() public {
        pdpService.rootsAdded(proofSetId, 0, new PDPVerifier.RootData[](0), empty);
        pdpService.nextProvingPeriod(proofSetId, pdpService.initChallengeWindowStart(), leafCount, empty);
        vm.roll(block.number + pdpService.getMaxProvingPeriod() + 1);
        vm.expectRevert("Current proving period passed. Open a new proving period.");
        pdpService.possessionProven(proofSetId, leafCount, seed, challengeCount);
    }

    function testNextProvingPeriodTwiceFails() public {
        // Set up the proving deadline
        pdpService.rootsAdded(proofSetId, 0, new PDPVerifier.RootData[](0), empty);
        pdpService.nextProvingPeriod(proofSetId, pdpService.initChallengeWindowStart(), leafCount, empty);
        vm.roll(block.number + pdpService.getMaxProvingPeriod() - pdpService.challengeWindow());
        pdpService.possessionProven(proofSetId, leafCount, seed, challengeCount);
        uint256 deadline1 = pdpService.provingDeadlines(proofSetId);
        assertTrue(pdpService.provenThisPeriod(proofSetId));

        assertEq(pdpService.provingDeadlines(proofSetId), deadline1, "Proving deadline should not change until nextProvingPeriod.");
        uint256 challengeEpoch = pdpService.nextChallengeWindowStart(proofSetId);
        pdpService.nextProvingPeriod(proofSetId, challengeEpoch, leafCount, empty);
        assertEq(pdpService.provingDeadlines(proofSetId), deadline1 + pdpService.getMaxProvingPeriod(), "Proving deadline should be updated");
        assertFalse(pdpService.provenThisPeriod(proofSetId));

        vm.expectRevert("One call to nextProvingPeriod allowed per proving period");
        pdpService.nextProvingPeriod(proofSetId, challengeEpoch, leafCount, empty);
    }

    function testFaultWithinOpenPeriod() public {
        pdpService.rootsAdded(proofSetId, 0, new PDPVerifier.RootData[](0), empty);
        pdpService.nextProvingPeriod(proofSetId, pdpService.initChallengeWindowStart(), leafCount, empty);

        // Move to open proving period
        vm.roll(block.number + pdpService.getMaxProvingPeriod() - 100);

        // Expect fault event when calling nextProvingPeriod without proof
        vm.expectEmit(true, true, true, true);
        emit SimplePDPService.FaultRecord(proofSetId, 1, pdpService.provingDeadlines(proofSetId));
        pdpService.nextProvingPeriod(proofSetId, pdpService.nextChallengeWindowStart(proofSetId), leafCount, empty);
    }

    function testFaultAfterPeriodOver() public {
        pdpService.rootsAdded(proofSetId, 0, new PDPVerifier.RootData[](0), empty);
        pdpService.nextProvingPeriod(proofSetId, pdpService.initChallengeWindowStart(), leafCount, empty);

        // Move past proving period
        vm.roll(block.number + pdpService.getMaxProvingPeriod() + 1);

        // Expect fault event when calling nextProvingPeriod without proof
        vm.expectEmit(true, true, true, true);
        emit SimplePDPService.FaultRecord(proofSetId, 1, pdpService.provingDeadlines(proofSetId));
        pdpService.nextProvingPeriod(proofSetId, pdpService.nextChallengeWindowStart(proofSetId), leafCount, empty);
    }

    function testNextProvingPeriodWithoutProof() public {
        // Set up the proving deadline without marking as proven
        pdpService.rootsAdded(proofSetId, 0, new PDPVerifier.RootData[](0), empty);
        pdpService.nextProvingPeriod(proofSetId, pdpService.initChallengeWindowStart(), leafCount, empty);
        // Move to the next period
        vm.roll(block.number + pdpService.getMaxProvingPeriod() + 1);
        // Expect a fault event
        vm.expectEmit();
        emit SimplePDPService.FaultRecord(proofSetId, 1, pdpService.provingDeadlines(proofSetId));
        pdpService.nextProvingPeriod(proofSetId, pdpService.nextChallengeWindowStart(proofSetId), leafCount, empty);
        assertFalse(pdpService.provenThisPeriod(proofSetId));
    }

    function testInvalidChallengeCount() public {
        uint256 invalidChallengeCount = 4; // Less than required

        pdpService.rootsAdded(proofSetId, 0, new PDPVerifier.RootData[](0), empty);
        pdpService.nextProvingPeriod(proofSetId, pdpService.initChallengeWindowStart(), leafCount, empty);
        vm.expectRevert("Invalid challenge count < 5");
        pdpService.possessionProven(proofSetId, leafCount, seed, invalidChallengeCount);
    }

    function testMultiplePeriodsLate() public {
        // Set up the proving deadline
        pdpService.rootsAdded(proofSetId, 0, new PDPVerifier.RootData[](0), empty);
        pdpService.nextProvingPeriod(proofSetId, pdpService.initChallengeWindowStart(), leafCount, empty);
        // Warp to 3 periods after the deadline
        vm.roll(block.number + pdpService.getMaxProvingPeriod() * 3 + 1);
        // unable to prove possession
        vm.expectRevert("Current proving period passed. Open a new proving period.");
        pdpService.possessionProven(proofSetId, leafCount, seed, challengeCount);

        vm.expectEmit(true, true, true, true);
        emit SimplePDPService.FaultRecord(proofSetId, 3, pdpService.provingDeadlines(proofSetId));
        pdpService.nextProvingPeriod(proofSetId, pdpService.nextChallengeWindowStart(proofSetId), leafCount, empty);
    }

    function testMultiplePeriodsLateWithInitialProof() public {
        // Set up the proving deadline
        pdpService.rootsAdded(proofSetId, 0, new PDPVerifier.RootData[](0), empty);

        pdpService.nextProvingPeriod(proofSetId, pdpService.initChallengeWindowStart(), leafCount, empty);
        // Move to first open proving period
        vm.roll(block.number + pdpService.getMaxProvingPeriod() - pdpService.challengeWindow());

        // Submit valid proof in first period
        pdpService.possessionProven(proofSetId, leafCount, seed, challengeCount);
        assertTrue(pdpService.provenThisPeriod(proofSetId));

        // Warp to 3 periods after the deadline
        vm.roll(block.number + pdpService.getMaxProvingPeriod() * 3 + 1);

        // Should emit fault record for 2 periods (current period not counted since not yet expired)
        vm.expectEmit(true, true, true, true);
        emit SimplePDPService.FaultRecord(proofSetId, 2, pdpService.provingDeadlines(proofSetId));
        pdpService.nextProvingPeriod(proofSetId, pdpService.nextChallengeWindowStart(proofSetId), leafCount, empty);
    }

    function testCanOnlyProveOncePerPeriod() public {
        pdpService.rootsAdded(proofSetId, 0, new PDPVerifier.RootData[](0), empty);
        pdpService.nextProvingPeriod(proofSetId, pdpService.initChallengeWindowStart(), leafCount, empty);

        // We're in the previous deadline so we fail to prove until we roll forward into challenge window
        vm.expectRevert("Too early. Wait for challenge window to open");
        pdpService.possessionProven(proofSetId, leafCount, seed, 5);
        vm.roll(block.number + pdpService.getMaxProvingPeriod() - pdpService.challengeWindow() -1);
        // We're one before the challenge window so we should still fail
        vm.expectRevert("Too early. Wait for challenge window to open");
        pdpService.possessionProven(proofSetId, leafCount, seed, 5);
        // now we succeed
        vm.roll(block.number + 1);
        pdpService.possessionProven(proofSetId, leafCount, seed, 5);
        vm.expectRevert("Only one proof of possession allowed per proving period. Open a new proving period.");
        pdpService.possessionProven(proofSetId, leafCount, seed, 5);
    }

    function testCantProveBeforePeriodIsOpen() public {
        pdpService.rootsAdded(proofSetId, 0, new PDPVerifier.RootData[](0), empty);
        pdpService.nextProvingPeriod(proofSetId, pdpService.initChallengeWindowStart(), leafCount, empty);
        vm.roll(block.number + pdpService.getMaxProvingPeriod() - pdpService.challengeWindow());
        pdpService.possessionProven(proofSetId, leafCount, seed, 5);
        pdpService.nextProvingPeriod(proofSetId, pdpService.nextChallengeWindowStart(proofSetId), leafCount, empty);
        vm.expectRevert("Too early. Wait for challenge window to open");
        pdpService.possessionProven(proofSetId, leafCount, seed, 5);
    }

    function testMissChallengeWindow() public {
        pdpService.rootsAdded(proofSetId, 0, new PDPVerifier.RootData[](0), empty);
        pdpService.nextProvingPeriod(proofSetId, pdpService.initChallengeWindowStart(), leafCount, empty);
        vm.roll(block.number + pdpService.getMaxProvingPeriod() - 100);
        // Too early
        uint256 tooEarly = pdpService.nextChallengeWindowStart(proofSetId)-1;
        vm.expectRevert("Next challenge epoch must fall within the next challenge window");
        pdpService.nextProvingPeriod(proofSetId, tooEarly, leafCount, empty);
        // Too late
        uint256 tooLate = pdpService.nextChallengeWindowStart(proofSetId)+pdpService.challengeWindow()+1;
        vm.expectRevert("Next challenge epoch must fall within the next challenge window");
        pdpService.nextProvingPeriod(proofSetId, tooLate, leafCount, empty);

        // Works right on the deadline
        pdpService.nextProvingPeriod(proofSetId, pdpService.nextChallengeWindowStart(proofSetId)+pdpService.challengeWindow(), leafCount, empty);
    }

    function testMissChallengeWindowAfterFaults() public {
        pdpService.rootsAdded(proofSetId, 0, new PDPVerifier.RootData[](0), empty);
        pdpService.nextProvingPeriod(proofSetId, pdpService.initChallengeWindowStart(), leafCount, empty);
        // Skip 2 proving periods
        vm.roll(block.number + pdpService.getMaxProvingPeriod() * 3 - 100);

        // Too early
        uint256 tooEarly = pdpService.nextChallengeWindowStart(proofSetId)-1;
        vm.expectRevert("Next challenge epoch must fall within the next challenge window");
        pdpService.nextProvingPeriod(proofSetId, tooEarly, leafCount, empty);

        // Too late
        uint256 tooLate = pdpService.nextChallengeWindowStart(proofSetId)+pdpService.challengeWindow()+1;
        vm.expectRevert("Next challenge epoch must fall within the next challenge window");
        pdpService.nextProvingPeriod(proofSetId, tooLate, leafCount, empty);

        // Should emit fault record for 2 periods
        vm.expectEmit(true, true, true, true);
        emit SimplePDPService.FaultRecord(proofSetId, 2, pdpService.provingDeadlines(proofSetId));
        // Works right on the deadline
        pdpService.nextProvingPeriod(proofSetId, pdpService.nextChallengeWindowStart(proofSetId)+pdpService.challengeWindow(), leafCount, empty);
    }

    function testInactivateWithCurrentPeriodFault() public {
        // Setup initial state
        pdpService.rootsAdded(proofSetId, 0, new PDPVerifier.RootData[](0), empty);
        pdpService.nextProvingPeriod(proofSetId, pdpService.initChallengeWindowStart(), leafCount, empty);

        // Move to end of period without proving
        vm.roll(block.number + pdpService.getMaxProvingPeriod());

        // Expect fault event for the unproven period
        vm.expectEmit(true, true, true, true);
        emit SimplePDPService.FaultRecord(proofSetId, 1, pdpService.provingDeadlines(proofSetId));

        pdpService.nextProvingPeriod(proofSetId, pdpService.NO_CHALLENGE_SCHEDULED(), leafCount, empty);

        assertEq(
            pdpService.provingDeadlines(proofSetId),
            pdpService.NO_PROVING_DEADLINE(),
            "Proving deadline should be set to NO_PROVING_DEADLINE"
        );
    }

    function testInactivateWithMultiplePeriodFaults() public {
        // Setup initial state
        pdpService.rootsAdded(proofSetId, 0, new PDPVerifier.RootData[](0), empty);
        pdpService.nextProvingPeriod(proofSetId, pdpService.initChallengeWindowStart(), leafCount, empty);

        // Skip 3 proving periods without proving
        vm.roll(block.number + pdpService.getMaxProvingPeriod() * 3 + 1);

        // Expect fault event for all missed periods
        vm.expectEmit(true, true, true, true);
        emit SimplePDPService.FaultRecord(proofSetId, 3, pdpService.provingDeadlines(proofSetId));

        pdpService.nextProvingPeriod(proofSetId, pdpService.NO_CHALLENGE_SCHEDULED(), leafCount, empty);

        assertEq(
            pdpService.provingDeadlines(proofSetId),
            pdpService.NO_PROVING_DEADLINE(),
            "Proving deadline should be set to NO_PROVING_DEADLINE"
        );
    }
}
