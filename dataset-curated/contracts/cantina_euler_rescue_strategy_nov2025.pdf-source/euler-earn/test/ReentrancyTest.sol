// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.26;

import {IEulerEarn} from "../src/interfaces/IEulerEarn.sol";

import {ERC1820Registry} from "./mocks/ERC1820Registry.sol";
import {ERC777Mock, IERC1820Registry} from "./mocks/ERC777Mock.sol";
import {IERC1820Implementer} from "../lib/openzeppelin-contracts/contracts/interfaces/IERC1820Implementer.sol";
import {ReentrancyGuard} from "../lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

import "../src/EulerEarnFactory.sol";
import "./helpers/IntegrationTest.sol";

bytes32 constant TOKENS_SENDER_INTERFACE_HASH = keccak256("ERC777TokensSender");
bytes32 constant TOKENS_RECIPIENT_INTERFACE_HASH = keccak256("ERC777TokensRecipient");

contract ReentrancyTest is IntegrationTest, IERC1820Implementer {
    address internal attacker = makeAddr("attacker");

    ERC777Mock internal reentrantToken;
    ERC1820Registry internal registry;

    /// @dev Protected methods against reentrancy.
    enum ReenterMethod {
        None, // 0
        Redeem,
        Withdraw,
        Mint,
        Deposit,
        Reallocate,
        SubmitCap,
        SetFee,
        SetFeeRecipient
    }

    function setUp() public override {
        super.setUp();

        registry = new ERC1820Registry();

        registry.setInterfaceImplementer(address(this), TOKENS_SENDER_INTERFACE_HASH, address(this));
        registry.setInterfaceImplementer(address(this), TOKENS_RECIPIENT_INTERFACE_HASH, address(this));

        reentrantToken = new ERC777Mock(100_000, new address[](0), IERC1820Registry(address(registry)));

        IERC4626 idleVault = IERC4626(
            factory.createProxy(
                address(0), true, abi.encodePacked(address(reentrantToken), address(oracle), unitOfAccount)
            )
        );
        _toEVault(idleVault).setHookConfig(address(0), 0);
        perspective.perspectiveVerify(address(idleVault));

        vault = eeFactory.createEulerEarn(
            OWNER, TIMELOCK, address(reentrantToken), "EulerEarn Vault", "EEV", bytes32(uint256(2))
        );

        vm.startPrank(OWNER);
        vault.setCurator(CURATOR);
        vault.setIsAllocator(ALLOCATOR, true);
        vault.setFeeRecipient(FEE_RECIPIENT);
        vm.stopPrank();

        _setCap(idleVault, type(uint136).max);
        reentrantToken.approve(address(vault), type(uint256).max);
    }

    function test777Reentrancy() public {
        reentrantToken.setBalance(attacker, 100_000); // Mint 100_000 tokens to attacker.
        reentrantToken.setBalance(address(this), 100_000); // Mint 100_000 tokens to the test contract.

        vm.startPrank(attacker);

        registry.setInterfaceImplementer(attacker, TOKENS_SENDER_INTERFACE_HASH, address(this)); // Set test contract
        // to receive ERC-777 callbacks.
        registry.setInterfaceImplementer(attacker, TOKENS_RECIPIENT_INTERFACE_HASH, address(this)); // Required "hack"
        // because done all in a single Foundry test.

        reentrantToken.approve(address(vault), 100_000);

        vm.stopPrank();

        // The test will try to reenter on the deposit.

        vault.deposit(uint256(ReenterMethod.Redeem), attacker);
        vault.deposit(uint256(ReenterMethod.Withdraw), attacker);
        vault.deposit(uint256(ReenterMethod.Mint), attacker);
        vault.deposit(uint256(ReenterMethod.Deposit), attacker);
        vault.deposit(uint256(ReenterMethod.Reallocate), attacker);
        vault.deposit(uint256(ReenterMethod.SubmitCap), attacker);
        vault.deposit(uint256(ReenterMethod.SetFee), attacker);
        vault.deposit(uint256(ReenterMethod.SetFeeRecipient), attacker);
    }

    function tokensToSend(address, address, address, uint256 amount, bytes calldata, bytes calldata) external {
        if (amount == uint256(ReenterMethod.Deposit)) {
            vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
            vault.deposit(1, attacker);
        } else if (amount == uint256(ReenterMethod.Withdraw)) {
            vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
            vault.withdraw(1, attacker, attacker);
        } else if (amount == uint256(ReenterMethod.Mint)) {
            vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
            vault.mint(1, attacker);
        } else if (amount == uint256(ReenterMethod.Reallocate)) {
            MarketAllocation[] memory allocations;
            vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
            vault.reallocate(allocations);
        } else if (amount == uint256(ReenterMethod.Redeem)) {
            vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
            vault.redeem(1, attacker, attacker);
        } else if (amount == uint256(ReenterMethod.SubmitCap)) {
            vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
            vault.submitCap(IERC4626(address(1)), 1);
        } else if (amount == uint256(ReenterMethod.SetFee)) {
            vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
            vault.setFee(1);
        } else if (amount == uint256(ReenterMethod.SetFeeRecipient)) {
            vm.expectRevert(ReentrancyGuard.ReentrancyGuardReentrantCall.selector);
            vault.setFeeRecipient(address(1));
        }
    }

    function tokensReceived(
        address operator,
        address from,
        address to,
        uint256 amount,
        bytes calldata data,
        bytes calldata operatorData
    ) external {}

    function canImplementInterfaceForAddress(bytes32, address) external pure returns (bytes32) {
        // Required for ERC-777
        return keccak256(abi.encodePacked("ERC1820_ACCEPT_MAGIC"));
    }
}
