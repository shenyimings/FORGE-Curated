// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { Test, stdStorage, StdStorage, stdError } from "@forge-std/Test.sol";
import { BoringVault } from "src/base/BoringVault.sol";
import { DeployPortProofOfConceptScript } from "script/DeployPortProofOfConcept.s.sol";
import { SafeTransferLib } from "@solmate/utils/SafeTransferLib.sol";
import { FixedPointMathLib } from "@solmate/utils/FixedPointMathLib.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { AtomicSolverV3, AtomicQueue } from "src/atomic-queue/AtomicSolverV3.sol";

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
}
