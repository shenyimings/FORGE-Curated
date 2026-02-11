// SPDX-LICENSE-Identifier: UNLICENSED

pragma solidity ^0.8.22;

import { Test } from "forge-std/Test.sol";
import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import { OneSig } from "../../contracts/OneSig.sol";

contract OneSigTest is Test, OneSig {
    using EnumerableSet for EnumerableSet.AddressSet;

    bytes32 public constant SEED = bytes32(uint256(12345678));

    // Executor addresses for testing
    address public executor1;
    address public executor2;

    // Signer addresses for testing
    address public signer1;
    address public signer2;

    // Address for testing non-executor, non-signer access
    address public nonAuthorized;

    constructor() OneSig(uint64(block.chainid), _getSigners(), 2, _getExecutors(), true, SEED) {}

    function setUp() public {
        // Setup test addresses
        executor1 = vm.addr(2);
        executor2 = vm.addr(3);
        signer1 = vm.addr(4);
        signer2 = vm.addr(5);
        nonAuthorized = vm.addr(6);
    }

    function _getExecutors() internal pure returns (address[] memory) {
        address[] memory executors = new address[](2);
        executors[0] = vm.addr(2);
        executors[1] = vm.addr(3);
        return executors;
    }

    function _getSigners() internal pure returns (address[] memory) {
        address[] memory signers = new address[](2);
        signers[0] = vm.addr(4);
        signers[1] = vm.addr(5);
        return signers;
    }

    function test_setSeed() public {
        assertEq(seed, SEED);
        bytes32 newSeed = bytes32(uint256(87654321));
        vm.expectEmit();
        emit SeedSet(newSeed);
        this.setSeed(newSeed);
        assertEq(seed, newSeed);

        // fail to set by non-self
        vm.expectRevert();
        vm.prank(address(1));
        this.setSeed(newSeed);
    }

    /* ========== EXECUTOR FUNCTIONALITY TESTS ========== */

    function test_initialExecutorSetup() public {
        // Verify initial executors are set correctly
        assertTrue(isExecutor(executor1));
        assertTrue(isExecutor(executor2));
        assertFalse(isExecutor(nonAuthorized));
    }

    function test_setExecutor_addNew() public {
        address newExecutor = vm.addr(7);

        // Verify new executor is not initially active
        assertFalse(isExecutor(newExecutor));

        // Prepare expected event
        vm.expectEmit();
        emit ExecutorSet(newExecutor, true);

        // Add new executor through multisig (contract itself)
        this.setExecutor(newExecutor, true);

        // Verify executor was added
        assertTrue(isExecutor(newExecutor));
    }

    function test_setExecutor_remove() public {
        // Verify executor1 is initially active
        assertTrue(isExecutor(executor1));

        // Prepare expected event
        vm.expectEmit();
        emit ExecutorSet(executor1, false);

        // Remove executor through multisig (contract itself)
        this.setExecutor(executor1, false);

        // Verify executor was removed
        assertFalse(isExecutor(executor1));
    }

    function test_setExecutor_onlySelfCall() public {
        address newExecutor = vm.addr(7);

        // Attempt to add executor as a non-multisig call
        vm.prank(executor1);
        vm.expectRevert(OnlySelfCall.selector);
        this.setExecutor(newExecutor, true);
    }

    function test_setExecutor_alreadyActive() public {
        // Attempt to add executor1 which is already active
        vm.expectRevert(abi.encodeWithSelector(ExecutorAlreadyActive.selector, executor1));
        this.setExecutor(executor1, true);
    }

    function test_setExecutor_alreadyInactive() public {
        address newExecutor = vm.addr(7);

        // Attempt to remove executor that is already inactive
        vm.expectRevert(abi.encodeWithSelector(ExecutorNotFound.selector, newExecutor));
        this.setExecutor(newExecutor, false);
    }

    function test_executeTransaction_onlyExecutorOrSigner() public {
        // Create dummy transaction components for the test
        OneSig.Call[] memory calls = new OneSig.Call[](0);
        bytes32[] memory proof = new bytes32[](0);
        OneSig.Transaction memory transaction = OneSig.Transaction({ calls: calls, proof: proof });
        bytes32 merkleRoot = bytes32(uint256(1));
        uint256 expiry = block.timestamp + 3600;
        bytes memory signatures = new bytes(0);

        // Test as non-authorized address
        vm.prank(nonAuthorized);
        vm.expectRevert(OnlyExecutorOrSigner.selector);
        this.executeTransaction(transaction, merkleRoot, expiry, signatures);

        // Test as executor - should pass the permission check but fail on merkle proof
        vm.prank(executor1);
        vm.expectRevert(SignatureError.selector);
        this.executeTransaction(transaction, merkleRoot, expiry, signatures);

        // Test as signer - should pass the permission check but fail on merkle proof
        vm.prank(signer1);
        vm.expectRevert(SignatureError.selector);
        this.executeTransaction(transaction, merkleRoot, expiry, signatures);
    }

    function test_executeTransaction_merkleRootExpired() public {
        // Create dummy transaction components for the test
        OneSig.Call[] memory calls = new OneSig.Call[](0);
        bytes32[] memory proof = new bytes32[](0);
        OneSig.Transaction memory transaction = OneSig.Transaction({ calls: calls, proof: proof });
        bytes32 merkleRoot = bytes32(uint256(1));

        // Set expiry in the past
        uint256 expiry = block.timestamp - 1;
        bytes memory signatures = new bytes(0);

        // Test as executor - should fail due to expired merkle root
        vm.prank(executor1);
        vm.expectRevert(MerkleRootExpired.selector);
        this.executeTransaction(transaction, merkleRoot, expiry, signatures);
    }

    function test_executorRemovalBehavior() public {
        // First remove executor1
        this.setExecutor(executor1, false);

        // Create dummy transaction components for the test
        OneSig.Call[] memory calls = new OneSig.Call[](0);
        bytes32[] memory proof = new bytes32[](0);
        OneSig.Transaction memory transaction = OneSig.Transaction({ calls: calls, proof: proof });
        bytes32 merkleRoot = bytes32(uint256(1));
        uint256 expiry = block.timestamp + 3600;
        bytes memory signatures = new bytes(0);

        // Test with removed executor
        vm.prank(executor1);
        vm.expectRevert(OnlyExecutorOrSigner.selector);
        this.executeTransaction(transaction, merkleRoot, expiry, signatures);
    }

    function test_signerRemovalBehavior() public {
        // First add another signer to avoid going below threshold
        address newSigner = vm.addr(8);
        this.setSigner(newSigner, true);

        // Now it's safe to remove signer1
        this.setSigner(signer1, false);

        // Create dummy transaction components for the test
        OneSig.Call[] memory calls = new OneSig.Call[](0);
        bytes32[] memory proof = new bytes32[](0);
        OneSig.Transaction memory transaction = OneSig.Transaction({ calls: calls, proof: proof });
        bytes32 merkleRoot = bytes32(uint256(1));
        uint256 expiry = block.timestamp + 3600;
        bytes memory signatures = new bytes(0);

        // Test with removed signer
        vm.prank(signer1);
        vm.expectRevert(OnlyExecutorOrSigner.selector);
        this.executeTransaction(transaction, merkleRoot, expiry, signatures);
    }

    /* ========== INTEGRATION TESTS ========== */

    function test_executorAndSignerInteraction() public {
        // Add a new address as both executor and signer
        address dualRole = vm.addr(10);

        // Add as executor
        this.setExecutor(dualRole, true);

        // Add as signer
        this.setSigner(dualRole, true);

        // Verify both roles
        assertTrue(isExecutor(dualRole));
        assertTrue(isSigner(dualRole));

        // Remove as executor but keep as signer
        this.setExecutor(dualRole, false);

        // Verify executor role removed but still signer
        assertFalse(isExecutor(dualRole));
        assertTrue(isSigner(dualRole));

        // Create dummy transaction components for the test
        OneSig.Call[] memory calls = new OneSig.Call[](0);
        bytes32[] memory proof = new bytes32[](0);
        OneSig.Transaction memory transaction = OneSig.Transaction({ calls: calls, proof: proof });
        bytes32 merkleRoot = bytes32(uint256(1));
        uint256 expiry = block.timestamp + 3600;
        bytes memory signatures = new bytes(0);

        // Should still be able to execute as signer, but will fail on signature validation
        vm.prank(dualRole);
        vm.expectRevert(SignatureError.selector);
        this.executeTransaction(transaction, merkleRoot, expiry, signatures);
    }
}
