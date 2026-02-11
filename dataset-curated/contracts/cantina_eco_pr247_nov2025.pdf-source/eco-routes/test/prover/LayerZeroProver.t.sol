// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseTest} from "../BaseTest.sol";
import {LayerZeroProver} from "../../contracts/prover/LayerZeroProver.sol";
import {ILayerZeroEndpointV2} from "../../contracts/interfaces/layerzero/ILayerZeroEndpointV2.sol";
import {ILayerZeroReceiver} from "../../contracts/interfaces/layerzero/ILayerZeroReceiver.sol";
import {Portal} from "../../contracts/Portal.sol";
import {IProver} from "../../contracts/interfaces/IProver.sol";

contract MockLayerZeroEndpoint {
    mapping(uint32 => mapping(bytes32 => address)) public delegates;

    function send(
        ILayerZeroEndpointV2.MessagingParams calldata params,
        address /* refundAddress */
    ) external payable returns (ILayerZeroEndpointV2.MessagingReceipt memory) {
        return
            ILayerZeroEndpointV2.MessagingReceipt({
                guid: keccak256(abi.encode(params, block.timestamp)),
                nonce: 1,
                fee: ILayerZeroEndpointV2.MessagingFee({
                    nativeFee: msg.value,
                    lzTokenFee: 0
                })
            });
    }

    function quote(
        ILayerZeroEndpointV2.MessagingParams calldata,
        address
    ) external pure returns (ILayerZeroEndpointV2.MessagingFee memory) {
        return
            ILayerZeroEndpointV2.MessagingFee({
                nativeFee: 0.001 ether,
                lzTokenFee: 0
            });
    }

    function setDelegate(address delegate) external {
        delegates[uint32(block.chainid)][
            bytes32(uint256(uint160(msg.sender)))
        ] = delegate;
    }
}

contract LayerZeroProverTest is BaseTest {
    LayerZeroProver public lzProver;
    MockLayerZeroEndpoint public endpoint;

    uint256 constant SOURCE_CHAIN_ID = 10;
    uint256 constant DEST_CHAIN_ID = 1;
    bytes32 constant SOURCE_PROVER =
        bytes32(uint256(uint160(0x1234567890123456789012345678901234567890)));

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
        require(
            intentHashes.length == claimants.length,
            "Array length mismatch"
        );

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
                mstore(
                    add(add(encodedProofs, 0x20), offset),
                    mload(add(intentHashes, add(0x20, mul(i, 32))))
                )
                // Store claimant in next 32 bytes of each pair
                mstore(
                    add(add(encodedProofs, 0x20), add(offset, 32)),
                    mload(add(claimants, add(0x20, mul(i, 32))))
                )
            }
        }
    }

    function setUp() public override {
        super.setUp();

        endpoint = new MockLayerZeroEndpoint();

        bytes32[] memory trustedProvers = new bytes32[](1);
        trustedProvers[0] = SOURCE_PROVER;

        lzProver = new LayerZeroProver(
            address(endpoint),
            address(this), // delegate
            address(portal),
            trustedProvers,
            200000
        );
    }

    function _encodeProverData(
        bytes32 sourceChainProver,
        bytes memory options,
        uint256 gasLimit
    ) internal pure returns (bytes memory) {
        LayerZeroProver.UnpackedData memory unpacked = LayerZeroProver
            .UnpackedData({
                sourceChainProver: sourceChainProver,
                options: options,
                gasLimit: gasLimit
            });

        return abi.encode(unpacked);
    }

    function test_constructor() public view {
        assertEq(lzProver.ENDPOINT(), address(endpoint));
        assertEq(lzProver.PORTAL(), address(portal));
        assertTrue(lzProver.isWhitelisted(SOURCE_PROVER));
        assertEq(lzProver.MIN_GAS_LIMIT(), 200000);
    }

    function test_getProofType() public view {
        assertEq(lzProver.getProofType(), "LayerZero");
    }

    function test_fetchFee() public view {
        bytes32[] memory intentHashes = new bytes32[](1);
        intentHashes[0] = keccak256("intent");

        bytes32[] memory claimants = new bytes32[](1);
        claimants[0] = bytes32(uint256(uint160(address(this))));

        bytes memory data = _encodeProverData(SOURCE_PROVER, "", 200000);

        bytes memory encodedProofs = encodeProofs(intentHashes, claimants);
        uint256 fee = lzProver.fetchFee(
            uint64(SOURCE_CHAIN_ID),
            encodedProofs,
            data
        );
        assertEq(fee, 0.001 ether);
    }

    function test_prove() public {
        bytes32[] memory intentHashes = new bytes32[](1);
        intentHashes[0] = keccak256("intent");

        bytes32[] memory claimants = new bytes32[](1);
        claimants[0] = bytes32(uint256(uint160(address(this))));

        bytes memory data = _encodeProverData(SOURCE_PROVER, "", 200000);

        bytes memory encodedProofs = encodeProofs(intentHashes, claimants);
        uint256 fee = lzProver.fetchFee(
            uint64(SOURCE_CHAIN_ID),
            encodedProofs,
            data
        );

        vm.deal(address(portal), fee);
        vm.prank(address(portal));
        lzProver.prove{value: fee}(
            address(portal),
            uint64(SOURCE_CHAIN_ID),
            encodedProofs,
            data
        );
    }

    function test_lzReceive() public {
        bytes32[] memory intentHashes = new bytes32[](1);
        intentHashes[0] = keccak256("intent");

        bytes32[] memory claimants = new bytes32[](1);
        claimants[0] = bytes32(uint256(uint160(address(this))));

        ILayerZeroReceiver.Origin memory origin = ILayerZeroReceiver.Origin({
            srcEid: uint32(SOURCE_CHAIN_ID),
            sender: SOURCE_PROVER,
            nonce: 1
        });

        // Pack hash/claimant pairs as bytes with chain ID prefix
        bytes memory message = _formatMessageWithChainId(
            SOURCE_CHAIN_ID,
            intentHashes,
            claimants
        );

        vm.prank(address(endpoint));
        lzProver.lzReceive(origin, bytes32(0), message, address(0), "");

        LayerZeroProver.ProofData memory proofData = lzProver.provenIntents(
            intentHashes[0]
        );
        assertEq(proofData.claimant, address(this));
        assertEq(proofData.destination, SOURCE_CHAIN_ID);
    }

    function test_allowInitializePath() public view {
        ILayerZeroReceiver.Origin memory origin = ILayerZeroReceiver.Origin({
            srcEid: uint32(SOURCE_CHAIN_ID),
            sender: SOURCE_PROVER,
            nonce: 1
        });

        assertTrue(lzProver.allowInitializePath(origin));

        origin.sender = bytes32(uint256(uint160(address(0x9999))));
        assertFalse(lzProver.allowInitializePath(origin));
    }

    function test_constructor_revertEndpointZero() public {
        bytes32[] memory trustedProvers = new bytes32[](1);
        trustedProvers[0] = SOURCE_PROVER;

        vm.expectRevert(LayerZeroProver.EndpointCannotBeZeroAddress.selector);
        new LayerZeroProver(
            address(0),
            address(this), // delegate
            address(portal),
            trustedProvers,
            200000
        );
    }

    function test_lzReceive_revertInvalidSender() public {
        ILayerZeroReceiver.Origin memory origin = ILayerZeroReceiver.Origin({
            srcEid: uint32(SOURCE_CHAIN_ID),
            sender: SOURCE_PROVER,
            nonce: 1
        });

        vm.expectRevert();
        lzProver.lzReceive(origin, bytes32(0), "", address(0), "");
    }

    function test_prove_withCustomGasLimit() public {
        bytes32[] memory intentHashes = new bytes32[](1);
        intentHashes[0] = keccak256("intent");

        bytes32[] memory claimants = new bytes32[](1);
        claimants[0] = bytes32(uint256(uint160(address(this))));

        uint256 customGasLimit = 300000;
        bytes memory data = _encodeProverData(
            SOURCE_PROVER,
            "",
            customGasLimit
        );

        bytes memory encodedProofs = encodeProofs(intentHashes, claimants);
        uint256 fee = lzProver.fetchFee(
            uint64(SOURCE_CHAIN_ID),
            encodedProofs,
            data
        );

        vm.deal(address(portal), fee);
        vm.prank(address(portal));
        lzProver.prove{value: fee}(
            address(portal),
            uint64(SOURCE_CHAIN_ID),
            encodedProofs,
            data
        );
    }

    function test_prove_enforcesMinimumGasLimit() public {
        bytes32[] memory intentHashes = new bytes32[](1);
        intentHashes[0] = keccak256("intent");

        bytes32[] memory claimants = new bytes32[](1);
        claimants[0] = bytes32(uint256(uint160(address(this))));

        // Test with gas limit below minimum (should be automatically increased to MIN_GAS_LIMIT)
        uint256 belowMinGasLimit = 50000; // Below 200k minimum
        bytes memory data = _encodeProverData(
            SOURCE_PROVER,
            "",
            belowMinGasLimit
        );

        bytes memory encodedProofs = encodeProofs(intentHashes, claimants);
        uint256 fee = lzProver.fetchFee(
            uint64(SOURCE_CHAIN_ID),
            encodedProofs,
            data
        );

        vm.deal(address(portal), fee);
        vm.prank(address(portal));
        lzProver.prove{value: fee}(
            address(portal),
            uint64(SOURCE_CHAIN_ID),
            encodedProofs,
            data
        );

        // Test with zero gas limit (should be automatically increased to MIN_GAS_LIMIT)
        bytes memory zeroGasData = _encodeProverData(SOURCE_PROVER, "", 0);

        uint256 zeroGasFee = lzProver.fetchFee(
            uint64(SOURCE_CHAIN_ID),
            encodedProofs,
            zeroGasData
        );

        vm.deal(address(portal), zeroGasFee);
        vm.prank(address(portal));
        lzProver.prove{value: zeroGasFee}(
            address(portal),
            uint64(SOURCE_CHAIN_ID),
            encodedProofs,
            zeroGasData
        );
    }

    // ============ Challenge Intent Proof Tests ============
    // Note: Comprehensive challenge tests are in MetaProver.t.sol
    // Keeping only LayerZero-specific challenge test

    function testChallengeIntentProofWithWrongChain() public {
        // Create test data
        uint64 actualDestination = 1;
        uint64 wrongDestination = 2;
        bytes32 routeHash = keccak256("route");
        bytes32 rewardHash = keccak256("reward");
        bytes32 intentHash = keccak256(
            abi.encodePacked(actualDestination, routeHash, rewardHash)
        );

        // Setup a proof with wrong destination chain
        bytes32[] memory intentHashes = new bytes32[](1);
        intentHashes[0] = intentHash;

        bytes32[] memory claimants = new bytes32[](1);
        claimants[0] = bytes32(uint256(uint160(address(this))));

        ILayerZeroReceiver.Origin memory origin = ILayerZeroReceiver.Origin({
            srcEid: uint32(wrongDestination), // Wrong destination
            sender: SOURCE_PROVER,
            nonce: 1
        });

        // Pack hash/claimant pairs as bytes with chain ID prefix
        bytes memory message = _formatMessageWithChainId(
            wrongDestination,
            intentHashes,
            claimants
        );

        // Add the proof with wrong destination
        vm.prank(address(endpoint));
        lzProver.lzReceive(origin, bytes32(0), message, address(0), "");

        // Verify proof exists with wrong destination
        LayerZeroProver.ProofData memory proofBefore = lzProver.provenIntents(
            intentHash
        );
        assertEq(proofBefore.claimant, address(this));
        assertEq(proofBefore.destination, wrongDestination);

        // Challenge the proof with correct destination
        vm.expectEmit(true, true, true, true);
        emit IProver.IntentProofInvalidated(intentHash);

        lzProver.challengeIntentProof(actualDestination, routeHash, rewardHash);

        // Verify proof was cleared
        LayerZeroProver.ProofData memory proofAfter = lzProver.provenIntents(
            intentHash
        );
        assertEq(proofAfter.claimant, address(0));
        assertEq(proofAfter.destination, 0);
    }

    // ============================================================================
    // LayerZero-Specific Challenge Tests
    // ============================================================================

    function testChallengeIntentProofWithCorrectChain() public {
        // Create test data
        uint64 correctDestination = 1;
        bytes32 routeHash = keccak256("route");
        bytes32 rewardHash = keccak256("reward");
        bytes32 intentHash = keccak256(
            abi.encodePacked(correctDestination, routeHash, rewardHash)
        );

        // Setup a proof with correct destination chain
        bytes32[] memory intentHashes = new bytes32[](1);
        intentHashes[0] = intentHash;

        bytes32[] memory claimants = new bytes32[](1);
        claimants[0] = bytes32(uint256(uint160(address(this))));

        ILayerZeroReceiver.Origin memory origin = ILayerZeroReceiver.Origin({
            srcEid: uint32(correctDestination), // Correct destination
            sender: SOURCE_PROVER,
            nonce: 1
        });

        // Pack hash/claimant pairs as bytes with chain ID prefix
        bytes memory message = _formatMessageWithChainId(
            correctDestination,
            intentHashes,
            claimants
        );

        // Add the proof with correct destination
        vm.prank(address(endpoint));
        lzProver.lzReceive(origin, bytes32(0), message, address(0), "");

        // Verify proof exists with correct destination
        LayerZeroProver.ProofData memory proofBefore = lzProver.provenIntents(
            intentHash
        );
        assertEq(proofBefore.claimant, address(this));
        assertEq(proofBefore.destination, correctDestination);

        // Challenge the proof with correct destination (should do nothing)
        lzProver.challengeIntentProof(
            correctDestination,
            routeHash,
            rewardHash
        );

        // Verify proof still exists
        LayerZeroProver.ProofData memory proofAfter = lzProver.provenIntents(
            intentHash
        );
        assertEq(proofAfter.claimant, address(this));
        assertEq(proofAfter.destination, correctDestination);
    }

    function testChallengeIntentProofLayerZeroSpecific() public {
        // Test LayerZero-specific edge cases
        uint64 actualDestination = 1;
        uint64 wrongDestination = 2;
        bytes32 routeHash = keccak256("route");
        bytes32 rewardHash = keccak256("reward");
        bytes32 intentHash = keccak256(
            abi.encodePacked(actualDestination, routeHash, rewardHash)
        );

        // Test with invalid srcEid
        bytes32[] memory intentHashes = new bytes32[](1);
        intentHashes[0] = intentHash;
        bytes32[] memory claimants = new bytes32[](1);
        claimants[0] = bytes32(uint256(uint160(address(this))));

        ILayerZeroReceiver.Origin memory origin = ILayerZeroReceiver.Origin({
            srcEid: uint32(wrongDestination), // Wrong destination
            sender: SOURCE_PROVER,
            nonce: 1
        });

        // Pack hash/claimant pairs as bytes with chain ID prefix
        bytes memory message = _formatMessageWithChainId(
            wrongDestination,
            intentHashes,
            claimants
        );

        // Add proof with wrong srcEid
        vm.prank(address(endpoint));
        lzProver.lzReceive(origin, bytes32(0), message, address(0), "");

        // Challenge should succeed for LayerZero-specific validation
        vm.expectEmit(true, true, true, true);
        emit IProver.IntentProofInvalidated(intentHash);

        lzProver.challengeIntentProof(actualDestination, routeHash, rewardHash);

        // Verify proof was cleared
        LayerZeroProver.ProofData memory proofAfter = lzProver.provenIntents(
            intentHash
        );
        assertEq(proofAfter.claimant, address(0));
        assertEq(proofAfter.destination, 0);
    }

    // Helper to import the event for testing
    event IntentProven(
        bytes32 indexed intentHash,
        address indexed claimant,
        uint64 destination
    );

    function _formatMessageWithChainId(
        uint256 chainId,
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
        return abi.encodePacked(uint64(chainId), packed);
    }
}
