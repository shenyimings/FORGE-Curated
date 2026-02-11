// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.26;

import { VmSafe } from "@prb/test/Vm.sol";
import { PRBTest } from "@prb/test/PRBTest.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { IERC20Errors } from "@openzeppelin/interfaces/draft-IERC6093.sol";
import { IERC1271 } from "@openzeppelin/interfaces/IERC1271.sol";
import {MessageHashUtils} from "@openzeppelin/utils/cryptography/MessageHashUtils.sol";
import { Token_ERC20, Token_ERC721, SelfDestructingMock, NonStandardToken } from "./helpers/Mocks.t.sol";

import { Tea } from "../src/TeaToken/Tea.sol";
import { ERC1271Wallet } from "./helpers/ERC1271Wallet.sol";
import { PasskeyWallet } from "./helpers/PasskeyWallet.sol";
import { TokenDeploy } from "../src/TeaToken/TokenDeploy.sol";
import { MintManager } from "../src/TeaToken/MintManager.sol";
import { DeterministicDeployer } from "../src/utils/DeterministicDeployer.sol";
import { ERC20Permit } from "../src/TeaToken/ERC20PermitWithERC1271.sol";
import { EIP3009 } from "../src/TeaToken/EIP3009.sol";

/* solhint-disable max-states-count */
contract TeaTokenTest is PRBTest, StdCheats {
    Tea internal tea;
    TokenDeploy internal tokenDeploy;
    MintManager internal mintManager;
    ERC1271Wallet internal smartWallet;
    PasskeyWallet internal passkeyWallet;

    VmSafe.Wallet internal initialGovernor = vm.createWallet("Initial Gov Account");
    VmSafe.Wallet internal alice = vm.createWallet("Alice Account");
    VmSafe.Wallet internal bob = vm.createWallet("Bob Account");
    VmSafe.Wallet internal smartWalletOwner = vm.createWallet("SmartWallet Account");
    VmSafe.Wallet internal passkeyOwner = vm.createWallet("Passkey Owner Account");

    error OwnableUnauthorizedAccount(address account);
    error ERC20InsufficientAllowance(address spender, uint256 allowance, uint256 needed);
    event RecoveredToken(address indexed token, address indexed to, uint256 amount);
    event RecoveredNFT(address indexed token, address indexed to, uint256 tokenId);
    event RecoveredEth(address indexed to, uint256 amount);

    // Helper to pack r,s,v into bytes signature
    function packSignature(bytes32 r, bytes32 s, uint8 v) internal pure returns (bytes memory) {
        bytes memory sig = new bytes(65);
        for (uint256 i; i < 32; i++) {
            sig[i] = r[i];
        }
        for (uint256 i = 32; i < 64; i++) {
            sig[i] = s[i-32];
        }
        sig[64] = bytes1(v);
        return sig;
    }

    function setUp() public virtual {
        vm.createSelectFork({ urlOrAlias: "mainnet", blockNumber: 20_456_340 });
        bytes32 salt = keccak256(abi.encode(0x00, "tea"));
        tokenDeploy = TokenDeploy(
            DeterministicDeployer._deploy(salt, type(TokenDeploy).creationCode, abi.encode(initialGovernor.addr))
        );

        vm.prank(initialGovernor.addr);
        tokenDeploy.deploy(keccak256(abi.encode(0x01, salt)), keccak256(abi.encode(0x02, salt)), keccak256(abi.encode(0x03, salt)));

        tea = Tea(payable(tokenDeploy.tea()));
        mintManager = MintManager(tokenDeploy.mintManager());

        smartWallet = ERC1271Wallet(
            DeterministicDeployer._deploy(salt, type(ERC1271Wallet).creationCode, abi.encode(smartWalletOwner.addr))
        );
        
        passkeyWallet = PasskeyWallet(
            DeterministicDeployer._deploy(keccak256(abi.encode(salt, "passkey")), type(PasskeyWallet).creationCode, abi.encode(passkeyOwner.addr))
        );
    }

    function test_owner() public {
        assertEq(tea.owner(), address(mintManager));
    }

    function test_mint_fail() public {
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, address(this)));
        tea.mintTo(alice.addr, 1);

        vm.startPrank(initialGovernor.addr);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, initialGovernor.addr));
        tea.mintTo(alice.addr, 1);
        vm.stopPrank();
    }

    function test_mint_succeed() public {
        vm.warp(block.timestamp + 365 days);

        vm.prank(initialGovernor.addr);
        mintManager.mintTo(alice.addr, 1);

        assertEq(tea.totalSupply(), tea.INITIAL_SUPPLY() + 1);
        assertEq(tea.totalMinted(), tea.INITIAL_SUPPLY() + 1);
        assertEq(tea.balanceOf(alice.addr), 1);
    }

    function test_burn_fail() public {
        vm.warp(block.timestamp + 365 days);

        vm.prank(initialGovernor.addr);
        mintManager.mintTo(alice.addr, 1);

        vm.expectRevert(abi.encodeWithSelector(ERC20InsufficientAllowance.selector, address(this), 0, 1));
        tea.burnFrom(alice.addr, 1);
    }

    function test_transfer_functionality() public {
        vm.warp(block.timestamp + 365 days);

        // Mint some tokens to alice
        vm.prank(initialGovernor.addr);
        mintManager.mintTo(alice.addr, 100);

        // Test transfer
        vm.prank(alice.addr);
        tea.transfer(bob.addr, 50);

        assertEq(tea.balanceOf(alice.addr), 50);
        assertEq(tea.balanceOf(bob.addr), 50);
    }

    function test_approve_and_transferFrom() public {
        vm.warp(block.timestamp + 365 days);

        // Mint some tokens to alice
        vm.prank(initialGovernor.addr);
        mintManager.mintTo(alice.addr, 100);

        // Alice approves Bob to spend 30 tokens
        vm.prank(alice.addr);
        tea.approve(bob.addr, 30);

        // Bob transfers 20 tokens from Alice to himself
        vm.prank(bob.addr);
        tea.transferFrom(alice.addr, bob.addr, 20);

        assertEq(tea.balanceOf(alice.addr), 80);
        assertEq(tea.balanceOf(bob.addr), 20);
        assertEq(tea.allowance(alice.addr, bob.addr), 10);
    }

    function test_burn_succeed() public {
        vm.warp(block.timestamp + 365 days);

        vm.prank(initialGovernor.addr);
        mintManager.mintTo(alice.addr, 1);

        vm.prank(alice.addr);
        tea.approve(address(this), 1);

        tea.burnFrom(alice.addr, 1);

        assertEq(tea.totalSupply(), tea.INITIAL_SUPPLY());
        assertEq(tea.totalMinted(), tea.INITIAL_SUPPLY() + 1);
        assertEq(tea.balanceOf(alice.addr), 0);
    }

    function test_zero_address_transfers() public {
        vm.warp(block.timestamp + 365 days);

        vm.prank(initialGovernor.addr);
        mintManager.mintTo(alice.addr, 100);

        vm.prank(alice.addr);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        tea.transfer(address(0), 50);
    }

    function test_mint_toZeroAddress_reverts() external {
        vm.warp(block.timestamp + 365 days);
        vm.prank(initialGovernor.addr);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        mintManager.mintTo(address(0), 100);
    }

    // ========================================
    // Allowance Hygiene Tests (increaseAllowance/decreaseAllowance)
    // ========================================

    function test_increaseAllowance_fromZero() public {
        // Start with zero allowance
        assertEq(tea.allowance(alice.addr, bob.addr), 0);

        // Increase from zero
        vm.prank(alice.addr);
        bool success = tea.increaseAllowance(bob.addr, 100);

        assertTrue(success);
        assertEq(tea.allowance(alice.addr, bob.addr), 100);
    }

    function test_increaseAllowance_fromExisting() public {
        // Set initial allowance
        vm.prank(alice.addr);
        tea.approve(bob.addr, 50);
        assertEq(tea.allowance(alice.addr, bob.addr), 50);

        // Increase allowance
        vm.prank(alice.addr);
        bool success = tea.increaseAllowance(bob.addr, 75);

        assertTrue(success);
        assertEq(tea.allowance(alice.addr, bob.addr), 125);
    }

    function test_increaseAllowance_overflow() public {
        // Set allowance near max
        vm.prank(alice.addr);
        tea.approve(bob.addr, type(uint256).max - 50);

        // Try to increase beyond max - should overflow/revert
        vm.prank(alice.addr);
        vm.expectRevert();
        tea.increaseAllowance(bob.addr, 100);
    }

    function test_decreaseAllowance_toZero() public {
        // Set initial allowance
        vm.prank(alice.addr);
        tea.approve(bob.addr, 100);

        // Decrease to zero
        vm.prank(alice.addr);
        bool success = tea.decreaseAllowance(bob.addr, 100);

        assertTrue(success);
        assertEq(tea.allowance(alice.addr, bob.addr), 0);
    }

    function test_decreaseAllowance_partial() public {
        // Set initial allowance
        vm.prank(alice.addr);
        tea.approve(bob.addr, 100);

        // Decrease partially
        vm.prank(alice.addr);
        bool success = tea.decreaseAllowance(bob.addr, 60);

        assertTrue(success);
        assertEq(tea.allowance(alice.addr, bob.addr), 40);
    }

    function test_decreaseAllowance_underflow_reverts() public {
        // Set initial allowance
        vm.prank(alice.addr);
        tea.approve(bob.addr, 50);

        // Try to decrease more than available - should revert
        vm.prank(alice.addr);
        vm.expectRevert("ERC20: decreased allowance below zero");
        tea.decreaseAllowance(bob.addr, 100);

        // Allowance should remain unchanged
        assertEq(tea.allowance(alice.addr, bob.addr), 50);
    }

    function test_decreaseAllowance_fromZero_reverts() public {
        // No allowance set
        assertEq(tea.allowance(alice.addr, bob.addr), 0);

        // Try to decrease from zero - should revert
        vm.prank(alice.addr);
        vm.expectRevert("ERC20: decreased allowance below zero");
        tea.decreaseAllowance(bob.addr, 1);
    }

    function test_allowance_zeroAddress_reverts() public {
        // Try to increase allowance for zero address - _approve will revert
        vm.prank(alice.addr);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        tea.increaseAllowance(address(0), 100);

        // For decreaseAllowance with zero allowance, it reverts with underflow error first
        vm.prank(alice.addr);
        vm.expectRevert("ERC20: decreased allowance below zero");
        tea.decreaseAllowance(address(0), 100);
        
        // But if we have allowance set to zero address (via approve), decrease should work
        // Note: OpenZeppelin's _approve will revert on zero address, so we can't test this path
    }

    // ========================================
    // ERC-2612 Permit Tests
    // ========================================

    function test_ERC1271_permit_standard_success() public {
        // Create Hash
        bytes32 messageHash = keccak256(
            abi.encode(
                tea.PERMIT_TYPEHASH(),
                smartWalletOwner.addr,
                alice.addr, 1,
                tea.nonces(smartWalletOwner.addr),
                block.timestamp + 10000
            ));

        bytes32 hash =  MessageHashUtils.toTypedDataHash(tea.DOMAIN_SEPARATOR(), messageHash);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(smartWalletOwner, hash);

        vm.prank(smartWalletOwner.addr);
        tea.permit(
            smartWalletOwner.addr,
            alice.addr,
            1,
            block.timestamp + 10000,
            v,
            r,
            s
        );

        assertEq(tea.allowance(smartWalletOwner.addr, alice.addr), 1, "Permit should succeed");
        assertEq(tea.nonces(smartWalletOwner.addr), 1, "Nonce should increment");
    }

    /// @notice EIP-7702 style test: EOA signs a 65-byte bytes signature and uses the bytes overload of permit
    function test_EIP7702_permit_EOA_bytesSignature_success() public {
        // Build permit digest for alice -> bob
        bytes32 messageHash = keccak256(
            abi.encode(
                tea.PERMIT_TYPEHASH(),
                alice.addr,
                bob.addr,
                1,
                tea.nonces(alice.addr),
                block.timestamp + 10000
            )
        );
        bytes32 digest = MessageHashUtils.toTypedDataHash(tea.DOMAIN_SEPARATOR(), messageHash);

        // Sign digest with alice EOA
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alice, digest);

        // Pack into bytes signature (r || s || v)
        bytes memory signature = packSignature(r, s, v);

        // Call bytes-overload permit
        tea.permit(alice.addr, bob.addr, 1, block.timestamp + 10000, signature);

        // Expect allowance and nonce to update
        assertEq(tea.allowance(alice.addr, bob.addr), 1, "Permit (bytes) should succeed for EOA");
        assertEq(tea.nonces(alice.addr), 1, "Nonce should increment after successful permit");
    }

    function test_ERC1271_permit_standard_reuse_fail() public {
        // Create Hash
        bytes32 messageHash = keccak256(
            abi.encode(
                tea.PERMIT_TYPEHASH(),
                smartWalletOwner.addr,
                alice.addr, 1,
                tea.nonces(smartWalletOwner.addr),
                block.timestamp + 10000
            ));

        bytes32 hash =  MessageHashUtils.toTypedDataHash(tea.DOMAIN_SEPARATOR(), messageHash);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(smartWalletOwner, hash);

        vm.prank(smartWalletOwner.addr);
        tea.permit(
            smartWalletOwner.addr,
            alice.addr,
            1,
            block.timestamp + 10000,
            v,
            r,
            s
        );

        assertEq(tea.allowance(smartWalletOwner.addr, alice.addr), 1, "Permit should succeed");
        assertEq(tea.nonces(smartWalletOwner.addr), 1, "Nonce should increment");
        vm.expectRevert();
        vm.prank(smartWalletOwner.addr);
        tea.permit(
            smartWalletOwner.addr,
            alice.addr,
            1,
            block.timestamp + 10000,
            v,
            r,
            s
        );

        assertEq(tea.allowance(smartWalletOwner.addr, alice.addr), 1, "Permit should Fail");
        assertEq(tea.nonces(smartWalletOwner.addr), 1, "Nonce should not increment");
    }

    function test_ERC1271_permit_erc1271_success() public {
        // Create Hash
        bytes32 messageHash = keccak256(
            abi.encode(
                tea.PERMIT_TYPEHASH(),
                address(smartWallet),
                alice.addr, 1,
                tea.nonces(address(smartWallet)),
                block.timestamp + 10000
            ));

        bytes32 hash =  MessageHashUtils.toTypedDataHash(tea.DOMAIN_SEPARATOR(), messageHash);

        // SECURITY: The wallet wraps the digest to prevent signature replay attacks
        // We must sign the wrapped digest, not the original application digest
        bytes32 wrappedHash = smartWallet.getWrappedDigest(hash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(smartWalletOwner, wrappedHash);

        bytes memory signature = packSignature(r, s, v);
        bytes4 result = smartWallet.isValidSignature(hash, signature);

        // Assert its valid
        assertEq(result, IERC1271.isValidSignature.selector, "Valid signature should return the magic value");

        vm.prank(smartWalletOwner.addr);
        tea.permit(
            address(smartWallet),
            alice.addr,
            1,
            block.timestamp + 10000,
            v,
            r,
            s
        );

        assertEq(tea.allowance(address(smartWallet), alice.addr), 1, "Permit should succeed");
        assertEq(tea.nonces(address(smartWallet)), 1, "Nonce should increment");
    }

    function test_ERC1271_permit_erc1271_reuse_fail() public {
        // Create Hash
        bytes32 messageHash = keccak256(
            abi.encode(
                tea.PERMIT_TYPEHASH(),
                address(smartWallet),
                alice.addr, 1,
                tea.nonces(address(smartWallet)),
                block.timestamp + 10000
            ));

        bytes32 hash =  MessageHashUtils.toTypedDataHash(tea.DOMAIN_SEPARATOR(), messageHash);

        // SECURITY: Sign the wrapped digest to prevent replay attacks
        bytes32 wrappedHash = smartWallet.getWrappedDigest(hash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(smartWalletOwner, wrappedHash);

        bytes memory signature = packSignature(r, s, v);
        bytes4 result = smartWallet.isValidSignature(hash, signature);

        // Assert its valid
        assertEq(result, IERC1271.isValidSignature.selector, "Valid signature should return the magic value");

        vm.prank(smartWalletOwner.addr);
        tea.permit(
            address(smartWallet),
            alice.addr,
            1,
            block.timestamp + 10000,
            v,
            r,
            s
        );

        assertEq(tea.allowance(address(smartWallet), alice.addr), 1, "Permit should succeed");
        assertEq(tea.nonces(address(smartWallet)), 1, "Nonce should increment");

        vm.prank(smartWalletOwner.addr);
        vm.expectRevert();
        tea.permit(
            address(smartWallet),
            alice.addr,
            1,
            block.timestamp + 10000,
            v,
            r,
            s
        );

        assertEq(tea.allowance(address(smartWallet), alice.addr), 1, "Permit should fail");
        assertEq(tea.nonces(address(smartWallet)), 1, "Nonce should not increment");
    }

    function test_ERC1271_permit_erc1271_contract_does_not_exist() public {
        // Create Hash
        bytes32 messageHash = keccak256(
            abi.encode(
                tea.PERMIT_TYPEHASH(),
                bob.addr,
                alice.addr, 1,
                tea.nonces(smartWalletOwner.addr),
                block.timestamp + 10000
            ));

        bytes32 hash =  MessageHashUtils.toTypedDataHash(tea.DOMAIN_SEPARATOR(), messageHash);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(smartWalletOwner, hash);

        vm.prank(smartWalletOwner.addr);
        vm.expectRevert();
        tea.permit(
            smartWalletOwner.addr,
            alice.addr,
            1,
            block.timestamp + 10000,
            v,
            r,
            s
        );

        assertEq(tea.allowance(smartWalletOwner.addr, alice.addr), 0, "Permit should fail");
        assertEq(tea.nonces(smartWalletOwner.addr), 0, "Nonce should not increment");
    }

    function test_ERC1271_permit_erc1271_attacker() public {
        // Create Hash
        bytes32 messageHash = keccak256(
            abi.encode(
                tea.PERMIT_TYPEHASH(),
                address(smartWallet),
                alice.addr, 1,
                tea.nonces(smartWalletOwner.addr),
                block.timestamp + 10000
            ));

        bytes32 hash =  MessageHashUtils.toTypedDataHash(tea.DOMAIN_SEPARATOR(), messageHash);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(bob, hash);

        vm.prank(smartWalletOwner.addr);
        vm.expectRevert(abi.encodeWithSelector(ERC20Permit.ERC2612InvalidSigner.selector, bob.addr, address(smartWallet)));
        tea.permit(
            address(smartWallet),
            alice.addr,
            1,
            block.timestamp + 10000,
            v,
            r,
            s
        );

        assertEq(tea.allowance(address(smartWallet), alice.addr), 0, "Permit should fail");
        assertEq(tea.nonces(address(smartWallet)), 0, "Nonce should not increment");
    }

    // ========================================
    // Permit Edge Case Tests
    // ========================================

    function test_permit_expiredDeadline_reverts() public {
        uint256 expiredDeadline = block.timestamp - 1; // 1 second in the past

        bytes32 messageHash = keccak256(
            abi.encode(
                tea.PERMIT_TYPEHASH(),
                alice.addr,
                bob.addr,
                100,
                tea.nonces(alice.addr),
                expiredDeadline
            ));

        bytes32 hash = MessageHashUtils.toTypedDataHash(tea.DOMAIN_SEPARATOR(), messageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alice, hash);

        // Should revert with ERC2612ExpiredSignature
        vm.expectRevert(abi.encodeWithSelector(ERC20Permit.ERC2612ExpiredSignature.selector, expiredDeadline));
        tea.permit(alice.addr, bob.addr, 100, expiredDeadline, v, r, s);
        assertEq(tea.nonces(alice.addr), 0, "Nonce should not increment");
    }

    function test_permit_deadlineBoundary_exactTimestamp() public {
        // Deadline exactly at current timestamp should succeed
        uint256 deadline = block.timestamp;

        bytes32 messageHash = keccak256(
            abi.encode(
                tea.PERMIT_TYPEHASH(),
                alice.addr,
                bob.addr,
                100,
                tea.nonces(alice.addr),
                deadline
            ));

        bytes32 hash = MessageHashUtils.toTypedDataHash(tea.DOMAIN_SEPARATOR(), messageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alice, hash);

        // Should succeed (deadline check is >, not >=)
        tea.permit(alice.addr, bob.addr, 100, deadline, v, r, s);

        assertEq(tea.allowance(alice.addr, bob.addr), 100);
        assertEq(tea.nonces(alice.addr), 1, "Nonce should increment");
    }

    function test_permit_maxUint256Value() public {
        // Test permit with max uint256 value
        uint256 maxValue = type(uint256).max;
        uint256 deadline = block.timestamp + 1000;

        bytes32 messageHash = keccak256(
            abi.encode(
                tea.PERMIT_TYPEHASH(),
                alice.addr,
                bob.addr,
                maxValue,
                tea.nonces(alice.addr),
                deadline
            ));

        bytes32 hash = MessageHashUtils.toTypedDataHash(tea.DOMAIN_SEPARATOR(), messageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alice, hash);

        tea.permit(alice.addr, bob.addr, maxValue, deadline, v, r, s);

        assertEq(tea.allowance(alice.addr, bob.addr), maxValue);
        assertEq(tea.nonces(alice.addr), 1, "Nonce should increment");
    }

    function test_permit_integrationWithTransferFrom() public {
        vm.warp(block.timestamp + 365 days);

        // Mint tokens to alice
        vm.prank(initialGovernor.addr);
        mintManager.mintTo(alice.addr, 1000);

        // Alice permits bob to spend 500 tokens
        uint256 deadline = block.timestamp + 1000;
        bytes32 messageHash = keccak256(
            abi.encode(
                tea.PERMIT_TYPEHASH(),
                alice.addr,
                bob.addr,
                500,
                tea.nonces(alice.addr),
                deadline
            ));

        bytes32 hash = MessageHashUtils.toTypedDataHash(tea.DOMAIN_SEPARATOR(), messageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alice, hash);

        tea.permit(alice.addr, bob.addr, 500, deadline, v, r, s);

        // Bob can now transfer from alice
        vm.prank(bob.addr);
        tea.transferFrom(alice.addr, bob.addr, 300);

        assertEq(tea.balanceOf(alice.addr), 700);
        assertEq(tea.balanceOf(bob.addr), 300);
        assertEq(tea.allowance(alice.addr, bob.addr), 200); // 500 - 300 = 200 remaining
        assertEq(tea.nonces(alice.addr), 1, "Nonce should increment");
    }

    function test_permit_invalidNonce_reverts() public {
        uint256 deadline = block.timestamp + 1000;
        uint256 wrongNonce = tea.nonces(alice.addr) + 1; // Wrong nonce

        bytes32 messageHash = keccak256(
            abi.encode(
                tea.PERMIT_TYPEHASH(),
                alice.addr,
                bob.addr,
                100,
                wrongNonce,
                deadline
            ));

        bytes32 hash = MessageHashUtils.toTypedDataHash(tea.DOMAIN_SEPARATOR(), messageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alice, hash);

        // Should revert with invalid signer
        vm.expectRevert();
        tea.permit(alice.addr, bob.addr, 100, deadline, v, r, s);
        assertEq(tea.nonces(alice.addr), 0, "Nonce should not increment");
    }

    // ==================== permitBurn Tests ====================
    function test_permitBurn_EOA_success() public {
        vm.warp(block.timestamp + 365 days);

        // Mint tokens to alice so she can burn
        vm.prank(initialGovernor.addr);
        mintManager.mintTo(alice.addr, 1000);

        uint256 amount = 100;
        uint256 deadline = block.timestamp + 1000;

        bytes32 messageHash = keccak256(
            abi.encode(
                tea.PERMIT_BURN_TYPEHASH(),
                alice.addr,
                amount,
                tea.nonces(alice.addr),
                deadline
            )
        );

        bytes32 hash = MessageHashUtils.toTypedDataHash(tea.DOMAIN_SEPARATOR(), messageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alice, hash);

        // Call permitBurn (any caller can submit)
        tea.permitBurn(alice.addr, amount, deadline, v, r, s);

        assertEq(tea.balanceOf(alice.addr), 1000 - amount);
        assertEq(tea.nonces(alice.addr), 1, "Nonce should increment");
    }

    function test_permitBurn_replay_fails() public {
        vm.warp(block.timestamp + 365 days);

        // Mint tokens to alice
        vm.prank(initialGovernor.addr);
        mintManager.mintTo(alice.addr, 2000);

        uint256 amount = 50;
        uint256 deadline = block.timestamp + 1000;

        bytes32 messageHash = keccak256(
            abi.encode(
                tea.PERMIT_BURN_TYPEHASH(),
                alice.addr,
                amount,
                tea.nonces(alice.addr),
                deadline
            )
        );

        bytes32 hash = MessageHashUtils.toTypedDataHash(tea.DOMAIN_SEPARATOR(), messageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alice, hash);

        // First call succeeds
        tea.permitBurn(alice.addr, amount, deadline, v, r, s);
        assertEq(tea.nonces(alice.addr), 1, "Nonce should increment");

        // Second call with same signature should fail (nonce consumed)
        vm.expectRevert();
        tea.permitBurn(alice.addr, amount, deadline, v, r, s);
        assertEq(tea.nonces(alice.addr), 1, "Nonce should not increment");
    }

    function test_permitBurn_expiredDeadline_reverts() public {
        uint256 expiredDeadline = block.timestamp - 1;
        uint256 amount = 1;

        bytes32 messageHash = keccak256(
            abi.encode(
                tea.PERMIT_BURN_TYPEHASH(),
                alice.addr,
                amount,
                tea.nonces(alice.addr),
                expiredDeadline
            )
        );

        bytes32 hash = MessageHashUtils.toTypedDataHash(tea.DOMAIN_SEPARATOR(), messageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alice, hash);

        vm.expectRevert(abi.encodeWithSelector(ERC20Permit.ERC2612ExpiredSignature.selector, expiredDeadline));
        tea.permitBurn(alice.addr, amount, expiredDeadline, v, r, s);
        assertEq(tea.nonces(alice.addr), 0, "Nonce should not increment");
    }

    function test_permitBurn_invalidSigner_reverts() public {
        vm.warp(block.timestamp + 365 days);

        vm.prank(initialGovernor.addr);
        mintManager.mintTo(alice.addr, 1000);

        uint256 amount = 10;
        uint256 deadline = block.timestamp + 1000;

        bytes32 messageHash = keccak256(
            abi.encode(
                tea.PERMIT_BURN_TYPEHASH(),
                alice.addr,
                amount,
                tea.nonces(alice.addr),
                deadline
            )
        );

        bytes32 hash = MessageHashUtils.toTypedDataHash(tea.DOMAIN_SEPARATOR(), messageHash);
        // Sign with bob (attacker)
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(bob, hash);

        vm.expectRevert();
        tea.permitBurn(alice.addr, amount, deadline, v, r, s);
        assertEq(tea.nonces(alice.addr), 0, "Nonce should not increment");
    }

    function test_permitBurn_erc1271_success() public {
        vm.warp(block.timestamp + 365 days);

        // Deploy a smart wallet and mint tokens to it
        ERC1271Wallet wallet = new ERC1271Wallet(smartWalletOwner.addr);

        vm.startPrank(initialGovernor.addr);
        mintManager.mintTo(address(wallet), 1000);
        vm.stopPrank();

        uint256 amount = 25;
        uint256 deadline = block.timestamp + 1000;

        bytes32 messageHash = keccak256(
            abi.encode(
                tea.PERMIT_BURN_TYPEHASH(),
                address(wallet),
                amount,
                tea.nonces(address(wallet)),
                deadline
            )
        );

        bytes32 hash = MessageHashUtils.toTypedDataHash(tea.DOMAIN_SEPARATOR(), messageHash);

        // Sign the wrapped digest for the wallet
        bytes32 wrapped = wallet.getWrappedDigest(hash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(smartWalletOwner, wrapped);

        bytes memory signature = packSignature(r, s, v);

        // Caller can be anyone; emulate sender as smartWalletOwner for parity with other tests
        vm.prank(smartWalletOwner.addr);
        tea.permitBurn(address(wallet), amount, deadline, signature);

        assertEq(tea.balanceOf(address(wallet)), 1000 - amount);
        assertEq(tea.nonces(address(wallet)), 1, "Nonce should increment");
    }

    // ========== EIP-3009 Tests ==========

    function test_transferWithAuthorization_EOA_success() public {
        vm.warp(block.timestamp + 365 days);

        // Mint tokens to alice
        vm.prank(initialGovernor.addr);
        mintManager.mintTo(alice.addr, 1000);

        uint256 validAfter = block.timestamp - 1; // 1 second in the past
        uint256 validBefore = block.timestamp + 1000;
        bytes32 nonce = keccak256(abi.encodePacked("nonce1"));

        // Create authorization hash
        bytes32 messageHash = keccak256(
            abi.encode(
                tea.TRANSFER_WITH_AUTHORIZATION_TYPEHASH(),
                alice.addr,
                bob.addr,
                100,
                validAfter,
                validBefore,
                nonce
            ));

        bytes32 hash = MessageHashUtils.toTypedDataHash(tea.DOMAIN_SEPARATOR(), messageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alice, hash);

        // Execute transfer with authorization
        tea.transferWithAuthorization(
            alice.addr,
            bob.addr,
            100,
            validAfter,
            validBefore,
            nonce,
            v,
            r,
            s
        );

        assertEq(tea.balanceOf(alice.addr), 900);
        assertEq(tea.balanceOf(bob.addr), 100);
        assertTrue(tea.authorizationState(alice.addr, nonce));
    }

    function test_transferWithAuthorization_ERC1271_success() public {
        vm.warp(block.timestamp + 365 days);

        // Mint tokens to smart wallet
        vm.prank(initialGovernor.addr);
        mintManager.mintTo(address(smartWallet), 1000);

        uint256 validAfter = block.timestamp - 1;
        uint256 validBefore = block.timestamp + 1000;
        bytes32 nonce = keccak256(abi.encodePacked("nonce2"));

        // Create authorization hash
        bytes32 messageHash = keccak256(
            abi.encode(
                tea.TRANSFER_WITH_AUTHORIZATION_TYPEHASH(),
                address(smartWallet),
                bob.addr,
                100,
                validAfter,
                validBefore,
                nonce
            ));

        bytes32 hash = MessageHashUtils.toTypedDataHash(tea.DOMAIN_SEPARATOR(), messageHash);
        
        // SECURITY: Sign the wrapped digest to prevent replay attacks
        bytes32 wrappedHash = smartWallet.getWrappedDigest(hash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(smartWalletOwner, wrappedHash);

        // Execute transfer with authorization
        tea.transferWithAuthorization(
            address(smartWallet),
            bob.addr,
            100,
            validAfter,
            validBefore,
            nonce,
            v,
            r,
            s
        );

        assertEq(tea.balanceOf(address(smartWallet)), 900);
        assertEq(tea.balanceOf(bob.addr), 100);
        assertTrue(tea.authorizationState(address(smartWallet), nonce));
    }

    function test_transferWithAuthorization_replay_fails() public {
        vm.warp(block.timestamp + 365 days);

        vm.prank(initialGovernor.addr);
        mintManager.mintTo(alice.addr, 1000);

        uint256 validAfter = block.timestamp - 1;
        uint256 validBefore = block.timestamp + 1000;
        bytes32 nonce = keccak256(abi.encodePacked("nonce3"));

        bytes32 messageHash = keccak256(
            abi.encode(
                tea.TRANSFER_WITH_AUTHORIZATION_TYPEHASH(),
                alice.addr,
                bob.addr,
                100,
                validAfter,
                validBefore,
                nonce
            ));

        bytes32 hash = MessageHashUtils.toTypedDataHash(tea.DOMAIN_SEPARATOR(), messageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alice, hash);

        // First transfer succeeds
        tea.transferWithAuthorization(alice.addr, bob.addr, 100, validAfter, validBefore, nonce, v, r, s);
        assertTrue(tea.authorizationState(alice.addr, nonce));

        // Second transfer with same nonce fails
        vm.expectRevert(abi.encodeWithSelector(EIP3009.EIP3009AuthorizationAlreadyUsed.selector, alice.addr, nonce));
        tea.transferWithAuthorization(alice.addr, bob.addr, 100, validAfter, validBefore, nonce, v, r, s);
    }

    function test_transferWithAuthorization_expired_fails() public {
        vm.warp(block.timestamp + 365 days);

        vm.prank(initialGovernor.addr);
        mintManager.mintTo(alice.addr, 1000);

        uint256 validAfter = block.timestamp - 1000;
        uint256 validBefore = block.timestamp - 1; // Already expired
        bytes32 nonce = keccak256(abi.encodePacked("nonce4"));

        bytes32 messageHash = keccak256(
            abi.encode(
                tea.TRANSFER_WITH_AUTHORIZATION_TYPEHASH(),
                alice.addr,
                bob.addr,
                100,
                validAfter,
                validBefore,
                nonce
            ));

        bytes32 hash = MessageHashUtils.toTypedDataHash(tea.DOMAIN_SEPARATOR(), messageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alice, hash);

        vm.expectRevert(abi.encodeWithSelector(EIP3009.EIP3009AuthorizationExpired.selector, validBefore, block.timestamp));
        tea.transferWithAuthorization(alice.addr, bob.addr, 100, validAfter, validBefore, nonce, v, r, s);
        assertFalse(tea.authorizationState(alice.addr, nonce));
    }

    function test_transferWithAuthorization_notYetValid_fails() public {
        vm.warp(block.timestamp + 365 days);

        vm.prank(initialGovernor.addr);
        mintManager.mintTo(alice.addr, 1000);

        uint256 validAfter = block.timestamp + 1000;
        uint256 validBefore = block.timestamp + 2000;
        bytes32 nonce = keccak256(abi.encodePacked("nonce5"));

        bytes32 messageHash = keccak256(
            abi.encode(
                tea.TRANSFER_WITH_AUTHORIZATION_TYPEHASH(),
                alice.addr,
                bob.addr,
                100,
                validAfter,
                validBefore,
                nonce
            ));

        bytes32 hash = MessageHashUtils.toTypedDataHash(tea.DOMAIN_SEPARATOR(), messageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alice, hash);

        vm.expectRevert(abi.encodeWithSelector(EIP3009.EIP3009AuthorizationNotYetValid.selector, validAfter, block.timestamp));
        tea.transferWithAuthorization(alice.addr, bob.addr, 100, validAfter, validBefore, nonce, v, r, s);
        assertFalse(tea.authorizationState(alice.addr, nonce));
    }

    function test_transferWithAuthorization_invalidSignature_fails() public {
        vm.warp(block.timestamp + 365 days);

        vm.prank(initialGovernor.addr);
        mintManager.mintTo(alice.addr, 1000);

        uint256 validAfter = block.timestamp - 1;
        uint256 validBefore = block.timestamp + 1000;
        bytes32 nonce = keccak256(abi.encodePacked("nonce6"));

        bytes32 messageHash = keccak256(
            abi.encode(
                tea.TRANSFER_WITH_AUTHORIZATION_TYPEHASH(),
                alice.addr,
                bob.addr,
                100,
                validAfter,
                validBefore,
                nonce
            ));

        bytes32 hash = MessageHashUtils.toTypedDataHash(tea.DOMAIN_SEPARATOR(), messageHash);
        // Sign with wrong key (bob instead of alice)
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(bob, hash);

        vm.expectRevert(abi.encodeWithSelector(EIP3009.EIP3009InvalidSignature.selector));
        tea.transferWithAuthorization(alice.addr, bob.addr, 100, validAfter, validBefore, nonce, v, r, s);
        assertFalse(tea.authorizationState(alice.addr, nonce));
    }

    function test_receiveWithAuthorization_EOA_success() public {
        vm.warp(block.timestamp + 365 days);

        vm.prank(initialGovernor.addr);
        mintManager.mintTo(alice.addr, 1000);

        uint256 validAfter = block.timestamp - 1;
        uint256 validBefore = block.timestamp + 1000;
        bytes32 nonce = keccak256(abi.encodePacked("nonce7"));

        bytes32 messageHash = keccak256(
            abi.encode(
                tea.RECEIVE_WITH_AUTHORIZATION_TYPEHASH(),
                alice.addr,
                bob.addr,
                100,
                validAfter,
                validBefore,
                nonce
            ));

        bytes32 hash = MessageHashUtils.toTypedDataHash(tea.DOMAIN_SEPARATOR(), messageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alice, hash);

        // Bob (recipient) calls receiveWithAuthorization
        vm.prank(bob.addr);
        tea.receiveWithAuthorization(
            alice.addr,
            bob.addr,
            100,
            validAfter,
            validBefore,
            nonce,
            v,
            r,
            s
        );

        assertEq(tea.balanceOf(alice.addr), 900);
        assertEq(tea.balanceOf(bob.addr), 100);
        assertTrue(tea.authorizationState(alice.addr, nonce));
    }

    function test_receiveWithAuthorization_wrongCaller_fails() public {
        vm.warp(block.timestamp + 365 days);

        vm.prank(initialGovernor.addr);
        mintManager.mintTo(alice.addr, 1000);

        uint256 validAfter = block.timestamp - 1;
        uint256 validBefore = block.timestamp + 1000;
        bytes32 nonce = keccak256(abi.encodePacked("nonce8"));

        bytes32 messageHash = keccak256(
            abi.encode(
                tea.RECEIVE_WITH_AUTHORIZATION_TYPEHASH(),
                alice.addr,
                bob.addr,
                100,
                validAfter,
                validBefore,
                nonce
            ));

        bytes32 hash = MessageHashUtils.toTypedDataHash(tea.DOMAIN_SEPARATOR(), messageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alice, hash);

        // Alice tries to call (but should be bob as recipient)
        vm.prank(alice.addr);
        vm.expectRevert(
            abi.encodeWithSelector(EIP3009.EIP3009CallerMustBePayee.selector, alice.addr, bob.addr)
        );
        tea.receiveWithAuthorization(alice.addr, bob.addr, 100, validAfter, validBefore, nonce, v, r, s);
        assertFalse(tea.authorizationState(alice.addr, nonce));
    }

    function test_cancelAuthorization_EOA_success() public {
        bytes32 nonce = keccak256(abi.encodePacked("nonce9"));

        // Verify nonce is unused
        assertFalse(tea.authorizationState(alice.addr, nonce));

        bytes32 messageHash = keccak256(
            abi.encode(
                tea.CANCEL_AUTHORIZATION_TYPEHASH(),
                alice.addr,
                nonce
            ));

        bytes32 hash = MessageHashUtils.toTypedDataHash(tea.DOMAIN_SEPARATOR(), messageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alice, hash);

        // Cancel authorization
        tea.cancelAuthorization(alice.addr, nonce, v, r, s);

        // Verify nonce is now used
        assertTrue(tea.authorizationState(alice.addr, nonce));
    }

    function test_cancelAuthorization_ERC1271_success() public {
        bytes32 nonce = keccak256(abi.encodePacked("nonce10"));

        assertFalse(tea.authorizationState(address(smartWallet), nonce));

        bytes32 messageHash = keccak256(
            abi.encode(
                tea.CANCEL_AUTHORIZATION_TYPEHASH(),
                address(smartWallet),
                nonce
            ));

        bytes32 hash = MessageHashUtils.toTypedDataHash(tea.DOMAIN_SEPARATOR(), messageHash);
        
        // SECURITY: Sign the wrapped digest to prevent replay attacks
        bytes32 wrappedHash = smartWallet.getWrappedDigest(hash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(smartWalletOwner, wrappedHash);

        // Cancel authorization
        tea.cancelAuthorization(address(smartWallet), nonce, v, r, s);

        assertTrue(tea.authorizationState(address(smartWallet), nonce));
    }

    function test_cancelAuthorization_alreadyUsed_fails() public {
        bytes32 nonce = keccak256(abi.encodePacked("nonce11"));

        bytes32 messageHash = keccak256(
            abi.encode(
                tea.CANCEL_AUTHORIZATION_TYPEHASH(),
                alice.addr,
                nonce
            ));

        bytes32 hash = MessageHashUtils.toTypedDataHash(tea.DOMAIN_SEPARATOR(), messageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alice, hash);

        // First cancel succeeds
        tea.cancelAuthorization(alice.addr, nonce, v, r, s);
        assertTrue(tea.authorizationState(alice.addr, nonce));

        // Second cancel fails
        vm.expectRevert(abi.encodeWithSelector(EIP3009.EIP3009AuthorizationAlreadyUsed.selector, alice.addr, nonce));
        tea.cancelAuthorization(alice.addr, nonce, v, r, s);
    }

    function test_transferWithAuthorization_afterCancel_fails() public {
        vm.warp(block.timestamp + 365 days);

        vm.prank(initialGovernor.addr);
        mintManager.mintTo(alice.addr, 1000);

        uint256 validAfter = block.timestamp - 1;
        uint256 validBefore = block.timestamp + 1000;
        bytes32 nonce = keccak256(abi.encodePacked("nonce12"));

        // Cancel the authorization first
        bytes32 cancelHash = keccak256(
            abi.encode(
                tea.CANCEL_AUTHORIZATION_TYPEHASH(),
                alice.addr,
                nonce
            ));
        bytes32 cancelDigest = MessageHashUtils.toTypedDataHash(tea.DOMAIN_SEPARATOR(), cancelHash);
        (uint8 cv, bytes32 cr, bytes32 cs) = vm.sign(alice, cancelDigest);
        tea.cancelAuthorization(alice.addr, nonce, cv, cr, cs);
        assertTrue(tea.authorizationState(alice.addr, nonce));

        // Try to use the cancelled authorization
        bytes32 messageHash = keccak256(
            abi.encode(
                tea.TRANSFER_WITH_AUTHORIZATION_TYPEHASH(),
                alice.addr,
                bob.addr,
                100,
                validAfter,
                validBefore,
                nonce
            ));
        bytes32 hash = MessageHashUtils.toTypedDataHash(tea.DOMAIN_SEPARATOR(), messageHash);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alice, hash);

        vm.expectRevert(
            abi.encodeWithSelector(EIP3009.EIP3009AuthorizationAlreadyUsed.selector, alice.addr, nonce)
        );
        tea.transferWithAuthorization(alice.addr, bob.addr, 100, validAfter, validBefore, nonce, v, r, s);
    }

    // ============================================
    // Passkey Wallet Tests (7702/WebAuthn/Ed25519)
    // ============================================

    function test_passkey_permit_success() public {
        // Mint tokens to passkey wallet
        vm.warp(block.timestamp + 365 days);
        vm.prank(initialGovernor.addr);
        mintManager.mintTo(address(passkeyWallet), 1000);

        // Create permit digest
        bytes32 messageHash = keccak256(
            abi.encode(
                tea.PERMIT_TYPEHASH(),
                address(passkeyWallet),
                alice.addr,
                100,
                tea.nonces(address(passkeyWallet)),
                block.timestamp + 10000
            ));
        bytes32 digest = MessageHashUtils.toTypedDataHash(tea.DOMAIN_SEPARATOR(), messageHash);

        // Pre-approve the digest (simulates user confirming via biometrics)
        vm.prank(passkeyOwner.addr);
        passkeyWallet.approveDigest(digest);

        // Create passkey-style signature (non-ECDSA)
        bytes memory passkeySignature = abi.encodePacked(
            passkeyWallet.MAGIC_PREFIX(),
            bytes32(uint256(1)), // arbitrary passkey data
            bytes32(uint256(2))  // arbitrary passkey data
        );

        // Call permit with bytes signature
        tea.permit(
            address(passkeyWallet),
            alice.addr,
            100,
            block.timestamp + 10000,
            passkeySignature
        );

        assertEq(tea.allowance(address(passkeyWallet), alice.addr), 100, "Passkey permit should succeed");
    }

    function test_passkey_transferWithAuthorization_success() public {
        // Mint tokens to passkey wallet
        vm.warp(block.timestamp + 365 days);
        vm.prank(initialGovernor.addr);
        mintManager.mintTo(address(passkeyWallet), 1000);

        bytes32 nonce = bytes32(uint256(1));
        uint256 validAfter = block.timestamp - 1; // Past time
        uint256 validBefore = block.timestamp + 1000; // Future time

        // Create transfer authorization digest
        bytes32 messageHash = keccak256(
            abi.encode(
                tea.TRANSFER_WITH_AUTHORIZATION_TYPEHASH(),
                address(passkeyWallet),
                bob.addr,
                100,
                validAfter,
                validBefore,
                nonce
            ));
        bytes32 digest = MessageHashUtils.toTypedDataHash(tea.DOMAIN_SEPARATOR(), messageHash);

        // Pre-approve the digest
        vm.prank(passkeyOwner.addr);
        passkeyWallet.approveDigest(digest);

        // Create passkey-style signature
        bytes memory passkeySignature = abi.encodePacked(
            passkeyWallet.MAGIC_PREFIX(),
            bytes32(uint256(3)),
            bytes32(uint256(4))
        );

        // Call transferWithAuthorization with bytes signature
        tea.transferWithAuthorization(
            address(passkeyWallet),
            bob.addr,
            100,
            validAfter,
            validBefore,
            nonce,
            passkeySignature
        );

        assertEq(tea.balanceOf(address(passkeyWallet)), 900, "Balance should decrease");
        assertEq(tea.balanceOf(bob.addr), 100, "Bob should receive tokens");
        assertTrue(tea.authorizationState(address(passkeyWallet), nonce), "Nonce should be used");
    }

    function test_passkey_receiveWithAuthorization_success() public {
        // Mint tokens to passkey wallet
        vm.warp(block.timestamp + 365 days);
        vm.prank(initialGovernor.addr);
        mintManager.mintTo(address(passkeyWallet), 1000);

        bytes32 nonce = bytes32(uint256(2));
        uint256 validAfter = block.timestamp - 1; // Past time
        uint256 validBefore = block.timestamp + 1000; // Future time

        // Create receive authorization digest
        bytes32 messageHash = keccak256(
            abi.encode(
                tea.RECEIVE_WITH_AUTHORIZATION_TYPEHASH(),
                address(passkeyWallet),
                bob.addr,
                100,
                validAfter,
                validBefore,
                nonce
            ));
        bytes32 digest = MessageHashUtils.toTypedDataHash(tea.DOMAIN_SEPARATOR(), messageHash);

        // Pre-approve the digest
        vm.prank(passkeyOwner.addr);
        passkeyWallet.approveDigest(digest);

        // Create passkey-style signature
        bytes memory passkeySignature = abi.encodePacked(
            passkeyWallet.MAGIC_PREFIX(),
            bytes32(uint256(5)),
            bytes32(uint256(6))
        );

        // Bob calls receiveWithAuthorization with bytes signature
        vm.prank(bob.addr);
        tea.receiveWithAuthorization(
            address(passkeyWallet),
            bob.addr,
            100,
            validAfter,
            validBefore,
            nonce,
            passkeySignature
        );

        assertEq(tea.balanceOf(address(passkeyWallet)), 900);
        assertEq(tea.balanceOf(bob.addr), 100);
        assertTrue(tea.authorizationState(address(passkeyWallet), nonce), "Nonce should be used");
    }

    function test_passkey_cancelAuthorization_success() public {
        bytes32 nonce = bytes32(uint256(3));

        // Create cancel authorization digest
        bytes32 messageHash = keccak256(
            abi.encode(
                tea.CANCEL_AUTHORIZATION_TYPEHASH(),
                address(passkeyWallet),
                nonce
            ));
        bytes32 digest = MessageHashUtils.toTypedDataHash(tea.DOMAIN_SEPARATOR(), messageHash);

        // Pre-approve the digest
        vm.prank(passkeyOwner.addr);
        passkeyWallet.approveDigest(digest);

        // Create passkey-style signature
        bytes memory passkeySignature = abi.encodePacked(
            passkeyWallet.MAGIC_PREFIX(),
            bytes32(uint256(7)),
            bytes32(uint256(8))
        );

        // Cancel with bytes signature
        tea.cancelAuthorization(address(passkeyWallet), nonce, passkeySignature);

        assertTrue(tea.authorizationState(address(passkeyWallet), nonce), "Nonce should be marked as used");
    }

    function test_passkey_unapproved_digest_fails() public {
        // Try to use permit without pre-approving digest
        // (digest intentionally not approved to test failure)

        bytes memory passkeySignature = abi.encodePacked(
            passkeyWallet.MAGIC_PREFIX(),
            bytes32(uint256(9)),
            bytes32(uint256(10))
        );

        vm.prank(passkeyOwner.addr);
        vm.expectRevert();
        tea.permit(
            address(passkeyWallet),
            alice.addr,
            100,
            block.timestamp + 10000,
            passkeySignature
        );
        assertEq(tea.nonces(smartWalletOwner.addr), 0, "Nonce should not increment");
    }

    function test_passkey_invalid_signature_format_fails() public {
        // Create permit digest
        bytes32 messageHash = keccak256(
            abi.encode(
                tea.PERMIT_TYPEHASH(),
                address(passkeyWallet),
                alice.addr,
                100,
                tea.nonces(address(passkeyWallet)),
                block.timestamp + 10000
            ));
        bytes32 digest = MessageHashUtils.toTypedDataHash(tea.DOMAIN_SEPARATOR(), messageHash);

        // Pre-approve the digest
        vm.prank(passkeyOwner.addr);
        passkeyWallet.approveDigest(digest);


        // Create invalid signature (wrong prefix)
        bytes memory invalidSignature = abi.encodePacked(
            bytes32(uint256(999)), // wrong prefix
            bytes32(uint256(1)),
            bytes32(uint256(2))
        );

        vm.expectRevert();
        tea.permit(
            address(passkeyWallet),
            alice.addr,
            100,
            block.timestamp + 10000,
            invalidSignature
        );
        assertEq(tea.nonces(smartWalletOwner.addr), 0, "Nonce should not increment");
    }

    /**
     * @notice Test that ERC-1271 signature replay attack is prevented
     * @dev This test demonstrates the vulnerability described in:
     *      https://www.alchemy.com/blog/erc-1271-signature-replay-vulnerability
     * 
     * SCENARIO: Alice owns two smart wallets (wallet1 and wallet2) with the same EOA signer.
     * Without proper protection, a signature valid for wallet1 could be replayed on wallet2.
     * 
     * PROTECTION: Both wallets wrap incoming digests with their own domain separator,
     * making signatures specific to each wallet address.
     */
    function test_ERC1271_signature_replay_attack_prevented() public {
        // Create two wallets owned by the same EOA
        ERC1271Wallet wallet1 = new ERC1271Wallet(smartWalletOwner.addr);
        ERC1271Wallet wallet2 = new ERC1271Wallet(smartWalletOwner.addr);

        // Transfer tokens from initial supply to both wallets
        // (avoiding minting to keep test simple)
        vm.startPrank(initialGovernor.addr);
        tea.transfer(address(wallet1), 1000);
        tea.transfer(address(wallet2), 1000);
        vm.stopPrank();

        // Create a permit for wallet1
        bytes32 messageHash = keccak256(
            abi.encode(
                tea.PERMIT_TYPEHASH(),
                address(wallet1), // wallet1 as owner
                bob.addr,
                100,
                tea.nonces(address(wallet1)),
                block.timestamp + 10000
            ));

        bytes32 appDigest = MessageHashUtils.toTypedDataHash(tea.DOMAIN_SEPARATOR(), messageHash);

        // Sign with wallet1's wrapped digest
        bytes32 wallet1WrappedDigest = wallet1.getWrappedDigest(appDigest);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(smartWalletOwner, wallet1WrappedDigest);

        // The signature should work for wallet1
        vm.prank(smartWalletOwner.addr);
        tea.permit(
            address(wallet1),
            bob.addr,
            100,
            block.timestamp + 10000,
            v,
            r,
            s
        );

        assertEq(tea.allowance(address(wallet1), bob.addr), 100, "Wallet1 permit should succeed");
        assertEq(tea.nonces(address(wallet1)), 1, "Nonce should increment");

        // REPLAY ATTACK ATTEMPT: Try to use the same signature for wallet2
        // This should FAIL because wallet2 wraps the digest differently
        // We don't even need to create the correct message - the signature from wallet1 won't work

        // Try to replay the same signature (v, r, s) from wallet1 on wallet2
        // This should fail because wallet2 has a different domain separator
        vm.prank(smartWalletOwner.addr);
        vm.expectRevert(); // Signature verification should fail
        tea.permit(
            address(wallet2),
            bob.addr,
            100,
            block.timestamp + 10000,
            v,
            r,
            s
        );

        // Verify wallet2 allowance was NOT set (replay attack prevented)
        assertEq(tea.allowance(address(wallet2), bob.addr), 0, "Wallet2 permit should fail - replay attack prevented");
        assertEq(tea.nonces(address(wallet2)), 0, "Nonce should not increment");
    }
    
    // -------------------------- Recovery tests ----------------------------
    function test_recoverToken_onlyTimelock_reverts() public {
        Token_ERC20 token = new Token_ERC20();
        token.mint(address(tea), 1);

        // Call from a non-timelock address should revert
        vm.prank(initialGovernor.addr);
        vm.expectRevert();
        tea.recoverToken(address(token), 1);
    }

    function test_recoverToken_success_sendsToTreasury() public {
        Token_ERC20 token = new Token_ERC20();
        token.mint(address(tea), 1);

        // Call from timelock should succeed
        vm.prank(tea.timelock());
        tea.recoverToken(address(token), 1);

        assertEq(token.balanceOf(tea.TREASURY_SAFE()), 1);
        assertEq(token.balanceOf(address(tea)), 0);
    }

    function test_recoverToken_nonStandardToken_withSafeERC20_reverts() public {
        // This test documents what SHOULD happen with SafeERC20
        // (Currently will pass showing the silent failure, but with SafeERC20 it would revert as expected)
        
        NonStandardToken nonStandardToken = new NonStandardToken();
        nonStandardToken.mint(address(tea), 1000);
        nonStandardToken.setShouldFail(true);

        // With SafeERC20, this would expectRevert instead of succeeding silently
        // Uncomment below line when SafeERC20 is adopted:
        
        uint256 treasuryBalanceBefore = nonStandardToken.balanceOf(tea.TREASURY_SAFE());
        uint256 teaBalanceBefore = nonStandardToken.balanceOf(address(tea));

        vm.prank(tea.timelock());
        vm.expectRevert();
        tea.recoverToken(address(nonStandardToken), 1000);

        assertEq(nonStandardToken.balanceOf(address(tea)), teaBalanceBefore, "PROBLEM: Tokens should have moved but stayed in tea contract");
        assertEq(nonStandardToken.balanceOf(tea.TREASURY_SAFE()), treasuryBalanceBefore, "PROBLEM: Treasury should have received tokens but didn't");
    }

    function test_recoverNFT_onlyTimelock_reverts() public {
        Token_ERC721 nft = new Token_ERC721();
        nft.mint(address(tea), 1337);

        vm.prank(initialGovernor.addr);
        vm.expectRevert();
        tea.recoverNFT(address(nft), 1337);
    }

    function test_recoverNFT_success_transfers() public {
        Token_ERC721 nft = new Token_ERC721();
        nft.mint(address(tea), 2025);

        vm.prank(tea.timelock());
        tea.recoverNFT(address(nft), 2025);

        assertEq(nft.ownerOf(2025), tea.TREASURY_SAFE());
    }

    function test_recoverEth_onlyTimelock_reverts() public {
        // Non-timelock call should revert
        vm.prank(initialGovernor.addr);
        tea.transfer(address(tea), 1);

        vm.prank(initialGovernor.addr);
        vm.expectRevert();
        tea.sweepSelf(1);
    }

    function test_recoverEth_onlyTimelock_success_transfers() public {
        // Timelock can recover TEA
        vm.prank(initialGovernor.addr);
        tea.transfer(address(tea), 1);

        vm.prank(tea.timelock());
        tea.sweepSelf(1);

        assertEq(tea.balanceOf(tea.TREASURY_SAFE()), 1);
        assertEq(tea.balanceOf(address(tea)), 0);
    }

    function test_recoverNative_afterSelfDestruct() public {
        // Deploy mock that can selfdestruct
        SelfDestructingMock selfDestructingMock = new SelfDestructingMock();
    
        // Send some ETH to the mock contract
        uint256 amount = 1 ether;
        vm.deal(address(selfDestructingMock), amount);
        assertEq(address(selfDestructingMock).balance, amount);
    
        // Force-send ETH to tea token contract via selfdestruct
        selfDestructingMock.selfDestruct(payable(address(tea)));
        assertEq(address(tea).balance, amount);
    
        // Only timelock can recover
        vm.prank(initialGovernor.addr);
        vm.expectRevert(abi.encodeWithSelector(Tea.CallerIsNotTimelock.selector));
        tea.recoverNative(amount);

        // Recover the forced ETH transfer through timelock
        vm.prank(tea.timelock());
        tea.recoverNative(amount);
    
        assertEq(address(tea.TREASURY_SAFE()).balance, amount);
        assertEq(address(tea).balance, 0);
    }   

    function test_recoverNative_afterSelfDestruct_invalid_amount() public {
        // Deploy mock that can selfdestruct
        SelfDestructingMock selfDestructingMock = new SelfDestructingMock();
        address safe = tea.TREASURY_SAFE();
    
        // Send some ETH to the mock contract
        uint256 amount = 1 ether;
        vm.deal(address(selfDestructingMock), amount);
        assertEq(address(selfDestructingMock).balance, amount);
    
        // Force-send ETH to tea token contract via selfdestruct
        selfDestructingMock.selfDestruct(payable(address(tea)));
        assertEq(address(tea).balance, amount);
        
        // Recover too much the forced ETH transfer through timelock
        vm.prank(tea.timelock());
        vm.expectRevert(abi.encodeWithSelector(Tea.RecoverNativeFailed.selector, safe, amount * 2));
        tea.recoverNative(amount * 2);
    }

    function test_EIP5267_Domain() public {
        (
            ,
            string memory name,
            string memory version,
            uint256 chainId,
            address verifyingContract,
            bytes32 salt,
            uint256[] memory extensions
        ) = tea.eip712Domain();

        assertEq(name, tea.name());
        assertEq(version, "1");
        assertEq(chainId, block.chainid);
        assertEq(verifyingContract, address(tea));
        assertEq(salt, bytes32(0));
        assertEq(extensions.length, 0);
    }
}