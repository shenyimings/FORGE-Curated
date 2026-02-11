// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import { VmSafe } from "@prb/test/Vm.sol";
import { PRBTest } from "@prb/test/PRBTest.sol";
import { StdCheats } from "forge-std/StdCheats.sol";

import { Tea } from "../src/TeaToken/Tea.sol";
import { TokenDeploy } from "../src/TeaToken/TokenDeploy.sol";
import { MintManager } from "../src/TeaToken/MintManager.sol";
import { DeterministicDeployer } from "../src/utils/DeterministicDeployer.sol";

contract MintManager_Initializer is PRBTest, StdCheats {
    Tea internal tea;
    TokenDeploy internal tokenDeploy;
    MintManager internal mintManager;

    VmSafe.Wallet internal initialGovernor = vm.createWallet("Initial Gov Account");
    VmSafe.Wallet internal alice = vm.createWallet("Alice Account");
    VmSafe.Wallet internal bob = vm.createWallet("Bob Account");

    error OwnableUnauthorizedAccount(address account);

    /// @dev Sets up the test suite.
    function setUp() public {
        vm.createSelectFork({ urlOrAlias: "mainnet", blockNumber: 20_456_340 });
        bytes32 salt = keccak256(abi.encode(0x00, "tea"));
        tokenDeploy = TokenDeploy(
            DeterministicDeployer._deploy(salt, type(TokenDeploy).creationCode, abi.encode(initialGovernor.addr))
        );

        vm.prank(initialGovernor.addr);
        tokenDeploy.deploy(keccak256(abi.encode(0x01, salt)), keccak256(abi.encode(0x02, salt)), keccak256(abi.encode(0x03, salt)));

        tea = Tea(payable(tokenDeploy.tea()));
        mintManager = MintManager(tokenDeploy.mintManager());
    }
}

contract MintManager_constructor_Test is MintManager_Initializer {
    /// @dev Tests that the constructor properly configures the contract.
    function test_constructor_succeeds() external {
        assertEq(mintManager.owner(), initialGovernor.addr);
        assertEq(address(mintManager.tea()), address(tea));
        assertEq(tea.owner(), address(mintManager));
    }
}

contract MintManager_mint_Test is MintManager_Initializer {
    /// @dev Tests that the mint function properly mints tokens when called by the owner.
    function test_mint_fromOwner_succeeds() external {
        // Mint once.
        vm.warp(block.timestamp + 365 days);

        vm.prank(initialGovernor.addr);
        mintManager.mintTo(initialGovernor.addr, 100);

        // Token balance increases.
        assertEq(tea.balanceOf(initialGovernor.addr), tea.INITIAL_SUPPLY() + 100);
    }

    /// @dev Tests that the mint function reverts before the first year is over.
    function test_mint_fromOwner_reverts() external {
        vm.startPrank(initialGovernor.addr);
        vm.expectRevert("MintManager: minting not permitted yet");
        mintManager.mintTo(initialGovernor.addr, 100);
        vm.stopPrank();
        // Token balance increases.
        assertEq(tea.balanceOf(initialGovernor.addr), tea.INITIAL_SUPPLY());
    }

    /// @dev Tests that the mint function reverts when called by a non-owner.
    function test_mint_fromNotOwner_reverts() external {
        // Mint from alice.addr fails.
        vm.prank(alice.addr);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, alice.addr));
        mintManager.mintTo(initialGovernor.addr, 100);
    }

    /// @dev Tests that the mint function properly mints tokens when called by the owner a second
    ///      time after the mint period has elapsed.
    function test_mint_afterPeriodElapsed_succeeds() external {
        // Mint once.
        vm.warp(block.timestamp + 365 days);
        vm.prank(initialGovernor.addr);
        mintManager.mintTo(initialGovernor.addr, 100);

        // Token balance increases.
        assertEq(tea.balanceOf(initialGovernor.addr), tea.INITIAL_SUPPLY() + 100);

        // Mint again after period elapsed (2% max).
        vm.warp(block.timestamp + mintManager.MINT_PERIOD() + 1);
        vm.prank(initialGovernor.addr);
        mintManager.mintTo(initialGovernor.addr, 2_000_000_000 ether + 2);

        // Token balance increases.
        assertEq(tea.balanceOf(initialGovernor.addr), tea.INITIAL_SUPPLY() + 2_000_000_000 ether + 102);
    }

    /// @dev Tests that the mint function always reverts when called before the mint period has
    ///      elapsed, even if the caller is the owner.
    function test_mint_beforePeriodElapsed_reverts() external {
        // Mint once.
        vm.warp(block.timestamp + 365 days);
        vm.prank(initialGovernor.addr);
        mintManager.mintTo(initialGovernor.addr, 100);

        // Token balance increases.
        assertEq(tea.balanceOf(initialGovernor.addr), tea.INITIAL_SUPPLY() + 100);

        // Mint again.
        vm.prank(initialGovernor.addr);
        vm.expectRevert("MintManager: minting not permitted yet");
        mintManager.mintTo(initialGovernor.addr, 100);

        // Token balance does not increase.
        assertEq(tea.balanceOf(initialGovernor.addr), tea.INITIAL_SUPPLY() + 100);
    }

    /// @dev Tests that the owner cannot mint more than the mint cap.
    function test_mint_moreThanCap_reverts() external {
        // Mint once.
        vm.warp(block.timestamp + 365 days);
        vm.prank(initialGovernor.addr);
        mintManager.mintTo(initialGovernor.addr, 100);

        // Token balance increases.
        assertEq(tea.balanceOf(initialGovernor.addr), tea.INITIAL_SUPPLY() + 100);

        // Mint again (greater than 2% max).
        vm.warp(block.timestamp + mintManager.MINT_PERIOD() + 1);
        vm.prank(initialGovernor.addr);
        vm.expectRevert("MintManager: mint amount exceeds cap");
        mintManager.mintTo(initialGovernor.addr, 2_000_000_000 ether + 3);

        // Token balance does not increase.
        assertEq(tea.balanceOf(initialGovernor.addr), tea.INITIAL_SUPPLY() + 100);
    }

    function test_mint_multipleMints_withinPeriod_reverts() external {
        // First mint after 1 year
        vm.warp(block.timestamp + 365 days);
        vm.startPrank(initialGovernor.addr);

        // Mint 1% first
        uint256 onePercent = (tea.totalSupply() * 10) / mintManager.DENOMINATOR();
        mintManager.mintTo(initialGovernor.addr, onePercent);

        // Try to mint another 1% - should fail as the mint period has not elapsed
        uint256 onePointFivePercent = (tea.totalSupply() * 10) / mintManager.DENOMINATOR();
        vm.expectRevert("MintManager: minting not permitted yet");
        mintManager.mintTo(initialGovernor.addr, onePointFivePercent);
        vm.stopPrank();
    }

    function test_mint_exactlyAtPeriodBoundary_reverts() external {
        uint256 ts = block.timestamp;
        // First mint after 1 year
        vm.warp(ts + 365 days);
        vm.prank(initialGovernor.addr);
        mintManager.mintTo(initialGovernor.addr, 100);

        // Try minting exactly at mintPermittedAfter (should fail)
        vm.warp(ts + 365 days + mintManager.MINT_PERIOD() - 1);
        vm.prank(initialGovernor.addr);
        vm.expectRevert("MintManager: minting not permitted yet");
        mintManager.mintTo(initialGovernor.addr, 100);
    }

    function test_mint_exactlyAtCap_succeeds() external {
        vm.warp(block.timestamp + 365 days);
        vm.startPrank(initialGovernor.addr);

        // Calculate exact 2% of total supply
        uint256 exactCap = (tea.totalSupply() * mintManager.MINT_CAP()) / mintManager.DENOMINATOR();
        mintManager.mintTo(initialGovernor.addr, exactCap);

        // Verify balance increased by exactly 2%
        assertEq(tea.balanceOf(initialGovernor.addr), tea.INITIAL_SUPPLY() + exactCap);
        vm.stopPrank();
    }
}

contract MintManager_upgrade_Test is MintManager_Initializer {
    /// @dev Tests that the upgrade function reverts when called by a non-owner.
    function test_upgrade_fromNotOwner_reverts() external {
        // Upgrade from alice.addr fails.
        vm.prank(alice.addr);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, alice.addr));
        mintManager.upgrade(alice.addr);
    }

    /// @dev Tests that the upgrade function reverts when attempting to update to the zero
    ///      address, even if the caller is the owner.
    function test_upgrade_toZeroAddress_reverts() external {
        // Upgrade to zero address fails.
        vm.prank(initialGovernor.addr);
        vm.expectRevert("MintManager: mint manager cannot be the zero address");
        mintManager.upgrade(address(0));
    }

    /// @dev Tests that the owner can upgrade the mint mintManager.
    function test_upgrade_fromOwner_succeeds() external {
        // Upgrade to new mintManager
        vm.prank(initialGovernor.addr);
        mintManager.upgrade(alice.addr);

        // Check pending state
        assertEq(tea.owner(), address(mintManager));
        assertEq(tea.pendingOwner(), alice.addr);

        vm.prank(alice.addr);
        tea.acceptOwnership();

        // New manager is alice.addr
        assertEq(tea.owner(), alice.addr);
        assertEq(tea.pendingOwner(), address(0));
    }
}
