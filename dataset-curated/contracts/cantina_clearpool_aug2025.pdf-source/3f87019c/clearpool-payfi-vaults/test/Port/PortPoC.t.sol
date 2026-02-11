// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { Test, stdStorage, StdStorage, stdError } from "@forge-std/Test.sol";
import { BoringVault } from "src/base/BoringVault.sol";
import { DeployPortProofOfConceptScript } from "script/DeployPortProofOfConcept.s.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { FixedPointMathLib } from "@solmate/utils/FixedPointMathLib.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { AtomicSolverV3, AtomicQueue } from "src/atomic-queue/AtomicSolverV3.sol";
import { console2 } from "@forge-std/console2.sol";

/// @dev forge test --match-contract PortPoCTest
contract PortPoCTest is Test, DeployPortProofOfConceptScript {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    address public alice = makeAddr("alice");

    function setUp() external {
        uint256 forkId = vm.createFork(vm.envString("MAINNET_RPC_URL"));
        vm.selectFork(forkId);

        USDX = WETH;
        run();

        vm.prank(hexTrust);
        teller.setDepositCap(type(uint256).max);
        vm.stopPrank();
    }

    function test_CanArbitrarilyRemoveFunds() external {
        uint256 amount = 100e18;
        deal(address(WETH), address(boringVault), amount);

        vm.startPrank(hexTrust);
        address target = address(WETH);
        bytes memory data = abi.encodeCall(ERC20.transfer, (hexTrust, amount));
        uint256 value;
        boringVault.manage(target, data, value);
        vm.stopPrank();
    }

    /*
    First
    1. Deposit - LP
    2. Borrow - Borrower / strategy executor
    3. Withdrawal request - LP
    4. NAV setting - Borrower / strategy executor
    5. Repay - Borrower / strategy executor - P2P path
    Cross check accruals (NAV vs Withdraw)
    */
    function test_FirstFlow() external {
        uint256 amount = 100e18;
        deal(address(WETH), address(alice), amount);

        /// 1. Deposit - LP
        vm.startPrank(alice);
        WETH.approve(address(boringVault), amount);
        uint256 aliceShares = teller.deposit(WETH, amount, 0);
        vm.stopPrank();

        /// 2. Borrow - Borrower / strategy executor
        vm.startPrank(hexTrust);
        address target = address(WETH);
        bytes memory data = abi.encodeCall(ERC20.transfer, (hexTrust, amount));
        uint256 value;
        boringVault.manage(target, data, value);
        vm.stopPrank();

        /// 3. Withdrawal request - LP
        vm.startPrank(alice);
        AtomicQueue.AtomicRequest memory req = AtomicQueue.AtomicRequest({
            deadline: uint64(block.timestamp + 1 days),
            offerAmount: uint96(aliceShares),
            inSolve: false
        });
        boringVault.approve(address(atomicQueue), aliceShares);
        atomicQueue.updateAtomicRequest(boringVault, WETH, req.deadline, req.offerAmount);
        vm.stopPrank();

        /// 4. NAV setting - Borrower / strategy executor
        /// 5. Repay - Borrower / strategy executor - P2P path
        vm.startPrank(hexTrust);
        WETH.approve(address(atomicSolverV3), amount);
        address[] memory users = new address[](1);
        users[0] = alice;
        atomicSolverV3.p2pSolve(atomicQueue, boringVault, WETH, users, 0, type(uint256).max);
        vm.stopPrank();

        /// Cross check accruals (NAV vs Withdraw)
        assertEq(WETH.balanceOf(address(boringVault)), 0);
        assertEq(WETH.balanceOf(alice), amount);
    }

    /*
    Second
    6. Deposit - LP
    7. Borrow - Borrower / strategy executor
    8. Nav Setting - Borrower / strategy executor
    9. Withdrawal request in diff currency LP - REDEEM path
    10. Repay - Borrower / strategy executor - REDEEM path
    11. Cross check accruals (NAV vs Withdraw)
    */
    function test_SecondFlow() external {
        uint256 amount = 100e18;
        deal(address(WETH), address(alice), amount);

        /// 6. Deposit - LP
        vm.startPrank(alice);
        WETH.approve(address(boringVault), amount);
        uint256 aliceShares = teller.deposit(WETH, amount, 0);
        vm.stopPrank();

        /// 7. Borrow - Borrower / strategy executor
        vm.startPrank(hexTrust);
        address target = address(WETH);
        bytes memory data = abi.encodeCall(ERC20.transfer, (hexTrust, amount));
        uint256 value;
        boringVault.manage(target, data, value);
        vm.stopPrank();

        /// 8. Nav Setting - Borrower / strategy executor
        vm.prank(hexTrust);
        WETH.transfer(address(boringVault), amount);

        /// 9. Withdrawal request in diff currency LP - REDEEM path
        /// Wrong request
        vm.startPrank(alice);
        AtomicQueue.AtomicRequest memory req = AtomicQueue.AtomicRequest({
            deadline: uint64(block.timestamp + 1 days),
            offerAmount: uint96(aliceShares),
            inSolve: false
        });
        boringVault.approve(address(atomicQueue), aliceShares);
        atomicQueue.updateAtomicRequest(boringVault, ERC20(address(69)), req.deadline, req.offerAmount);
        vm.stopPrank();

        /// Should fail
        vm.startPrank(hexTrust);
        WETH.approve(address(atomicSolverV3), amount);
        address[] memory users = new address[](1);
        users[0] = alice;
        vm.expectRevert();
        atomicSolverV3.redeemSolve(atomicQueue, boringVault, WETH, users, 0, type(uint256).max, teller);
        vm.stopPrank();

        /// 10. Repay - Borrower / strategy executor - REDEEM path
        /// Right request
        vm.startPrank(alice);
        req = AtomicQueue.AtomicRequest({
            deadline: uint64(block.timestamp + 1 days),
            offerAmount: uint96(aliceShares),
            inSolve: false
        });
        boringVault.approve(address(atomicQueue), aliceShares);
        atomicQueue.updateAtomicRequest(boringVault, ERC20(WETH), req.deadline, req.offerAmount);
        vm.stopPrank();

        /// Should suceed
        vm.startPrank(hexTrust);
        atomicSolverV3.redeemSolve(atomicQueue, boringVault, WETH, users, 0, type(uint256).max, teller);
        vm.stopPrank();

        /// Cross check accruals (NAV vs Withdraw)
        assertEq(WETH.balanceOf(address(boringVault)), 0);
        assertEq(WETH.balanceOf(alice), amount);
    }

    /**
     * @notice Test that failed solver transfers revert entire transaction
     */
    function test_SolverTransferFailureRevertsAll() external {
        uint256 amount = 100e18;
        deal(address(WETH), address(alice), amount);

        // Alice deposits
        vm.startPrank(alice);
        WETH.approve(address(boringVault), amount);
        uint256 aliceShares = teller.deposit(WETH, amount, 0);
        vm.stopPrank();

        // Create withdrawal request
        vm.startPrank(alice);
        AtomicQueue.AtomicRequest memory req = AtomicQueue.AtomicRequest({
            deadline: uint64(block.timestamp + 1 days),
            offerAmount: uint96(aliceShares),
            inSolve: false
        });
        boringVault.approve(address(atomicQueue), aliceShares);
        atomicQueue.updateAtomicRequest(boringVault, WETH, req.deadline, req.offerAmount);
        vm.stopPrank();

        // Solver attempts to solve but doesn't have enough WETH
        address poorSolver = makeAddr("poorSolver");
        deal(address(WETH), poorSolver, amount / 2); // Only half the needed amount

        vm.startPrank(poorSolver);
        WETH.approve(address(atomicSolverV3), amount); // Approve more than they have

        address[] memory users = new address[](1);
        users[0] = alice;

        // Should revert because solver doesn't have enough WETH
        vm.expectRevert(); // SafeTransferLib will revert on insufficient balance
        atomicSolverV3.p2pSolve(atomicQueue, boringVault, WETH, users, 0, type(uint256).max);
        vm.stopPrank();

        // Verify nothing changed - Alice still has her shares
        assertEq(boringVault.balanceOf(alice), aliceShares);
        assertEq(WETH.balanceOf(alice), 0);

        // Verify request is still active (not marked as inSolve)
        AtomicQueue.AtomicRequest memory requestAfter = atomicQueue.getUserAtomicRequest(alice, boringVault, WETH);
        assertEq(requestAfter.offerAmount, uint96(aliceShares));
        assertFalse(requestAfter.inSolve);
    }

    // /**
    //  * @notice Test multiple asset withdrawals after 30 days with interest accrual
    //  */
    // function test_MultiAssetWithdrawalWithInterest() external {
    //     // Setup: Add USDC and DAI as supported assets
    //     address USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    //     address DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    //     // Set rate providers for USDC and DAI (both pegged to base)
    //     vm.startPrank(hexTrust);
    //     accountant.setRateProviderData(ERC20(USDC), true, address(0)); // Pegged 1:1
    //     accountant.setRateProviderData(ERC20(DAI), true, address(0)); // Pegged 1:1
    //     teller.addAsset(ERC20(USDC));
    //     teller.addAsset(ERC20(DAI));

    //     // Set lending rate to 10% APY (1000 basis points)
    //     accountant.setLendingRate(1000);
    //     vm.stopPrank();

    //     // Alice deposits USDC
    //     uint256 usdcAmount = 1000e6; // 1000 USDC
    //     deal(USDC, alice, usdcAmount);

    //     vm.startPrank(alice);
    //     ERC20(USDC).approve(address(boringVault), usdcAmount);
    //     uint256 aliceSharesFromUSDC = teller.deposit(ERC20(USDC), usdcAmount, 0);
    //     vm.stopPrank();

    //     // Bob deposits DAI
    //     address bob = makeAddr("bob");
    //     uint256 daiAmount = 2000e18; // 2000 DAI
    //     deal(DAI, bob, daiAmount);

    //     vm.startPrank(bob);
    //     ERC20(DAI).approve(address(boringVault), daiAmount);
    //     uint256 bobSharesFromDAI = teller.deposit(ERC20(DAI), daiAmount, 0);
    //     vm.stopPrank();

    //     // Borrower takes out funds
    //     vm.startPrank(hexTrust);
    //     boringVault.manage(USDC, abi.encodeCall(ERC20.transfer, (hexTrust, usdcAmount)), 0);
    //     boringVault.manage(DAI, abi.encodeCall(ERC20.transfer, (hexTrust, daiAmount)), 0);
    //     vm.stopPrank();

    //     // Fast forward 30 days
    //     vm.warp(block.timestamp + 30 days);

    //     // Get the actual rate after interest accrual
    //     uint256 currentRate = accountant.getRate();
    //     console2.log("Current rate after 30 days:");
    //     console2.log(currentRate);

    //     // Calculate expected amounts based on shares and current rate
    //     // Alice's USDC: shares * rate / 1e18, then convert to USDC decimals
    //     uint256 aliceValueIn18 = aliceSharesFromUSDC.mulDivDown(currentRate, 1e18);
    //     uint256 expectedUSDCAmount = aliceValueIn18 / 1e12; // Convert from 18 to 6 decimals

    //     // Bob's DAI: shares * rate / 1e18 (DAI is already 18 decimals)
    //     uint256 bobValueIn18 = bobSharesFromDAI.mulDivDown(currentRate, 1e18);
    //     uint256 expectedDAIAmount = bobValueIn18; // DAI is 18 decimals

    //     console2.log("Expected USDC for Alice:");
    //     console2.log(expectedUSDCAmount);
    //     console2.log("Expected DAI for Bob:");
    //     console2.log(expectedDAIAmount);

    //     // Create withdrawal requests
    //     vm.startPrank(alice);
    //     boringVault.approve(address(atomicQueue), aliceSharesFromUSDC);
    //     atomicQueue.updateAtomicRequest(
    //         boringVault, ERC20(USDC), uint64(block.timestamp + 1 days), uint96(aliceSharesFromUSDC)
    //     );
    //     vm.stopPrank();

    //     vm.startPrank(bob);
    //     boringVault.approve(address(atomicQueue), bobSharesFromDAI);
    //     atomicQueue.updateAtomicRequest(
    //         boringVault, ERC20(DAI), uint64(block.timestamp + 1 days), uint96(bobSharesFromDAI)
    //     );
    //     vm.stopPrank();

    //     // Borrower repays with interest (add some buffer for rounding)
    //     uint256 usdcToRepay = expectedUSDCAmount + 10; // Add small buffer
    //     uint256 daiToRepay = expectedDAIAmount + 1e10; // Add small buffer

    //     deal(USDC, hexTrust, usdcToRepay);
    //     deal(DAI, hexTrust, daiToRepay);

    //     // Process USDC withdrawal
    //     vm.startPrank(hexTrust);
    //     ERC20(USDC).approve(address(atomicSolverV3), usdcToRepay);
    //     address[] memory usersUSDC = new address[](1);
    //     usersUSDC[0] = alice;
    //     atomicSolverV3.p2pSolve(atomicQueue, boringVault, ERC20(USDC), usersUSDC, 0, type(uint256).max);
    //     vm.stopPrank();

    //     // Process DAI withdrawal
    //     vm.startPrank(hexTrust);
    //     ERC20(DAI).approve(address(atomicSolverV3), daiToRepay);
    //     address[] memory usersDAI = new address[](1);
    //     usersDAI[0] = bob;
    //     atomicSolverV3.p2pSolve(atomicQueue, boringVault, ERC20(DAI), usersDAI, 0, type(uint256).max);
    //     vm.stopPrank();

    //     // Verify withdrawals include interest
    //     uint256 aliceUSDCBalance = ERC20(USDC).balanceOf(alice);
    //     uint256 bobDAIBalance = ERC20(DAI).balanceOf(bob);

    //     console2.log("Alice USDC received:");
    //     console2.log(aliceUSDCBalance);
    //     console2.log("Bob DAI received:");
    //     console2.log(bobDAIBalance);

    //     // Alice should receive ~1008.2 USDC (1000 + interest)
    //     assertGt(aliceUSDCBalance, usdcAmount, "Alice should receive interest on USDC");

    //     // Bob should receive ~2016.4 DAI (2000 + interest)
    //     assertGt(bobDAIBalance, daiAmount, "Bob should receive interest on DAI");

    //     // Verify vault is empty
    //     assertEq(ERC20(USDC).balanceOf(address(boringVault)), 0, "Vault should have no USDC");
    //     assertEq(ERC20(DAI).balanceOf(address(boringVault)), 0, "Vault should have no DAI");
    // }
}
