// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {console} from "forge-std/Test.sol";

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

import {IBoringOnChainQueue} from "src/interfaces/ggv/IBoringOnChainQueue.sol";
import {IBoringSolver} from "src/interfaces/ggv/IBoringSolver.sol";
import {ITellerWithMultiAssetSupport} from "src/interfaces/ggv/ITellerWithMultiAssetSupport.sol";

import {StvStrategyPoolHarness} from "test/utils/StvStrategyPoolHarness.sol";

import {StvStETHPool} from "src/StvStETHPool.sol";
import {WithdrawalQueue} from "src/WithdrawalQueue.sol";
import {IStrategy} from "src/interfaces/IStrategy.sol";
import {IStrategyCallForwarder} from "src/interfaces/IStrategyCallForwarder.sol";
import {GGVStrategy} from "src/strategy/GGVStrategy.sol";

import {TableUtils} from "../utils/format/TableUtils.sol";
import {AllowList} from "src/AllowList.sol";
import {GGVMockTeller} from "src/mock/ggv/GGVMockTeller.sol";
import {GGVQueueMock} from "src/mock/ggv/GGVQueueMock.sol";
import {GGVVaultMock} from "src/mock/ggv/GGVVaultMock.sol";

interface IAuthority {
    function setUserRole(address user, uint8 role, bool enabled) external;
    function setRoleCapability(uint8 role, address code, bytes4 sig, bool enabled) external;
    function owner() external view returns (address);
    function canCall(address caller, address code, bytes4 sig) external view returns (bool);
    function doesRoleHaveCapability(uint8 role, address code, bytes4 sig) external view returns (bool);
    function doesUserHaveRole(address user, uint8 role) external view returns (bool);
    function getUserRoles(address user) external view returns (bytes32);
    function getRolesWithCapability(address code, bytes4 sig) external view returns (bytes32);
}

interface IAccountant {
    function setRateProviderData(ERC20 asset, bool isPeggedToBase, address rateProvider) external;
}

contract GGVTest is StvStrategyPoolHarness {
    using SafeCast for uint256;
    using TableUtils for TableUtils.Context;

    TableUtils.Context private _log;

    address public constant ADMIN = address(0x1337);
    address public constant SOLVER = address(0x1338);

    uint8 public constant OWNER_ROLE = 8;
    uint8 public constant MULTISIG_ROLE = 9;
    uint8 public constant STRATEGIST_MULTISIG_ROLE = 10;
    uint8 public constant SOLVER_ORIGIN_ROLE = 33;

    // Use local mocks for teller/on-chain queue/solver in integration tests
    //    ITellerWithMultiAssetSupport public teller;
    //    IBoringOnChainQueue public boringOnChainQueue;
    //    IBoringSolver public solver;

    ITellerWithMultiAssetSupport public teller;
    IBoringOnChainQueue public boringOnChainQueue;
    IBoringSolver public solver;

    StvStETHPool public pool;
    WithdrawalQueue public withdrawalQueue;

    GGVStrategy public ggvStrategy;
    GGVVaultMock public boringVault;

    address WSTETH = address(0); // unused with mocks

    TableUtils.User[] public logUsers;

    WrapperContext public ctx;

    address public user1StrategyCallForwarder;
    address public user2StrategyCallForwarder;

    function setUp() public {
        _initializeCore();

        vm.deal(ADMIN, 100_000 ether);
        vm.deal(SOLVER, 100_000 ether);

        boringVault = new GGVVaultMock(ADMIN, address(steth), address(wsteth));
        teller = GGVMockTeller(address(boringVault.TELLER()));
        boringOnChainQueue = GGVQueueMock(address(boringVault.BORING_QUEUE()));

        ctx = _deployStvStETHPool(true, 0, 0, address(teller), address(boringOnChainQueue));
        pool = StvStETHPool(payable(ctx.pool));
        vm.label(address(pool), "WrapperProxy");

        strategy = IStrategy(ctx.strategy);
        ggvStrategy = GGVStrategy(address(strategy));

        user1StrategyCallForwarder = address(ggvStrategy.getStrategyCallForwarderAddress(USER1));
        vm.label(user1StrategyCallForwarder, "User1StrategyCallForwarder");

        user2StrategyCallForwarder = address(ggvStrategy.getStrategyCallForwarderAddress(USER2));
        vm.label(user2StrategyCallForwarder, "User2StrategyCallForwarder");

        _log.init(address(pool), address(boringVault), address(steth), address(wsteth), address(boringOnChainQueue));

        vm.startPrank(ADMIN);
        steth.submit{value: 10 ether}(ADMIN);
        steth.approve(address(boringVault), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(SOLVER);
        uint256 solverSteth = steth.submit{value: 2 ether}(SOLVER);
        steth.approve(address(wsteth), type(uint256).max);
        uint256 solverWsteth = wsteth.wrap(solverSteth);
        assertTrue(wsteth.transfer(address(boringVault), solverWsteth));
        vm.stopPrank();

        withdrawalQueue = pool.WITHDRAWAL_QUEUE();

        // Skip external GGV mainnet setup when using local mocks
        // _setupGGV();
    }

    function _setupGGV() public {
        address tellerAuthority = teller.authority();

        IAuthority authority = IAuthority(tellerAuthority);
        address authorityOwner = authority.owner();

        IAccountant accountant = IAccountant(teller.accountant());

        vm.startPrank(authorityOwner);
        authority.setUserRole(address(this), OWNER_ROLE, true);
        authority.setUserRole(address(this), STRATEGIST_MULTISIG_ROLE, true);
        authority.setUserRole(address(this), MULTISIG_ROLE, true);
        authority.setUserRole(address(this), SOLVER_ORIGIN_ROLE, true);
        vm.stopPrank();

        teller.updateAssetData(ERC20(address(core.steth())), true, true, 0);
        accountant.setRateProviderData(ERC20(address(core.steth())), true, address(0));
        boringOnChainQueue.updateWithdrawAsset(address(core.steth()), 0, 604800, 1, 9, 0);

        console.log("setup GGV finished\n");
    }

    function test_revert_if_user_is_not_allowlisted() public {
        uint256 depositAmount = 1 ether;
        vm.prank(USER1);
        vm.expectRevert(abi.encodeWithSelector(AllowList.NotAllowListed.selector, USER1));
        pool.depositETH{value: depositAmount}(USER1, address(0));
    }

    function test_rebase_scenario() public {
        uint256 stethIncrease = 0;
        uint256 vaultIncrease = 0;
        uint256 ggvDiscount = 1;

        uint256 depositAmount = 1 ether;
        uint256 vaultProfit = depositAmount * vaultIncrease / 100; // 0.05 ether profit

        logUsers.push(TableUtils.User(USER1, "user1"));
        logUsers.push(TableUtils.User(user1StrategyCallForwarder, "user1_forwarder"));
        logUsers.push(TableUtils.User(address(pool), "pool"));
        logUsers.push(TableUtils.User(address(pool.WITHDRAWAL_QUEUE()), "wq"));
        logUsers.push(TableUtils.User(address(boringVault), "boringVault"));
        logUsers.push(TableUtils.User(address(boringOnChainQueue), "boringVaultQueue"));

        // Apply 1% increase to core (stETH share ratio)
        core.increaseBufferedEther(steth.totalSupply() * stethIncrease / 100);
        console.log("INITIAL share rate %s", steth.getPooledEthByShares(1e18));

        _log.printUsers("[SCENARIO] Initial State", logUsers, ggvDiscount);

        // 1. Initial Deposit

        uint256 wstethToMint = pool.remainingMintingCapacitySharesOf(USER1, depositAmount);

        vm.prank(USER1);
        ggvStrategy.supply{value: depositAmount}(address(0), wstethToMint, abi.encode(GGVStrategy.GGVParamsSupply(0)));

        _log.printUsers("[SCENARIO] After Deposit (1 ETH)", logUsers, ggvDiscount);

        uint256 userMintedStethSharesAfterDeposit = ggvStrategy.mintedStethSharesOf(USER1);

        //         3. Request withdrawal (full amount, based on appreciated value)
        uint256 totalGgvShares = boringVault.balanceOf(user1StrategyCallForwarder);
        uint256 withdrawalWstethAmount =
            boringOnChainQueue.previewAssetsOut(address(wsteth), totalGgvShares.toUint128(), ggvDiscount.toUint16());

        console.log("\n[SCENARIO] Requesting withdrawal based on new appreciated assets:", withdrawalWstethAmount);

        GGVStrategy.GGVParamsRequestExit memory params =
            GGVStrategy.GGVParamsRequestExit({discount: ggvDiscount.toUint16(), secondsToDeadline: type(uint24).max});

        vm.prank(USER1);
        bytes32 requestId = ggvStrategy.requestExitByWsteth(withdrawalWstethAmount, abi.encode(params));
        assertNotEq(requestId, 0);

        // Apply 1% increase to core (stETH share ratio)
        core.increaseBufferedEther(steth.totalSupply() * 1 / 100);
        uint256 shareRate3 = steth.getPooledEthByShares(1e18);

        console.log("\n[SCENARIO] apply new stETH rebase shareRate after request, before ggv solve:", shareRate3);

        _log.printUsers("[SCENARIO] After Request Withdrawal", logUsers, ggvDiscount);

        // 4. Solve GGV requests (Simulate GGV Solver)
        console.log("\n[SCENARIO] Step 4. Solve GGV requests");

        IBoringOnChainQueue.OnChainWithdraw memory req =
            GGVQueueMock(address(boringOnChainQueue)).mockGetRequestById(requestId);
        IBoringOnChainQueue.OnChainWithdraw[] memory requests = new IBoringOnChainQueue.OnChainWithdraw[](1);
        requests[0] = req;

        vm.warp(block.timestamp + req.secondsToMaturity + 1);
        boringOnChainQueue.solveOnChainWithdraws(requests, new bytes(0), address(0));

        _log.printUsers("After GGV Solver", logUsers, ggvDiscount);

        // 5. User Finalizes Withdrawal (Wrapper side)
        console.log("\n[SCENARIO] Step 5. Finalize Wrapper withdrawal");

        // simulate the unwrapping of wstETH to stETH with rounding issue
        uint256 wstethUserBalance = ggvStrategy.wstethOf(USER1);
        assertGt(
            userMintedStethSharesAfterDeposit,
            wstethUserBalance,
            "user minted steth shares should be greater than wsteth balance"
        );

        uint256 mintedStethShares = ggvStrategy.mintedStethSharesOf(USER1);
        uint256 wstethToBurn = Math.min(mintedStethShares, wstethUserBalance);

        uint256 stETHAmount = steth.getPooledEthByShares(wstethToBurn);
        uint256 sharesAfterUnwrapping = steth.getSharesByPooledEth(stETHAmount);

        uint256 stethSharesToRebalance = 0;
        if (mintedStethShares > sharesAfterUnwrapping) {
            stethSharesToRebalance = mintedStethShares - sharesAfterUnwrapping;
        }

        uint256 stvToWithdraw = ggvStrategy.stvOf(USER1);

        vm.startPrank(USER1);
        ggvStrategy.burnWsteth(wstethToBurn);
        ggvStrategy.requestWithdrawalFromPool(USER1, stvToWithdraw, stethSharesToRebalance);
        vm.stopPrank();

        _log.printUsers("After User Finalizes Wrapper", logUsers, ggvDiscount);

        // 6. Node Operator Finalizes WQ (Node Operator side)
        console.log("\n[SCENARIO] Step 6. Finalize WQ (Node Operator)");

        vm.deal(address(ctx.vault), 10 ether);
        _finalizeWQ(1, vaultProfit);

        _log.printUsers("After WQ Finalized", logUsers, ggvDiscount);

        // 7. User Claims ETH
        console.log("\n[SCENARIO] Step 7. Claim final ETH");
        uint256 userBalanceBeforeClaim = USER1.balance;

        uint256[] memory wqRequestIds = withdrawalQueue.withdrawalRequestsOf(USER1);

        //  console.log("requestIds length", wqRequestIds[0]);

        vm.prank(USER1);
        withdrawalQueue.claimWithdrawal(USER1, wqRequestIds[0]);

        uint256 ethClaimed = USER1.balance - userBalanceBeforeClaim;
        console.log("ETH Claimed:", ethClaimed);

        _log.printUsers("After User Claims ETH", logUsers, ggvDiscount);
    }

    function test_positive_wsteth_rebase_flow() public {
        uint256 depositAmount = 1 ether;
        uint16 discount = 0;

        uint256 wstethToMint = pool.remainingMintingCapacitySharesOf(USER1, depositAmount);

        vm.prank(USER1);
        ggvStrategy.supply{value: depositAmount}(address(0), wstethToMint, abi.encode(GGVStrategy.GGVParamsSupply(0)));

        uint256 mintedSharesBefore = ggvStrategy.mintedStethSharesOf(USER1);
        assertEq(mintedSharesBefore, wstethToMint, "minted shares mismatch");

        IStrategyCallForwarder callForwarder = ggvStrategy.getStrategyCallForwarderAddress(USER1);
        uint256 totalGGVShares = boringVault.balanceOf(address(callForwarder));

        // Simulate GGV rewards
        uint256 rebaseStethAmount = 0.1 ether;
        vm.startPrank(ADMIN);
        steth.approve(address(wsteth), type(uint256).max);
        uint256 rebaseWstethAmount = wsteth.wrap(rebaseStethAmount);
        wsteth.approve(address(boringVault), type(uint256).max);
        boringVault.rebaseWsteth(rebaseWstethAmount);
        vm.stopPrank();

        uint128 withdrawSharesPreview =
            boringOnChainQueue.previewAssetsOut(address(wsteth), totalGGVShares.toUint128(), discount);

        GGVStrategy.GGVParamsRequestExit memory params =
            GGVStrategy.GGVParamsRequestExit({discount: discount, secondsToDeadline: type(uint24).max});

        vm.prank(USER1);
        bytes32 requestId = ggvStrategy.requestExitByWsteth(uint256(withdrawSharesPreview), abi.encode(params));

        IBoringOnChainQueue.OnChainWithdraw memory request =
            GGVQueueMock(address(boringOnChainQueue)).mockGetRequestById(requestId);
        IBoringOnChainQueue.OnChainWithdraw[] memory requests = new IBoringOnChainQueue.OnChainWithdraw[](1);
        requests[0] = request;

        vm.prank(SOLVER);
        boringOnChainQueue.solveOnChainWithdraws(requests, new bytes(0), address(0));

        uint256 wstethAfterSolve = ggvStrategy.wstethOf(USER1);
        assertGt(wstethAfterSolve, mintedSharesBefore, "wstETH returned should exceed supplied amount");

        uint256 stvBalance = ggvStrategy.stvOf(USER1);

        vm.startPrank(USER1);
        ggvStrategy.burnWsteth(mintedSharesBefore);

        uint256 remainingLiability = ggvStrategy.mintedStethSharesOf(USER1);
        uint256 leftoverWsteth = ggvStrategy.wstethOf(USER1);
        ggvStrategy.requestWithdrawalFromPool(USER1, stvBalance, remainingLiability);
        vm.stopPrank();

        assertGt(leftoverWsteth, 0, "surplus wstETH expected after covering liability");

        _finalizeWQ(1, 0);

        uint256[] memory wqRequestIds = withdrawalQueue.withdrawalRequestsOf(USER1);
        uint256 userEthBefore = USER1.balance;

        vm.prank(USER1);
        withdrawalQueue.claimWithdrawal(USER1, wqRequestIds[0]);

        assertGt(USER1.balance - userEthBefore, 0, "user should receive ETH on claim");

        uint256 recoverableWsteth = ggvStrategy.wstethOf(USER1);
        assertEq(recoverableWsteth, leftoverWsteth, "unexpected wstETH balance on strategy");

        uint256 userWstethBefore = wsteth.balanceOf(USER1);

        vm.prank(USER1);
        ggvStrategy.safeTransferERC20(address(wsteth), USER1, recoverableWsteth);

        assertEq(ggvStrategy.wstethOf(USER1), 0, "strategy call forwarder should have no wstETH left");
        assertEq(
            wsteth.balanceOf(USER1) - userWstethBefore, recoverableWsteth, "user must receive recovered wstETH amount"
        );
    }

    function test_supply_zeroWstethToMint_doesNotRevert() public {
        vm.skip(true); // There is a bug in the GGVStrategy not yet to be fixed

        uint256 depositAmount = 1 ether;
        uint256 wstethToMint = 0;

        IStrategyCallForwarder callForwarder = ggvStrategy.getStrategyCallForwarderAddress(USER1);

        uint256 mintedSharesBefore = ggvStrategy.mintedStethSharesOf(USER1);
        uint256 wstethBalanceBefore = wsteth.balanceOf(address(callForwarder));
        uint256 ggvSharesBefore = boringVault.balanceOf(address(callForwarder));

        vm.prank(USER1);
        uint256 stv = ggvStrategy.supply{value: depositAmount}(address(0), wstethToMint, abi.encode(GGVStrategy.GGVParamsSupply(0)));

        uint256 mintedSharesAfter = ggvStrategy.mintedStethSharesOf(USER1);
        uint256 wstethBalanceAfter = wsteth.balanceOf(address(callForwarder));
        uint256 ggvSharesAfter = boringVault.balanceOf(address(callForwarder));

        assertGt(stv, 0, "stv should be minted from ETH deposit");
        assertEq(mintedSharesAfter, mintedSharesBefore, "no wsteth shares should be minted");
        assertEq(mintedSharesAfter, 0, "minted shares should be zero");
        assertEq(wstethBalanceAfter, wstethBalanceBefore, "wsteth balance should not change");
        assertEq(ggvSharesAfter, ggvSharesBefore, "ggv shares should not change");
    }

    function _finalizeWQ(uint256 _maxRequest, uint256 vaultProfit) public {
        vm.deal(address(pool.VAULT()), 1 ether);

        vm.warp(block.timestamp + 1 days);
        core.applyVaultReport(address(pool.VAULT()), pool.totalAssets(), 0, pool.DASHBOARD().liabilityShares(), 0);

        if (vaultProfit != 0) {
            vm.startPrank(NODE_OPERATOR);
            pool.DASHBOARD().fund{value: 10 ether}();
            vm.stopPrank();
        }

        vm.startPrank(NODE_OPERATOR);
        uint256 finalizedRequests = pool.WITHDRAWAL_QUEUE().finalize(_maxRequest, address(0));
        vm.stopPrank();

        assertEq(finalizedRequests, _maxRequest, "Invalid finalized requests");
    }
}
