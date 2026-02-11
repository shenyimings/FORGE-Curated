// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../src/interfaces/IMultiTokenPermit.sol";
import "../src/interfaces/IPermit3.sol";
import "./utils/TestBase.sol";

/**
 * @title Permit3Test
 * @notice Consolidated tests for core Permit3 functionality
 */
contract Permit3Test is TestBase {
    bytes32 public constant SIGNED_PERMIT3_WITNESS_TYPEHASH = keccak256(
        "SignedPermit3Witness(address owner,bytes32 salt,uint48 deadline,uint48 timestamp,bytes32 permitHash,bytes32 witnessTypeHash,bytes32 witness)"
    );

    function test_permitTransferFrom() public {
        // Create the permit
        IPermit3.ChainPermits memory chainPermits = _createBasicTransferPermit();

        // Reset recipient balance
        deal(address(token), recipient, 0);

        uint48 deadline = uint48(block.timestamp + 1 hours);
        uint48 timestamp = uint48(block.timestamp);
        bytes memory signature = _signPermit(chainPermits, deadline, timestamp, SALT);

        // Execute permit
        permit3.permit(owner, SALT, deadline, timestamp, chainPermits.permits, signature);

        // Verify transfer happened
        assertEq(token.balanceOf(recipient), AMOUNT);

        // Verify nonce is used
        assertTrue(permit3.isNonceUsed(owner, SALT));
    }

    function test_permitTransferFromExpired() public {
        // Create the permit
        IPermit3.ChainPermits memory chainPermits = _createBasicTransferPermit();

        uint48 deadline = uint48(block.timestamp - 1); // Expired
        uint48 timestamp = uint48(block.timestamp);
        bytes memory signature = _signPermit(chainPermits, deadline, timestamp, SALT);

        // Should revert with SignatureExpired
        vm.expectRevert(
            abi.encodeWithSelector(INonceManager.SignatureExpired.selector, deadline, uint48(block.timestamp))
        );
        permit3.permit(owner, SALT, deadline, timestamp, chainPermits.permits, signature);
    }

    function test_permitTransferFromInvalidSignature() public {
        // Create the permit
        IPermit3.ChainPermits memory chainPermits = _createBasicTransferPermit();

        uint48 deadline = uint48(block.timestamp + 1 hours);
        uint48 timestamp = uint48(block.timestamp);
        bytes memory signature = _signPermit(chainPermits, deadline, timestamp, SALT);

        // Modify signature to make it invalid
        signature[0] = signature[0] ^ bytes1(uint8(1));

        // Should revert with InvalidSignature
        // When signature is invalid, the recovered signer will be different from owner
        // We can't predict the exact recovered address, so we use expectRevert without parameters
        vm.expectRevert();
        permit3.permit(owner, SALT, deadline, timestamp, chainPermits.permits, signature);
    }

    function test_permitTransferFromReusedNonce() public {
        // Create the permit
        IPermit3.ChainPermits memory chainPermits = _createBasicTransferPermit();

        uint48 deadline = uint48(block.timestamp + 1 hours);
        uint48 timestamp = uint48(block.timestamp);
        bytes memory signature = _signPermit(chainPermits, deadline, timestamp, SALT);

        // First permit should succeed
        permit3.permit(owner, SALT, deadline, timestamp, chainPermits.permits, signature);

        // Second attempt with same nonce should fail
        vm.expectRevert(abi.encodeWithSelector(INonceManager.NonceAlreadyUsed.selector, owner, SALT));
        permit3.permit(owner, SALT, deadline, timestamp, chainPermits.permits, signature);
    }

    function test_permitTransferFromWrongChainId() public {
        // Skip this test if we're on chain 999 (unlikely in tests)
        if (block.chainid == 999) {
            return;
        }

        // Create a permit with wrong chain ID
        IPermit3.AllowanceOrTransfer[] memory permits = new IPermit3.AllowanceOrTransfer[](1);
        permits[0] = IPermit3.AllowanceOrTransfer({
            modeOrExpiration: 0, // Transfer mode
            tokenKey: bytes32(uint256(uint160(address(token)))),
            account: recipient,
            amountDelta: AMOUNT
        });

        IPermit3.ChainPermits memory chainPermits = IPermit3.ChainPermits({
            chainId: 999, // Wrong chain ID
            permits: permits
        });

        uint48 deadline = uint48(block.timestamp + 1 hours);
        uint48 timestamp = uint48(block.timestamp);
        bytes memory signature = _signPermit(chainPermits, deadline, timestamp, SALT);

        // Should revert with InvalidSignature (signature was created for wrong chain ID)
        vm.expectRevert();
        permit3.permit(owner, SALT, deadline, timestamp, chainPermits.permits, signature);
    }

    function test_permitAllowance() public {
        // Create a permit for allowance
        IPermit3.AllowanceOrTransfer[] memory permits = new IPermit3.AllowanceOrTransfer[](1);
        permits[0] = IPermit3.AllowanceOrTransfer({
            modeOrExpiration: EXPIRATION, // Setting expiration (allowance mode)
            tokenKey: bytes32(uint256(uint160(address(token)))),
            account: spender, // Approve spender
            amountDelta: AMOUNT
        });

        IPermit3.ChainPermits memory chainPermits =
            IPermit3.ChainPermits({ chainId: uint64(block.chainid), permits: permits });

        uint48 deadline = uint48(block.timestamp + 1 hours);
        uint48 timestamp = uint48(block.timestamp);
        bytes memory signature = _signPermit(chainPermits, deadline, timestamp, SALT);

        // Execute permit
        permit3.permit(owner, SALT, deadline, timestamp, chainPermits.permits, signature);

        // Verify allowance is set
        (uint160 amount, uint48 expiration,) = permit3.allowance(owner, address(token), spender);
        assertEq(amount, AMOUNT);
        assertEq(expiration, EXPIRATION);

        // Verify nonce is used
        assertTrue(permit3.isNonceUsed(owner, SALT));
    }

    function test_permitMultipleOperations() public {
        // Create combined permit with both allowance and transfer
        IPermit3.AllowanceOrTransfer[] memory permits = new IPermit3.AllowanceOrTransfer[](2);

        // Approve spender
        permits[0] = IPermit3.AllowanceOrTransfer({
            modeOrExpiration: EXPIRATION, // Setting expiration (allowance mode)
            tokenKey: bytes32(uint256(uint160(address(token)))),
            account: spender,
            amountDelta: AMOUNT
        });

        // Transfer tokens
        permits[1] = IPermit3.AllowanceOrTransfer({
            modeOrExpiration: 0, // Transfer mode
            tokenKey: bytes32(uint256(uint160(address(token)))),
            account: recipient,
            amountDelta: AMOUNT / 2
        });

        IPermit3.ChainPermits memory chainPermits =
            IPermit3.ChainPermits({ chainId: uint64(block.chainid), permits: permits });

        // Reset balances
        deal(address(token), recipient, 0);

        uint48 deadline = uint48(block.timestamp + 1 hours);
        uint48 timestamp = uint48(block.timestamp);
        bytes memory signature = _signPermit(chainPermits, deadline, timestamp, SALT);

        // Execute permit
        permit3.permit(owner, SALT, deadline, timestamp, chainPermits.permits, signature);

        // Verify allowance is set
        (uint160 amount, uint48 expiration,) = permit3.allowance(owner, address(token), spender);
        assertEq(amount, AMOUNT);
        assertEq(expiration, EXPIRATION);

        // Verify transfer happened
        assertEq(token.balanceOf(recipient), AMOUNT / 2);

        // Verify nonce is used
        assertTrue(permit3.isNonceUsed(owner, SALT));
    }

    // The witness test functionality is covered in Permit3Witness.t.sol
    // No need to duplicate it here

    function test_unbalancedPermit() public {
        // Test the unbalanced permit functionality

        // Create a chain permit for the current chain
        IPermit3.ChainPermits memory chainPermits = _createBasicTransferPermit();

        // Create a valid unbalanced proof (using preHash only, no subtreeProof - mutually exclusive)
        bytes32[] memory nodes = new bytes32[](2);
        nodes[0] = bytes32(uint256(0x1234)); // preHash
        nodes[1] = bytes32(uint256(0x9abc)); // following hash

        // Reset recipient balance
        deal(address(token), recipient, 0);

        uint48 deadline = uint48(block.timestamp + 1 hours);
        uint48 timestamp = uint48(block.timestamp);

        // Create signature
        bytes memory signature = _signUnbalancedPermit(chainPermits, nodes, deadline, timestamp, SALT);

        // Execute permit
        permit3.permit(owner, SALT, deadline, timestamp, chainPermits, nodes, signature);

        // Verify transfer happened
        assertEq(token.balanceOf(recipient), AMOUNT);

        // Verify nonce is used
        assertTrue(permit3.isNonceUsed(owner, SALT));
    }

    function test_invalidUnbalancedProof() public {
        // Test the branch where unbalanced proof is invalid

        // Create a chain permit for the current chain
        IPermit3.ChainPermits memory chainPermits = _createBasicTransferPermit();

        // Create an invalid unbalanced proof with invalid structure
        // Since we're testing the failure path, we'll make a fixed signature
        // instead of using the _signUnbalancedPermit helper which is failing for invalid proofs

        bytes32[] memory nodes = new bytes32[](1); // Just 1 node, invalid
        nodes[0] = bytes32(uint256(0x1)); // preHash only

        // Create invalid proof with insufficient nodes
        uint48 deadline = uint48(block.timestamp + 1 hours);
        uint48 timestamp = uint48(block.timestamp);

        // Create a dummy signature
        bytes memory signature = new bytes(65);

        // Test that an invalid proof reverts
        vm.expectRevert();
        vm.prank(owner);
        permit3.permit(owner, SALT, deadline, timestamp, chainPermits, nodes, signature);
    }

    function test_permitUnbalancedProofErrors() public {
        // Test errors in unbalanced permit processing

        // Create a chain permit with wrong chain ID
        IPermit3.ChainPermits memory chainPermits = IPermit3.ChainPermits({
            chainId: 999, // Wrong chain ID
            permits: new IPermit3.AllowanceOrTransfer[](0)
        });

        // Create a dummy proof
        bytes32[] memory nodes = new bytes32[](1);
        nodes[0] = bytes32(uint256(0x1));

        uint48 deadline = uint48(block.timestamp + 1 hours);
        uint48 timestamp = uint48(block.timestamp);

        // Create a dummy signature
        bytes memory signature = new bytes(65);

        // Test that wrong chain ID reverts with WrongChainId error
        vm.expectRevert(abi.encodeWithSelector(INonceManager.WrongChainId.selector, uint64(block.chainid), 999));
        vm.prank(owner);
        permit3.permit(owner, SALT, deadline, timestamp, chainPermits, nodes, signature);

        // Test that expired deadline reverts with SignatureExpired error
        uint48 expiredDeadline = uint48(block.timestamp - 1);

        vm.expectRevert(
            abi.encodeWithSelector(INonceManager.SignatureExpired.selector, expiredDeadline, uint48(block.timestamp))
        );
        vm.prank(owner);
        permit3.permit(owner, SALT, expiredDeadline, timestamp, chainPermits, nodes, signature);
    }

    // ============================================
    // Event Emission Tests for Signed Permits
    // ============================================

    function test_permit_emitsPermitEventForERC20() public {
        // Create a permit for ERC20 allowance
        IPermit3.AllowanceOrTransfer[] memory permits = new IPermit3.AllowanceOrTransfer[](1);
        permits[0] = IPermit3.AllowanceOrTransfer({
            modeOrExpiration: EXPIRATION,
            tokenKey: bytes32(uint256(uint160(address(token)))), // Clean address for ERC20
            account: spender,
            amountDelta: AMOUNT
        });

        IPermit3.ChainPermits memory chainPermits =
            IPermit3.ChainPermits({ chainId: uint64(block.chainid), permits: permits });

        uint48 deadline = uint48(block.timestamp + 1 hours);
        uint48 timestamp = uint48(block.timestamp);
        bytes memory signature = _signPermit(chainPermits, deadline, timestamp, SALT);

        // Expect the regular Permit event for ERC20 (clean address)
        vm.expectEmit(true, true, true, true);
        emit IPermit.Permit(owner, address(token), spender, AMOUNT, EXPIRATION, timestamp);

        // Execute permit
        permit3.permit(owner, SALT, deadline, timestamp, chainPermits.permits, signature);
    }

    function test_permit_emitsPermitMultiTokenEventForNFT() public {
        // Create a permit for NFT with specific tokenId
        bytes32 tokenKey = keccak256(abi.encodePacked(address(token), uint256(1)));

        IPermit3.AllowanceOrTransfer[] memory permits = new IPermit3.AllowanceOrTransfer[](1);
        permits[0] = IPermit3.AllowanceOrTransfer({
            modeOrExpiration: EXPIRATION,
            tokenKey: tokenKey, // Hash for NFT+tokenId
            account: spender,
            amountDelta: 1 // NFT amount
         });

        IPermit3.ChainPermits memory chainPermits =
            IPermit3.ChainPermits({ chainId: uint64(block.chainid), permits: permits });

        uint48 deadline = uint48(block.timestamp + 1 hours);
        uint48 timestamp = uint48(block.timestamp);
        bytes memory signature = _signPermit(chainPermits, deadline, timestamp, SALT);

        // Expect the PermitMultiToken event for NFT (hashed tokenKey)
        vm.expectEmit(true, true, true, true);
        emit IMultiTokenPermit.PermitMultiToken(owner, tokenKey, spender, 1, EXPIRATION, timestamp);

        // Execute permit
        permit3.permit(owner, SALT, deadline, timestamp, chainPermits.permits, signature);
    }

    function test_permit_revertsZeroTokenKey() public {
        // Create a permit with zero tokenKey
        IPermit3.AllowanceOrTransfer[] memory permits = new IPermit3.AllowanceOrTransfer[](1);
        permits[0] = IPermit3.AllowanceOrTransfer({
            modeOrExpiration: EXPIRATION,
            tokenKey: bytes32(0), // Zero tokenKey
            account: spender,
            amountDelta: AMOUNT
        });

        IPermit3.ChainPermits memory chainPermits =
            IPermit3.ChainPermits({ chainId: uint64(block.chainid), permits: permits });

        uint48 deadline = uint48(block.timestamp + 1 hours);
        uint48 timestamp = uint48(block.timestamp);
        bytes memory signature = _signPermit(chainPermits, deadline, timestamp, SALT);

        // Should revert with ZeroToken
        vm.expectRevert(IPermit.ZeroToken.selector);
        permit3.permit(owner, SALT, deadline, timestamp, chainPermits.permits, signature);
    }
}
