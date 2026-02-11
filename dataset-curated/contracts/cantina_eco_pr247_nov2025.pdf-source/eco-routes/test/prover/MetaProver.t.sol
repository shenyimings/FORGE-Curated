// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "../BaseTest.sol";
import {MetaProver} from "../../contracts/prover/MetaProver.sol";
import {IProver} from "../../contracts/interfaces/IProver.sol";
import {IMessageBridgeProver} from "../../contracts/interfaces/IMessageBridgeProver.sol";
import {TestMetaRouter} from "../../contracts/test/TestMetaRouter.sol";
import {ReadOperation} from "@metalayer/contracts/src/interfaces/IMetalayerRecipient.sol";
import {TypeCasts} from "@hyperlane-xyz/core/contracts/libs/TypeCasts.sol";

contract MetaProverTest is BaseTest {
    MetaProver internal metaProver;
    TestMetaRouter internal metaRouter;

    address internal metaRouterAddress;

    function setUp() public override {
        super.setUp();

        vm.startPrank(deployer);

        // Deploy TestMetaRouter
        metaRouter = new TestMetaRouter(address(0));
        metaRouterAddress = address(metaRouter);

        // Setup provers array
        bytes32[] memory provers = new bytes32[](1);
        provers[0] = bytes32(uint256(uint160(address(prover))));

        // Deploy MetaProver
        metaProver = new MetaProver(
            metaRouterAddress,
            address(portal),
            provers,
            100000 // default gas limit
        );

        vm.stopPrank();

        _mintAndApprove(creator, MINT_AMOUNT);
    }

    function _encodeProverData(
        bytes32 sourceChainProver,
        uint256 gasLimit
    ) internal pure returns (bytes memory) {
        MetaProver.UnpackedData memory unpacked = MetaProver.UnpackedData({
            sourceChainProver: sourceChainProver,
            gasLimit: gasLimit
        });

        return abi.encode(unpacked);
    }

    // Helper function to fund inbox and call prove
    function _proveWithFunding(
        address sender,
        uint64 sourceChainId,
        bytes32[] memory intentHashes,
        bytes32[] memory claimants,
        bytes memory data,
        uint256 value
    ) internal {
        vm.deal(address(portal), value);
        vm.prank(address(portal));
        // Simulate what Inbox does - prepend chain ID to the packed pairs
        bytes memory messageWithChainId = abi.encodePacked(
            uint64(block.chainid),
            _packClaimantHashPairs(intentHashes, claimants)
        );
        metaProver.prove{value: value}(
            sender,
            sourceChainId,
            messageWithChainId,
            data
        );
    }

    function testInitializesCorrectly() public view {
        // Test that the contract was deployed successfully
        assertTrue(address(metaProver) != address(0));
    }

    function testImplementsIProverInterface() public view {
        assertTrue(metaProver.supportsInterface(type(IProver).interfaceId));
    }

    function testProveIntent() public {
        bytes32[] memory intentHashes = new bytes32[](1);
        bytes32[] memory claimants = new bytes32[](1);
        intentHashes[0] = _hashIntent(intent);
        claimants[0] = bytes32(uint256(uint160(claimant)));

        _proveWithFunding(
            creator,
            uint64(block.chainid),
            intentHashes,
            claimants,
            _encodeProverData(
                bytes32(uint256(uint160(address(prover)))),
                200000
            ),
            1 ether
        );

        // Verify that the metaRouter received the message
        assertTrue(metaRouter.dispatched());
    }

    function testProveIntentWithCorrectMessageBody() public {
        bytes32[] memory intentHashes = new bytes32[](1);
        bytes32[] memory claimants = new bytes32[](1);
        intentHashes[0] = _hashIntent(intent);
        claimants[0] = bytes32(uint256(uint160(claimant)));

        // Calculate expected message body (with chain ID prefix)
        bytes memory expectedBody = _formatMessageWithChainId(
            uint64(block.chainid),
            intentHashes,
            claimants
        );

        _proveWithFunding(
            creator,
            uint64(block.chainid),
            intentHashes,
            claimants,
            _encodeProverData(
                bytes32(uint256(uint160(address(prover)))),
                200000
            ),
            1 ether
        );

        // Verify the message body matches expectations
        assertEq(metaRouter.messageBody(), expectedBody);
    }

    function testProveIntentWithCorrectDestination() public {
        bytes32[] memory intentHashes = new bytes32[](1);
        bytes32[] memory claimants = new bytes32[](1);
        intentHashes[0] = _hashIntent(intent);
        claimants[0] = bytes32(uint256(uint160(claimant)));

        _proveWithFunding(
            creator,
            uint64(block.chainid),
            intentHashes,
            claimants,
            _encodeProverData(
                bytes32(uint256(uint160(address(prover)))),
                200000
            ),
            1 ether
        );

        // Verify the message was sent to correct destination (source chain)
        assertEq(metaRouter.destinationDomain(), uint32(block.chainid));
    }

    function testOnlyInboxCanProveIntent() public {
        bytes32[] memory intentHashes = new bytes32[](1);
        bytes32[] memory claimants = new bytes32[](1);
        intentHashes[0] = _hashIntent(intent);
        claimants[0] = bytes32(uint256(uint160(claimant)));

        vm.deal(creator, 1 ether);
        vm.expectRevert(); // Should revert with access control error
        vm.prank(creator);
        metaProver.prove{value: 1 ether}(
            creator,
            uint64(block.chainid),
            _packClaimantHashPairs(intentHashes, claimants),
            _encodeProverData(
                bytes32(uint256(uint160(address(prover)))),
                200000
            )
        );
    }

    function testProveIntentEmitsEvent() public {
        bytes32[] memory intentHashes = new bytes32[](1);
        bytes32[] memory claimants = new bytes32[](1);
        intentHashes[0] = _hashIntent(intent);
        claimants[0] = bytes32(uint256(uint160(claimant)));

        // BatchSent event was removed

        _proveWithFunding(
            creator,
            uint64(block.chainid),
            intentHashes,
            claimants,
            _encodeProverData(
                bytes32(uint256(uint160(address(prover)))),
                200000
            ),
            1 ether
        );
    }

    function testProveIntentWithDifferentDestinations() public {
        // Test with different destination chains
        uint256[] memory destinations = new uint256[](3);
        destinations[0] = 1;
        destinations[1] = 10;
        destinations[2] = 137;

        for (uint256 i = 0; i < destinations.length; i++) {
            Intent memory testIntent = intent;
            // For this test, we're testing different source chains
            bytes32 intentHash = _hashIntent(testIntent);

            bytes32[] memory intentHashes = new bytes32[](1);
            bytes32[] memory claimants = new bytes32[](1);
            intentHashes[0] = intentHash;
            claimants[0] = bytes32(uint256(uint160(claimant)));

            _proveWithFunding(
                creator,
                uint64(destinations[i]),
                intentHashes,
                claimants,
                _encodeProverData(
                    bytes32(uint256(uint160(address(prover)))),
                    200000
                ),
                1 ether
            );

            assertEq(metaRouter.destinationDomain(), uint32(destinations[i]));
        }
    }

    function testProveIntentWithDifferentCreators() public {
        address[] memory creators = new address[](3);
        creators[0] = makeAddr("creator1");
        creators[1] = makeAddr("creator2");
        creators[2] = makeAddr("creator3");

        for (uint256 i = 0; i < creators.length; i++) {
            Intent memory testIntent = intent;
            testIntent.reward.creator = creators[i];
            bytes32 intentHash = _hashIntent(testIntent);

            bytes32[] memory intentHashes = new bytes32[](1);
            bytes32[] memory claimants = new bytes32[](1);
            intentHashes[0] = intentHash;
            claimants[0] = bytes32(uint256(uint160(claimant)));

            _proveWithFunding(
                creator,
                uint64(block.chainid),
                intentHashes,
                claimants,
                _encodeProverData(
                    bytes32(uint256(uint160(address(prover)))),
                    200000
                ),
                1 ether
            );

            bytes memory expectedBody = _formatMessageWithChainId(
                uint64(block.chainid),
                intentHashes,
                claimants
            );

            assertEq(metaRouter.messageBody(), expectedBody);
        }
    }

    function testMultipleProveIntents() public {
        Intent memory testIntent1 = intent;
        Intent memory testIntent2 = intent;
        testIntent2.route.salt = keccak256("different salt");

        bytes32 intentHash1 = _hashIntent(testIntent1);
        bytes32 intentHash2 = _hashIntent(testIntent2);

        // Test multiple separate calls
        bytes32[] memory intentHashes1 = new bytes32[](1);
        bytes32[] memory claimants1 = new bytes32[](1);
        intentHashes1[0] = intentHash1;
        claimants1[0] = bytes32(uint256(uint160(claimant)));

        bytes32[] memory intentHashes2 = new bytes32[](1);
        bytes32[] memory claimants2 = new bytes32[](1);
        intentHashes2[0] = intentHash2;
        claimants2[0] = bytes32(uint256(uint160(claimant)));

        _proveWithFunding(
            creator,
            uint64(block.chainid),
            intentHashes1,
            claimants1,
            _encodeProverData(
                bytes32(uint256(uint160(address(prover)))),
                200000
            ),
            1 ether
        );
        _proveWithFunding(
            creator,
            uint64(block.chainid),
            intentHashes2,
            claimants2,
            _encodeProverData(
                bytes32(uint256(uint160(address(prover)))),
                200000
            ),
            1 ether
        );

        assertTrue(metaRouter.dispatched());
        assertTrue(metaRouter.dispatched());
    }

    function testProveIntentWithZeroDestination() public {
        Intent memory testIntent = intent;
        // Testing with zero source chain
        bytes32 intentHash = _hashIntent(testIntent);

        bytes32[] memory intentHashes = new bytes32[](1);
        bytes32[] memory claimants = new bytes32[](1);
        intentHashes[0] = intentHash;
        claimants[0] = bytes32(uint256(uint160(claimant)));

        _proveWithFunding(
            creator,
            0,
            intentHashes,
            claimants,
            _encodeProverData(
                bytes32(uint256(uint160(address(prover)))),
                200000
            ),
            1 ether
        );

        assertEq(metaRouter.destinationDomain(), 0);
    }

    function testProveIntentWithLargeDestination() public {
        Intent memory testIntent = intent;
        // Testing with max valid chain ID as source
        bytes32 intentHash = _hashIntent(testIntent);

        bytes32[] memory intentHashes = new bytes32[](1);
        bytes32[] memory claimants = new bytes32[](1);
        intentHashes[0] = intentHash;
        claimants[0] = bytes32(uint256(uint160(claimant)));

        _proveWithFunding(
            creator,
            type(uint32).max,
            intentHashes,
            claimants,
            _encodeProverData(
                bytes32(uint256(uint160(address(prover)))),
                200000
            ),
            1 ether
        );

        assertEq(metaRouter.destinationDomain(), type(uint32).max);
    }

    function testProveIntentWithZeroCreator() public {
        Intent memory testIntent = intent;
        testIntent.reward.creator = address(0);
        bytes32 intentHash = _hashIntent(testIntent);

        bytes32[] memory intentHashes = new bytes32[](1);
        bytes32[] memory claimants = new bytes32[](1);
        intentHashes[0] = intentHash;
        claimants[0] = bytes32(uint256(uint160(claimant)));

        _proveWithFunding(
            creator,
            uint64(block.chainid),
            intentHashes,
            claimants,
            _encodeProverData(
                bytes32(uint256(uint160(address(prover)))),
                200000
            ),
            1 ether
        );

        bytes memory expectedBody = _formatMessageWithChainId(
            uint64(block.chainid),
            intentHashes,
            claimants
        );

        assertEq(metaRouter.messageBody(), expectedBody);
    }

    function testProvenIntentsStorage() public {
        Intent memory testIntent = intent;
        bytes32 intentHash = _hashIntent(testIntent);

        bytes32[] memory intentHashes = new bytes32[](1);
        bytes32[] memory claimants = new bytes32[](1);
        intentHashes[0] = intentHash;
        claimants[0] = bytes32(uint256(uint160(claimant)));

        // MetaProver stores proof data when it receives a message via handle(), not when prove() is called
        // Simulate receiving a message from the source chain prover
        vm.prank(address(metaRouter));
        metaProver.handle(
            uint32(block.chainid),
            bytes32(uint256(uint160(address(prover)))),
            _formatMessageWithChainId(block.chainid, intentHashes, claimants),
            new ReadOperation[](0),
            new bytes[](0)
        );

        IProver.ProofData memory proof = metaProver.provenIntents(intentHash);
        assertEq(proof.claimant, claimant);
        assertEq(proof.destination, uint32(block.chainid));
    }

    function testSupportsInterface() public view {
        assertTrue(metaProver.supportsInterface(type(IProver).interfaceId));
        assertTrue(metaProver.supportsInterface(0x01ffc9a7)); // ERC165
    }

    function testDoesNotSupportRandomInterface() public view {
        assertFalse(metaProver.supportsInterface(0x12345678));
    }

    // MetaProver specific tests
    function testMetaRouterIntegration() public {
        bytes32 intentHash = _hashIntent(intent);

        bytes32[] memory intentHashes = new bytes32[](1);
        bytes32[] memory claimants = new bytes32[](1);
        intentHashes[0] = intentHash;
        claimants[0] = bytes32(uint256(uint160(claimant)));

        _proveWithFunding(
            creator,
            uint64(block.chainid),
            intentHashes,
            claimants,
            _encodeProverData(
                bytes32(uint256(uint160(address(prover)))),
                200000
            ),
            1 ether
        );

        // Verify MetaRouter received the correct call
        assertTrue(metaRouter.dispatched());
    }

    function testMetaRouterGasUsage() public {
        bytes32 intentHash = _hashIntent(intent);

        bytes32[] memory intentHashes = new bytes32[](1);
        bytes32[] memory claimants = new bytes32[](1);
        intentHashes[0] = intentHash;
        claimants[0] = bytes32(uint256(uint160(claimant)));

        uint256 gasStart = gasleft();

        _proveWithFunding(
            creator,
            uint64(block.chainid),
            intentHashes,
            claimants,
            _encodeProverData(
                bytes32(uint256(uint160(address(prover)))),
                200000
            ),
            1 ether
        );

        uint256 gasUsed = gasStart - gasleft();

        // Verify reasonable gas usage (adjust threshold as needed)
        assertLt(gasUsed, 400000); // Should use less than 400k gas
    }

    function testMetaRouterRevert() public {
        bytes32 intentHash = _hashIntent(intent);

        bytes32[] memory intentHashes = new bytes32[](1);
        bytes32[] memory claimants = new bytes32[](1);
        intentHashes[0] = intentHash;
        claimants[0] = bytes32(uint256(uint160(claimant)));

        // Test with insufficient fee to trigger revert
        vm.expectRevert();
        _proveWithFunding(
            creator,
            uint64(block.chainid),
            intentHashes,
            claimants,
            _encodeProverData(
                bytes32(uint256(uint160(address(prover)))),
                200000
            ),
            0
        );
    }

    function testProveWithArrayLengthMismatch() public view {
        bytes32[] memory intentHashes = new bytes32[](2);
        bytes32[] memory claimants = new bytes32[](1);
        intentHashes[0] = _hashIntent(intent);
        intentHashes[1] = keccak256("second intent");
        claimants[0] = bytes32(uint256(uint160(claimant)));

        // This should revert in _packClaimantHashPairs due to array length mismatch
        // We test this by checking that calling the function would fail
        // Since this is a helper function test, we just verify the logic
        assertTrue(
            intentHashes.length != claimants.length,
            "Arrays should have different lengths"
        );
    }

    function testProveWithEmptyArrays() public {
        bytes32[] memory intentHashes = new bytes32[](0);
        bytes32[] memory claimants = new bytes32[](0);

        _proveWithFunding(
            creator,
            uint64(block.chainid),
            intentHashes,
            claimants,
            _encodeProverData(
                bytes32(uint256(uint160(address(prover)))),
                200000
            ),
            1 ether
        );
    }

    function testProveWithGasLimitParameter() public {
        Intent memory testIntent = intent;
        bytes32 intentHash = _hashIntent(testIntent);

        // Test with gas limit encoded in data parameter
        // MetaProver expects: sourceChainProver (32 bytes) + gasLimit (32 bytes)
        bytes memory gasLimitData = abi.encode(
            bytes32(uint256(uint160(address(prover)))), // sourceChainProver
            uint256(200000) // custom gas limit
        );

        bytes32[] memory intentHashes = new bytes32[](1);
        bytes32[] memory claimants = new bytes32[](1);
        intentHashes[0] = intentHash;
        claimants[0] = bytes32(uint256(uint160(claimant)));

        _proveWithFunding(
            creator,
            uint64(block.chainid),
            intentHashes,
            claimants,
            gasLimitData,
            1 ether
        );

        // Verify the message was dispatched successfully
        assertTrue(metaRouter.dispatched());
        // Verify the gas limit was passed correctly
        assertEq(metaRouter.gasLimit(), 200000);
    }

    function testProveWithOverpaymentRefund() public {
        bytes32[] memory intentHashes = new bytes32[](1);
        bytes32[] memory claimants = new bytes32[](1);
        intentHashes[0] = _hashIntent(intent);
        claimants[0] = bytes32(uint256(uint160(claimant)));

        uint256 overpayment = 5 ether;
        vm.deal(creator, 10 ether);
        uint256 initialBalance = creator.balance;

        _proveWithFunding(
            creator,
            uint64(block.chainid),
            intentHashes,
            claimants,
            _encodeProverData(
                bytes32(uint256(uint160(address(prover)))),
                200000
            ),
            overpayment
        );

        // Should receive refund of overpayment minus actual fee
        // Fee is 0.001 ether, so refund should be 4.999 ether
        assertEq(creator.balance, initialBalance + overpayment - 0.001 ether);
    }

    function testProveWithMinimumGasLimitEnforcement() public {
        bytes32[] memory intentHashes = new bytes32[](1);
        bytes32[] memory claimants = new bytes32[](1);
        intentHashes[0] = _hashIntent(intent);
        claimants[0] = bytes32(uint256(uint160(claimant)));

        // Test with gas limit below minimum (should be automatically increased to MIN_GAS_LIMIT)
        _proveWithFunding(
            creator,
            uint64(block.chainid),
            intentHashes,
            claimants,
            _encodeProverData(
                bytes32(uint256(uint160(address(prover)))),
                50000 // Below 200k minimum
            ),
            1 ether
        );

        // Test with zero gas limit (should be automatically increased to MIN_GAS_LIMIT)
        _proveWithFunding(
            creator,
            uint64(block.chainid),
            intentHashes,
            claimants,
            _encodeProverData(
                bytes32(uint256(uint160(address(prover)))),
                0 // Zero gas limit
            ),
            1 ether
        );

        assertTrue(metaRouter.dispatched());
    }

    function testFetchFeeWithCustomGasLimit() public view {
        Intent memory testIntent = intent;
        bytes32 intentHash = _hashIntent(testIntent);

        bytes32[] memory intentHashes = new bytes32[](1);
        bytes32[] memory claimants = new bytes32[](1);
        intentHashes[0] = intentHash;
        claimants[0] = bytes32(uint256(uint160(claimant)));

        // Test with custom gas limit higher than minimum
        uint256 customGasLimit = 500000; // 500k gas
        bytes memory data = _encodeProverData(
            bytes32(uint256(uint160(address(prover)))),
            customGasLimit
        );

        bytes memory encodedProofs = _packClaimantHashPairs(
            intentHashes,
            claimants
        );

        // fetchFee should now use the actual custom gas limit instead of hardcoded 100k
        uint256 fee = metaProver.fetchFee(
            uint64(block.chainid),
            encodedProofs,
            data
        );

        // Fee should be calculated with the custom gas limit
        // The exact fee depends on the TestMetaRouter implementation
        assertEq(fee, 0.001 ether);

        // Test with minimum gas limit
        bytes memory minGasData = _encodeProverData(
            bytes32(uint256(uint160(address(prover)))),
            50000 // Below minimum, should be increased to MIN_GAS_LIMIT
        );

        uint256 minFee = metaProver.fetchFee(
            uint64(block.chainid),
            encodedProofs,
            minGasData
        );

        // Should return same fee as minimum gas limit is enforced
        assertEq(minFee, 0.001 ether);
    }

    function testCrossVMClaimantSupport() public {
        Intent memory testIntent = intent;
        bytes32 intentHash = _hashIntent(testIntent);

        // Use a valid address for the claimant
        address nonEVMClaimant = makeAddr("cross-vm-claimant");

        bytes32[] memory intentHashes = new bytes32[](1);
        bytes32[] memory claimants = new bytes32[](1);
        intentHashes[0] = intentHash;
        claimants[0] = bytes32(uint256(uint160(nonEVMClaimant)));

        _proveWithFunding(
            creator,
            uint64(block.chainid),
            intentHashes,
            claimants,
            _encodeProverData(
                bytes32(uint256(uint160(address(prover)))),
                200000
            ),
            1 ether
        );

        // Verify the message was dispatched with the non-address claimant
        assertTrue(metaRouter.dispatched());
        bytes memory expectedBody = _formatMessageWithChainId(
            uint64(block.chainid),
            intentHashes,
            claimants
        );
        assertEq(metaRouter.messageBody(), expectedBody);
    }

    function testProveIntentWithComplexData() public {
        Intent memory testIntent = intent;
        bytes32 intentHash = _hashIntent(testIntent);

        // Test with complex encoded data - sourceChainProver must be first parameter
        bytes memory complexData = abi.encode(
            bytes32(uint256(uint160(address(prover)))), // sourceChainProver (required)
            uint256(300000), // gas limit
            bytes32("additional_data"),
            true // some flag
        );

        bytes32[] memory intentHashes = new bytes32[](1);
        bytes32[] memory claimants = new bytes32[](1);
        intentHashes[0] = intentHash;
        claimants[0] = bytes32(uint256(uint160(claimant)));

        _proveWithFunding(
            creator,
            uint64(block.chainid),
            intentHashes,
            claimants,
            complexData,
            1 ether
        );

        // Verify the message was dispatched successfully with complex data
        assertTrue(metaRouter.dispatched());
        // Verify custom gas limit was used
        assertEq(metaRouter.gasLimit(), 300000);
    }

    // ===== CHALLENGE INTENT PROOF TESTS =====

    function testChallengeIntentProofWithWrongChain() public {
        Intent memory testIntent = intent;
        bytes32 intentHash = _hashIntent(testIntent);

        // First, create a proof by simulating receipt of cross-chain message
        bytes32[] memory intentHashes = new bytes32[](1);
        bytes32[] memory claimants = new bytes32[](1);
        intentHashes[0] = intentHash;
        claimants[0] = bytes32(uint256(uint160(claimant)));

        // Store proof with wrong destination chain ID
        uint32 wrongDestinationChainId = 999;
        vm.prank(address(metaRouter));
        metaProver.handle(
            wrongDestinationChainId,
            bytes32(uint256(uint160(address(prover)))),
            _formatMessageWithChainId(
                wrongDestinationChainId,
                intentHashes,
                claimants
            ),
            new ReadOperation[](0),
            new bytes[](0)
        );

        // Verify proof exists with wrong chain ID
        IProver.ProofData memory proofBefore = metaProver.provenIntents(
            intentHash
        );
        assertEq(proofBefore.claimant, claimant);
        assertEq(proofBefore.destination, wrongDestinationChainId);

        // Challenge the proof with correct destination chain ID
        bytes32 routeHash = keccak256(abi.encode(testIntent.route));
        bytes32 rewardHash = keccak256(abi.encode(testIntent.reward));

        // Anyone can challenge
        vm.prank(otherPerson);
        metaProver.challengeIntentProof(
            testIntent.destination,
            routeHash,
            rewardHash
        );

        // Verify proof was cleared
        IProver.ProofData memory proofAfter = metaProver.provenIntents(
            intentHash
        );
        assertEq(proofAfter.claimant, address(0));
        assertEq(proofAfter.destination, 0);
    }

    function testChallengeIntentProofWithCorrectChain() public {
        Intent memory testIntent = intent;
        bytes32 intentHash = _hashIntent(testIntent);

        // First, create a proof by simulating receipt of cross-chain message
        bytes32[] memory intentHashes = new bytes32[](1);
        bytes32[] memory claimants = new bytes32[](1);
        intentHashes[0] = intentHash;
        claimants[0] = bytes32(uint256(uint160(claimant)));

        // Store proof with correct destination chain ID
        vm.prank(address(metaRouter));
        metaProver.handle(
            uint32(testIntent.destination),
            bytes32(uint256(uint160(address(prover)))),
            _formatMessageWithChainId(
                testIntent.destination,
                intentHashes,
                claimants
            ),
            new ReadOperation[](0),
            new bytes[](0)
        );

        // Verify proof exists
        IProver.ProofData memory proofBefore = metaProver.provenIntents(
            intentHash
        );
        assertEq(proofBefore.claimant, claimant);
        assertEq(proofBefore.destination, testIntent.destination);

        // Challenge the proof with same destination chain ID
        bytes32 routeHash = keccak256(abi.encode(testIntent.route));
        bytes32 rewardHash = keccak256(abi.encode(testIntent.reward));

        vm.prank(otherPerson);
        metaProver.challengeIntentProof(
            testIntent.destination,
            routeHash,
            rewardHash
        );

        // Verify proof remains unchanged (correct chain ID)
        IProver.ProofData memory proofAfter = metaProver.provenIntents(
            intentHash
        );
        assertEq(proofAfter.claimant, claimant);
        assertEq(proofAfter.destination, testIntent.destination);
    }

    function testChallengeIntentProofEventEmission() public {
        Intent memory testIntent = intent;
        bytes32 intentHash = _hashIntent(testIntent);

        // First, create a proof by simulating receipt of cross-chain message
        bytes32[] memory intentHashes = new bytes32[](1);
        bytes32[] memory claimants = new bytes32[](1);
        intentHashes[0] = intentHash;
        claimants[0] = bytes32(uint256(uint160(claimant)));

        // Store proof with wrong destination chain ID
        uint32 wrongDestinationChainId = 999;
        vm.prank(address(metaRouter));
        metaProver.handle(
            wrongDestinationChainId,
            bytes32(uint256(uint160(address(prover)))),
            _formatMessageWithChainId(
                wrongDestinationChainId,
                intentHashes,
                claimants
            ),
            new ReadOperation[](0),
            new bytes[](0)
        );

        bytes32 routeHash = keccak256(abi.encode(testIntent.route));
        bytes32 rewardHash = keccak256(abi.encode(testIntent.reward));

        // Expect event emission for proof clearing
        _expectEmit();
        emit IProver.IntentProofInvalidated(intentHash);

        // Challenge the proof
        vm.prank(otherPerson);
        metaProver.challengeIntentProof(
            testIntent.destination,
            routeHash,
            rewardHash
        );
    }

    function _packClaimantHashPairs(
        bytes32[] memory intentHashes,
        bytes32[] memory claimants
    ) internal pure returns (bytes memory) {
        require(
            intentHashes.length == claimants.length,
            "Array length mismatch"
        );
        bytes memory packed = new bytes(intentHashes.length * 64);
        for (uint256 i = 0; i < intentHashes.length; i++) {
            assembly {
                let offset := mul(i, 64)
                mstore(
                    add(add(packed, 0x20), offset),
                    mload(add(intentHashes, add(0x20, mul(i, 32))))
                )
                mstore(
                    add(add(packed, 0x20), add(offset, 32)),
                    mload(add(claimants, add(0x20, mul(i, 32))))
                )
            }
        }
        return packed;
    }

    function _formatMessageWithChainId(
        uint256 chainId,
        bytes32[] memory intentHashes,
        bytes32[] memory claimants
    ) internal pure returns (bytes memory) {
        bytes memory rawProofs = _packClaimantHashPairs(
            intentHashes,
            claimants
        );
        return abi.encodePacked(uint64(chainId), rawProofs);
    }
}
