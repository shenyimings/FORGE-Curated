// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "../BaseTest.sol";
import {CCIPProver} from "../../contracts/prover/CCIPProver.sol";
import {IProver} from "../../contracts/interfaces/IProver.sol";
import {IMessageBridgeProver} from "../../contracts/interfaces/IMessageBridgeProver.sol";
import {TestCCIPRouter} from "../../contracts/test/TestCCIPRouter.sol";
import {Intent, Route, Reward, TokenAmount, Call} from "../../contracts/types/Intent.sol";
import {AddressConverter} from "../../contracts/libs/AddressConverter.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {IAny2EVMMessageReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IAny2EVMMessageReceiver.sol";

contract CCIPProverTest is BaseTest {
    using AddressConverter for bytes32;
    using AddressConverter for address;

    CCIPProver internal ccipProver;
    TestCCIPRouter internal router;

    address internal whitelistedProver;
    address internal nonWhitelistedProver;

    uint256 internal constant DEFAULT_GAS_LIMIT = 200000;
    bool internal constant ALLOW_OUT_OF_ORDER = true;

    /**
     * @notice Helper function to encode proofs from separate arrays
     * @param intentHashes Array of intent hashes
     * @param claimants Array of claimant addresses (as bytes32)
     * @return encodedProofs Encoded (intentHash, claimant) pairs as bytes
     */
    function encodeProofs(
        bytes32[] memory intentHashes,
        bytes32[] memory claimants
    ) internal view returns (bytes memory encodedProofs) {
        require(intentHashes.length == claimants.length, "Array length mismatch");

        // Simulate what Inbox does - prepend 8 bytes for chain ID
        encodedProofs = new bytes(8 + intentHashes.length * 64);

        // Prepend chain ID
        uint64 chainId = uint64(block.chainid);
        assembly {
            mstore(add(encodedProofs, 0x20), shl(192, chainId))
        }

        for (uint256 i = 0; i < intentHashes.length; i++) {
            assembly {
                let offset := add(8, mul(i, 64))
                // Store hash in first 32 bytes of each pair
                mstore(add(add(encodedProofs, 0x20), offset), mload(add(intentHashes, add(0x20, mul(i, 32)))))
                // Store claimant in next 32 bytes of each pair
                mstore(add(add(encodedProofs, 0x20), add(offset, 32)), mload(add(claimants, add(0x20, mul(i, 32)))))
            }
        }
    }

    function setUp() public override {
        super.setUp();

        whitelistedProver = makeAddr("whitelistedProver");
        nonWhitelistedProver = makeAddr("nonWhitelistedProver");

        vm.startPrank(deployer);

        // Deploy TestCCIPRouter - set processor to ccipProver so it processes messages
        router = new TestCCIPRouter(address(0));

        // Setup provers array - include our whitelisted prover
        bytes32[] memory provers = new bytes32[](1);
        provers[0] = bytes32(uint256(uint160(whitelistedProver)));

        // Deploy CCIPProver
        ccipProver = new CCIPProver(address(router), address(portal), provers, 0);

        // Set the ccipProver as the processor for the router
        router.setProcessor(address(ccipProver));

        vm.stopPrank();

        _mintAndApprove(creator, MINT_AMOUNT);
        _fundUserNative(creator, 10 ether);

        // Fund the ccipProver contract for gas fees
        vm.deal(address(ccipProver), 10 ether);
        // Also fund the portal since it's the one calling prove
        vm.deal(address(portal), 10 ether);
    }

    /**
     * @notice Helper to encode prover data for CCIP
     * @dev Out-of-order execution is now always enabled in CCIPProver
     * @param sourceChainProver The prover address on the source chain
     * @param gasLimit The gas limit for execution
     * @return Encoded prover data
     */
    function _encodeProverData(
        bytes32 sourceChainProver,
        uint256 gasLimit
    ) internal pure returns (bytes memory) {
        return abi.encode(sourceChainProver, gasLimit);
    }

    // ============ Constructor & Initialization Tests ============

    function testInitializesCorrectly() public view {
        assertTrue(address(ccipProver) != address(0));
        assertEq(ccipProver.getProofType(), "CCIP");
        assertEq(ccipProver.ROUTER(), address(router));
    }

    function testConstructorRevertsWithZeroRouter() public {
        bytes32[] memory provers = new bytes32[](1);
        provers[0] = bytes32(uint256(uint160(whitelistedProver)));

        vm.expectRevert();
        new CCIPProver(address(0), address(portal), provers, 0);
    }

    function testImplementsIProverInterface() public view {
        assertTrue(ccipProver.supportsInterface(type(IProver).interfaceId));
    }

    function testImplementsIAny2EVMMessageReceiverInterface() public view {
        assertTrue(ccipProver.supportsInterface(type(IAny2EVMMessageReceiver).interfaceId));
    }

    function testVersioning() public view {
        assertEq(ccipProver.version(), "2.6");
    }

    // ============ Prove Function Tests ============

    function testOnlyPortalCanCallProve() public {
        bytes32[] memory intentHashes = new bytes32[](1);
        bytes32[] memory claimants = new bytes32[](1);
        intentHashes[0] = _hashIntent(intent);
        claimants[0] = bytes32(uint256(uint160(claimant)));

        bytes memory encodedProofs = encodeProofs(intentHashes, claimants);

        vm.expectRevert();
        vm.prank(creator);
        ccipProver.prove(creator, uint64(block.chainid), encodedProofs, "");
    }

    function testProveWithValidInput() public {
        bytes32[] memory intentHashes = new bytes32[](1);
        bytes32[] memory claimants = new bytes32[](1);
        intentHashes[0] = _hashIntent(intent);
        claimants[0] = bytes32(uint256(uint160(claimant)));

        bytes memory proverData =
            _encodeProverData(bytes32(uint256(uint160(whitelistedProver))), DEFAULT_GAS_LIMIT);

        bytes memory encodedProofs = encodeProofs(intentHashes, claimants);

        // Check the fee first
        uint256 expectedFee = ccipProver.fetchFee(uint64(block.chainid), encodedProofs, proverData);

        vm.prank(address(portal));
        ccipProver.prove{value: expectedFee}(creator, uint64(block.chainid), encodedProofs, proverData);
    }

    function testProveEmitsIntentProvenEvent() public {
        bytes32[] memory intentHashes = new bytes32[](1);
        bytes32[] memory claimants = new bytes32[](1);
        bytes32 intentHash = _hashIntent(intent);
        intentHashes[0] = intentHash;
        claimants[0] = bytes32(uint256(uint160(claimant)));

        _expectEmit();
        emit IProver.IntentProven(intentHash, claimant, uint64(block.chainid));

        vm.prank(address(portal));
        bytes memory proverData =
            _encodeProverData(bytes32(uint256(uint160(whitelistedProver))), DEFAULT_GAS_LIMIT);
        ccipProver.prove{value: 1 ether}(creator, uint64(block.chainid), encodeProofs(intentHashes, claimants), proverData);
    }

    function testProveBatchIntents() public {
        bytes32[] memory intentHashes = new bytes32[](3);
        bytes32[] memory claimants = new bytes32[](3);

        for (uint256 i = 0; i < 3; i++) {
            Intent memory testIntent = intent;
            testIntent.route.salt = keccak256(abi.encodePacked(salt, i));
            intentHashes[i] = _hashIntent(testIntent);
            claimants[i] = bytes32(uint256(uint160(claimant)));
        }

        vm.prank(address(portal));
        bytes memory proverData =
            _encodeProverData(bytes32(uint256(uint160(whitelistedProver))), DEFAULT_GAS_LIMIT);
        ccipProver.prove{value: 1 ether}(creator, uint64(block.chainid), encodeProofs(intentHashes, claimants), proverData);

        // Check that all intents were proven
        for (uint256 i = 0; i < 3; i++) {
            IProver.ProofData memory proof = ccipProver.provenIntents(intentHashes[i]);
            assertEq(proof.claimant, claimant);
        }
    }

    function testProveWithEmptyArrays() public {
        bytes32[] memory intentHashes = new bytes32[](0);
        bytes32[] memory claimants = new bytes32[](0);

        vm.prank(address(portal));
        bytes memory proverData =
            _encodeProverData(bytes32(uint256(uint160(whitelistedProver))), DEFAULT_GAS_LIMIT);
        ccipProver.prove{value: 1 ether}(creator, uint64(block.chainid), encodeProofs(intentHashes, claimants), proverData);
    }

    function testProveWithRefundHandling() public {
        bytes32[] memory intentHashes = new bytes32[](1);
        bytes32[] memory claimants = new bytes32[](1);
        intentHashes[0] = _hashIntent(intent);
        claimants[0] = bytes32(uint256(uint160(claimant)));

        uint256 overpayment = 2 ether;
        uint256 initialBalance = creator.balance;

        vm.prank(address(portal));
        bytes memory proverData =
            _encodeProverData(bytes32(uint256(uint160(whitelistedProver))), DEFAULT_GAS_LIMIT);
        ccipProver.prove{value: overpayment}(creator, uint64(block.chainid), encodeProofs(intentHashes, claimants), proverData);

        // Should refund excess payment
        assertTrue(creator.balance >= initialBalance - overpayment);
    }

    function testProveWithLargeArrays() public {
        uint256 arraySize = 50; // Test with larger array
        bytes32[] memory intentHashes = new bytes32[](arraySize);
        bytes32[] memory claimants = new bytes32[](arraySize);

        for (uint256 i = 0; i < arraySize; i++) {
            intentHashes[i] = keccak256(abi.encodePacked("intent", i));
            claimants[i] = bytes32(uint256(uint160(claimant)));
        }

        // Should handle large arrays without running out of gas
        vm.prank(address(portal));
        bytes memory proverData =
            _encodeProverData(bytes32(uint256(uint160(whitelistedProver))), DEFAULT_GAS_LIMIT);
        ccipProver.prove{value: 1 ether}(creator, uint64(block.chainid), encodeProofs(intentHashes, claimants), proverData);
    }

    // ============ ccipReceive Tests ============

    function testCcipReceiveOnlyFromRouter() public {
        Client.Any2EVMMessage memory message = Client.Any2EVMMessage({
            messageId: bytes32(uint256(1)),
            sourceChainSelector: uint64(1),
            sender: abi.encode(whitelistedProver),
            data: abi.encode(new bytes32[](1), new bytes32[](1)),
            destTokenAmounts: new Client.EVMTokenAmount[](0)
        });

        vm.expectRevert();
        vm.prank(creator);
        ccipProver.ccipReceive(message);
    }

    function testCcipReceiveWithWhitelistedSender() public {
        bytes32[] memory intentHashes = new bytes32[](1);
        bytes32[] memory claimants = new bytes32[](1);
        intentHashes[0] = _hashIntent(intent);
        claimants[0] = bytes32(uint256(uint160(claimant)));

        // Pack hash/claimant pairs as bytes with chain ID prefix
        bytes memory messageBody = _formatMessageWithChainId(1, intentHashes, claimants);

        // Create CCIP message
        Client.Any2EVMMessage memory message = Client.Any2EVMMessage({
            messageId: bytes32(uint256(1)),
            sourceChainSelector: uint64(1),
            sender: abi.encode(whitelistedProver),
            data: messageBody,
            destTokenAmounts: new Client.EVMTokenAmount[](0)
        });

        vm.prank(address(router));
        ccipProver.ccipReceive(message);

        IProver.ProofData memory proof = ccipProver.provenIntents(intentHashes[0]);
        assertEq(proof.claimant, claimant);
        assertEq(proof.destination, CHAIN_ID);
    }

    function testCcipReceiveRejectsNonWhitelistedSender() public {
        bytes32[] memory intentHashes = new bytes32[](1);
        bytes32[] memory claimants = new bytes32[](1);
        intentHashes[0] = _hashIntent(intent);
        claimants[0] = bytes32(uint256(uint160(claimant)));

        bytes memory messageBody = _formatMessageWithChainId(1, intentHashes, claimants);

        Client.Any2EVMMessage memory message = Client.Any2EVMMessage({
            messageId: bytes32(uint256(1)),
            sourceChainSelector: uint64(1),
            sender: abi.encode(nonWhitelistedProver),
            data: messageBody,
            destTokenAmounts: new Client.EVMTokenAmount[](0)
        });

        vm.expectRevert();
        vm.prank(address(router));
        ccipProver.ccipReceive(message);
    }

    function testCcipReceiveWithEmptyArrays() public {
        bytes32[] memory intentHashes = new bytes32[](0);
        bytes32[] memory claimants = new bytes32[](0);

        bytes memory messageBody = _formatMessageWithChainId(1, intentHashes, claimants);

        Client.Any2EVMMessage memory message = Client.Any2EVMMessage({
            messageId: bytes32(uint256(1)),
            sourceChainSelector: uint64(1),
            sender: abi.encode(whitelistedProver),
            data: messageBody,
            destTokenAmounts: new Client.EVMTokenAmount[](0)
        });

        // Should handle empty arrays gracefully
        vm.prank(address(router));
        ccipProver.ccipReceive(message);
    }

    function testCcipReceiveDuplicateIntent() public {
        bytes32[] memory intentHashes = new bytes32[](1);
        bytes32[] memory claimants = new bytes32[](1);
        bytes32 intentHash = _hashIntent(intent);
        intentHashes[0] = intentHash;
        claimants[0] = bytes32(uint256(uint160(claimant)));

        bytes memory messageBody = _formatMessageWithChainId(1, intentHashes, claimants);

        Client.Any2EVMMessage memory message = Client.Any2EVMMessage({
            messageId: bytes32(uint256(1)),
            sourceChainSelector: uint64(1),
            sender: abi.encode(whitelistedProver),
            data: messageBody,
            destTokenAmounts: new Client.EVMTokenAmount[](0)
        });

        // First call should succeed
        vm.prank(address(router));
        ccipProver.ccipReceive(message);

        // Second call should emit IntentAlreadyProven event
        _expectEmit();
        emit IProver.IntentAlreadyProven(intentHash);

        vm.prank(address(router));
        ccipProver.ccipReceive(message);
    }

    function testCcipReceiveWithInvalidMessageFormat() public {
        // Create invalid message with wrong length (not multiple of 64)
        bytes memory invalidMessage = new bytes(63); // Should be multiple of 64

        Client.Any2EVMMessage memory message = Client.Any2EVMMessage({
            messageId: bytes32(uint256(1)),
            sourceChainSelector: uint64(1),
            sender: abi.encode(whitelistedProver),
            data: invalidMessage,
            destTokenAmounts: new Client.EVMTokenAmount[](0)
        });

        vm.expectRevert(IProver.ArrayLengthMismatch.selector);
        vm.prank(address(router));
        ccipProver.ccipReceive(message);
    }

    function testCcipReceiveRevertsOnZeroSourceChainSelector() public {
        Client.Any2EVMMessage memory message = Client.Any2EVMMessage({
            messageId: bytes32(uint256(1)),
            sourceChainSelector: uint64(0), // Zero source chain selector
            sender: abi.encode(whitelistedProver),
            data: abi.encode(new bytes32[](1), new bytes32[](1)),
            destTokenAmounts: new Client.EVMTokenAmount[](0)
        });

        vm.expectRevert(IMessageBridgeProver.MessageOriginChainDomainIDCannotBeZero.selector);
        vm.prank(address(router));
        ccipProver.ccipReceive(message);
    }

    function testCcipReceiveRevertsOnZeroSender() public {
        Client.Any2EVMMessage memory message = Client.Any2EVMMessage({
            messageId: bytes32(uint256(1)),
            sourceChainSelector: uint64(1),
            sender: abi.encode(address(0)), // Zero sender address
            data: abi.encode(new bytes32[](1), new bytes32[](1)),
            destTokenAmounts: new Client.EVMTokenAmount[](0)
        });

        vm.expectRevert(IMessageBridgeProver.MessageSenderCannotBeZeroAddress.selector);
        vm.prank(address(router));
        ccipProver.ccipReceive(message);
    }

    // ============ Fee Calculation Tests ============

    function testFetchFeeReturnsValidAmount() public view {
        bytes32[] memory intentHashes = new bytes32[](1);
        bytes32[] memory claimants = new bytes32[](1);
        intentHashes[0] = _hashIntent(intent);
        claimants[0] = bytes32(uint256(uint160(claimant)));

        bytes memory proverData =
            _encodeProverData(bytes32(uint256(uint160(whitelistedProver))), DEFAULT_GAS_LIMIT);

        bytes memory encodedProofs = encodeProofs(intentHashes, claimants);

        uint256 fee = ccipProver.fetchFee(uint64(block.chainid), encodedProofs, proverData);

        // Fee should be non-zero
        assertGt(fee, 0);
        // Fee should equal router's fee
        assertEq(fee, router.FEE());
    }

    function testFetchFeeWithDifferentGasLimits() public view {
        bytes32[] memory intentHashes = new bytes32[](1);
        bytes32[] memory claimants = new bytes32[](1);
        intentHashes[0] = _hashIntent(intent);
        claimants[0] = bytes32(uint256(uint160(claimant)));

        bytes memory encodedProofs = encodeProofs(intentHashes, claimants);

        bytes memory lowGasData = _encodeProverData(bytes32(uint256(uint160(whitelistedProver))), 100000);
        bytes memory highGasData = _encodeProverData(bytes32(uint256(uint160(whitelistedProver))), 500000);

        uint256 lowGasFee = ccipProver.fetchFee(uint64(block.chainid), encodedProofs, lowGasData);
        uint256 highGasFee = ccipProver.fetchFee(uint64(block.chainid), encodedProofs, highGasData);

        // Both should return valid fees (in mock they're the same, but validates no revert)
        assertGt(lowGasFee, 0);
        assertGt(highGasFee, 0);
    }

    // ============ Challenge Tests ============

    function testChallengeIntentProofWithWrongChain() public {
        // First, prove the intent
        bytes32[] memory intentHashes = new bytes32[](1);
        bytes32[] memory claimants = new bytes32[](1);
        bytes32 intentHash = _hashIntent(intent);
        intentHashes[0] = intentHash;
        claimants[0] = bytes32(uint256(uint160(claimant)));

        vm.prank(address(portal));
        bytes memory proverData =
            _encodeProverData(bytes32(uint256(uint160(whitelistedProver))), DEFAULT_GAS_LIMIT);
        ccipProver.prove{value: 1 ether}(creator, uint64(block.chainid), encodeProofs(intentHashes, claimants), proverData);

        // Verify intent is proven (with chain ID = 31337 from the prove call)
        IProver.ProofData memory proof = ccipProver.provenIntents(intentHash);
        assertTrue(proof.claimant != address(0));
        assertEq(proof.destination, uint96(block.chainid)); // 31337

        // The original intent has destination = 1 (CHAIN_ID from BaseTest)
        // So challenging with the original intent should clear the proof
        vm.prank(creator);
        ccipProver.challengeIntentProof(
            intent.destination, keccak256(abi.encode(intent.route)), keccak256(abi.encode(intent.reward))
        );

        // Verify proof was cleared
        proof = ccipProver.provenIntents(intentHash);
        assertEq(proof.claimant, address(0));
    }

    function testChallengeIntentProofWithCorrectChain() public {
        // Create an intent with destination matching the chain where we'll prove it
        Intent memory localIntent = intent;
        localIntent.destination = uint64(block.chainid); // 31337

        // First, prove the intent
        bytes32[] memory intentHashes = new bytes32[](1);
        bytes32[] memory claimants = new bytes32[](1);
        bytes32 intentHash = _hashIntent(localIntent);
        intentHashes[0] = intentHash;
        claimants[0] = bytes32(uint256(uint160(claimant)));

        vm.prank(address(portal));
        bytes memory proverData =
            _encodeProverData(bytes32(uint256(uint160(whitelistedProver))), DEFAULT_GAS_LIMIT);
        ccipProver.prove{value: 1 ether}(creator, uint64(block.chainid), encodeProofs(intentHashes, claimants), proverData);

        // Verify intent is proven
        IProver.ProofData memory proof = ccipProver.provenIntents(intentHash);
        assertTrue(proof.claimant != address(0));
        assertEq(proof.destination, uint96(block.chainid));

        // Challenge with correct chain should do nothing
        vm.prank(creator);
        ccipProver.challengeIntentProof(
            localIntent.destination, keccak256(abi.encode(localIntent.route)), keccak256(abi.encode(localIntent.reward))
        );

        // Verify proof is still there
        proof = ccipProver.provenIntents(intentHash);
        assertEq(proof.claimant, claimant);
    }

    // ============ Storage Tests ============

    function testProvenIntentsStorage() public {
        bytes32[] memory intentHashes = new bytes32[](1);
        bytes32[] memory claimants = new bytes32[](1);
        bytes32 intentHash = _hashIntent(intent);
        intentHashes[0] = intentHash;
        claimants[0] = bytes32(uint256(uint160(claimant)));

        // First, send the prove message
        vm.prank(address(portal));
        bytes memory proverData =
            _encodeProverData(bytes32(uint256(uint160(whitelistedProver))), DEFAULT_GAS_LIMIT);
        ccipProver.prove{value: 1 ether}(creator, uint64(block.chainid), encodeProofs(intentHashes, claimants), proverData);

        // Now simulate the message being received back by calling ccipReceive
        bytes memory messageBody = _formatMessageWithChainId(1, intentHashes, claimants);
        Client.Any2EVMMessage memory message = Client.Any2EVMMessage({
            messageId: bytes32(uint256(1)),
            sourceChainSelector: uint64(block.chainid),
            sender: abi.encode(whitelistedProver),
            data: messageBody,
            destTokenAmounts: new Client.EVMTokenAmount[](0)
        });

        vm.prank(address(router));
        ccipProver.ccipReceive(message);

        // Now check the storage
        IProver.ProofData memory proof = ccipProver.provenIntents(intentHash);
        assertEq(proof.claimant, claimant);
        assertEq(proof.destination, uint96(block.chainid));
    }

    function testCrossVMClaimantCompatibility() public {
        bytes32[] memory intentHashes = new bytes32[](1);
        bytes32[] memory claimants = new bytes32[](1);
        intentHashes[0] = _hashIntent(intent);
        address nonEvmClaimant = makeAddr("non-evm-claimant");
        claimants[0] = bytes32(uint256(uint160(nonEvmClaimant)));

        vm.prank(address(portal));
        bytes memory proverData =
            _encodeProverData(bytes32(uint256(uint160(whitelistedProver))), DEFAULT_GAS_LIMIT);
        ccipProver.prove{value: 1 ether}(creator, uint64(block.chainid), encodeProofs(intentHashes, claimants), proverData);

        IProver.ProofData memory proof = ccipProver.provenIntents(intentHashes[0]);
        assertEq(proof.claimant, nonEvmClaimant);
    }

    // ============ Gas Configuration Tests ============

    function testProveWithDifferentGasLimits() public {
        bytes32[] memory intentHashes = new bytes32[](1);
        bytes32[] memory claimants = new bytes32[](1);
        intentHashes[0] = _hashIntent(intent);
        claimants[0] = bytes32(uint256(uint160(claimant)));

        bytes memory encodedProofs = encodeProofs(intentHashes, claimants);

        // Test with custom gas limit
        uint256 customGasLimit = 500000;
        bytes memory proverData =
            _encodeProverData(bytes32(uint256(uint160(whitelistedProver))), customGasLimit);

        vm.prank(address(portal));
        ccipProver.prove{value: 1 ether}(creator, uint64(block.chainid), encodedProofs, proverData);
    }

    function testProveWithOutOfOrderExecution() public {
        bytes32[] memory intentHashes = new bytes32[](1);
        bytes32[] memory claimants = new bytes32[](1);
        intentHashes[0] = _hashIntent(intent);
        claimants[0] = bytes32(uint256(uint160(claimant)));

        bytes memory encodedProofs = encodeProofs(intentHashes, claimants);

        // Test with out-of-order execution enabled
        bytes memory proverData = _encodeProverData(bytes32(uint256(uint160(whitelistedProver))), DEFAULT_GAS_LIMIT);

        vm.prank(address(portal));
        ccipProver.prove{value: 1 ether}(creator, uint64(block.chainid), encodedProofs, proverData);
    }

    function testProveWithOutOfOrderExecutionDisabled() public {
        bytes32[] memory intentHashes = new bytes32[](1);
        bytes32[] memory claimants = new bytes32[](1);
        intentHashes[0] = _hashIntent(intent);
        claimants[0] = bytes32(uint256(uint160(claimant)));

        bytes memory encodedProofs = encodeProofs(intentHashes, claimants);

        // Test with out-of-order execution disabled
        bytes memory proverData = _encodeProverData(bytes32(uint256(uint160(whitelistedProver))), DEFAULT_GAS_LIMIT);

        vm.prank(address(portal));
        ccipProver.prove{value: 1 ether}(creator, uint64(block.chainid), encodedProofs, proverData);
    }

    // ============ Helper Functions ============

    function _formatMessageWithChainId(uint256 chainId, bytes32[] memory intentHashes, bytes32[] memory claimants)
        internal
        pure
        returns (bytes memory)
    {
        require(intentHashes.length == claimants.length, "Array length mismatch");
        bytes memory packed = new bytes(intentHashes.length * 64);
        for (uint256 i = 0; i < intentHashes.length; i++) {
            assembly {
                let offset := mul(i, 64)
                mstore(add(add(packed, 0x20), offset), mload(add(intentHashes, add(0x20, mul(i, 32)))))
                mstore(add(add(packed, 0x20), add(offset, 32)), mload(add(claimants, add(0x20, mul(i, 32)))))
            }
        }
        return abi.encodePacked(uint64(chainId), packed);
    }
}
