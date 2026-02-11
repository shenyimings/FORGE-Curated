// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {Factory} from "src/Factory.sol";
import {OssifiableProxy} from "src/proxy/OssifiableProxy.sol";
import {StvPool} from "src/StvPool.sol";
import {StvStETHPool} from "src/StvStETHPool.sol";
import {StvStETHPoolFactory} from "src/factories/StvStETHPoolFactory.sol";
import {IStrategy} from "src/interfaces/IStrategy.sol";
import {IDashboard} from "src/interfaces/core/IDashboard.sol";
import {WithdrawalQueue} from "src/WithdrawalQueue.sol";

import {FactoryHelper} from "test/utils/FactoryHelper.sol";
import {StvPoolHarness} from "test/utils/StvPoolHarness.sol";
import {TimelockHarness} from "test/utils/TimelockHarness.sol";
import {MockStrategy} from "test/mocks/MockStrategy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {console} from "forge-std/console.sol";

contract WrapperUpgradeBtoCTest is StvPoolHarness, TimelockHarness {
    Factory internal factory;

    function setUp() public {
        _initializeCore();
        FactoryHelper helper = new FactoryHelper();
        factory = helper.deployMainFactory(address(core.locator()));
    }

    // The flow:
    // - NodeOperator creates pool (Wrapper-B) via Factory
    //   - pool type is StvStETHPool
    //   - allowlist is disabled
    //   - minting is disabled
    //   - TODO
    function test_upgradeWrapperB_toWrapperC_strategyPool() public {
        Factory.VaultConfig memory vaultConfig = Factory.VaultConfig({
            nodeOperator: NODE_OPERATOR,
            nodeOperatorManager: NODE_OPERATOR,
            nodeOperatorFeeBP: 500,
            confirmExpiry: CONFIRM_EXPIRY
        });

        Factory.TimelockConfig memory timelockConfig = Factory.TimelockConfig({minDelaySeconds: 0, proposer: NODE_OPERATOR, executor: NODE_OPERATOR});

        uint256 reserveRatioGapBP = 500;
        Factory.CommonPoolConfig memory commonPoolConfig = Factory.CommonPoolConfig({
            minWithdrawalDelayTime: 1 days,
            name: "Upgrade test STV",
            symbol: "uSTV",
            // Give NODE_OPERATOR the emergency pauser role to be able to disable minting in StvStETHPool
            emergencyCommittee: NODE_OPERATOR
        });

        // Wrapper-B is deployed WITHOUT allowlist.
        Factory.AuxiliaryPoolConfig memory auxiliaryConfig = Factory.AuxiliaryPoolConfig({
            allowListEnabled: false,
            allowListManager: address(0),
            mintingEnabled: true,
            reserveRatioGapBP: reserveRatioGapBP
        });

        vm.startPrank(NODE_OPERATOR);
        Factory.PoolIntermediate memory intermediate =
            factory.createPoolStart(vaultConfig, timelockConfig, commonPoolConfig, auxiliaryConfig, address(0), "");
        Factory.PoolDeployment memory deployment = factory.createPoolFinish{value: CONNECT_DEPOSIT}(
            vaultConfig, timelockConfig, commonPoolConfig, auxiliaryConfig, address(0), "", intermediate
        );
        vm.stopPrank();

        // Apply initial report so deposits pass freshness checks
        core.applyVaultReport(deployment.vault, CONNECT_DEPOSIT, 0, 0, 0);

        StvStETHPool pool = StvStETHPool(payable(deployment.pool));
        assertEq(pool.poolType(), factory.STV_STETH_POOL_TYPE(), "expected Wrapper-B type");
        assertFalse(pool.ALLOW_LIST_ENABLED(), "allowlist must be disabled in Wrapper-B");

        // Disable minting in Wrapper-B by pausing the minting feature.
        vm.prank(NODE_OPERATOR);
        pool.pauseMinting();
        vm.expectRevert();
        pool.mintStethShares(1);

        uint256 userStvBefore1 = pool.balanceOf(USER1);
        console.log("userStvBefore1", userStvBefore1);

        // User deposits 100 ETH
        vm.deal(USER1, 1000 ether);
        vm.prank(USER1);
        pool.depositETH{value: 100 ether}(USER1, address(0));

        uint256 userStvBefore = pool.balanceOf(USER1);
        assertGt(userStvBefore, 0, "user should receive STV");

        uint256 userStvBefore2 = pool.balanceOf(USER1);
        console.log("userStvBefore2", userStvBefore2);

        // Wrapper-C: upgraded pool implementation with poolType=STRATEGY_POOL_TYPE + a Strategy proxy.
        // Allowlist becomes enabled at the implementation level (immutable) and strategy is allowlisted,
        // similar to how Factory sets allowlist for strategy pools.
        _setupTimelock(deployment.timelock, NODE_OPERATOR, NODE_OPERATOR);

        // new implementation
        StvStETHPoolFactory poolFactory = factory.STV_STETH_POOL_FACTORY();
        address newPoolImpl = poolFactory.deploy(
            deployment.dashboard,
            /* allowListEnabled */ true,
            reserveRatioGapBP,
            deployment.withdrawalQueue,
            deployment.distributor,
            factory.STRATEGY_POOL_TYPE()
        );
        bytes memory upgradePayload =
            abi.encodeWithSignature("proxy__upgradeToAndCall(address,bytes)", newPoolImpl, bytes(""));

        // strategy implementation
        address strategyImpl = address(new MockStrategy(address(pool)));
        address strategyProxy = address(
            new OssifiableProxy(
                strategyImpl,
                deployment.timelock,
                abi.encodeCall(IStrategy.initialize, (deployment.timelock, address(0)))
            )
        );

        // upgrade + set allowlist for strategy via timelock
        // - grant ALLOW_LIST_MANAGER_ROLE to timelock
        // - add strategy to allowlist
        // - revoke ALLOW_LIST_MANAGER_ROLE from previous manager (Factory) and from timelock
        // - revoke emergency pauser roles from NodeOperator
        bytes32 managerRole = pool.ALLOW_LIST_MANAGER_ROLE();
        bytes memory grantManagerToTimelock =
            abi.encodeWithSignature("grantRole(bytes32,address)", managerRole, deployment.timelock);
        bytes memory allowlistStrategy = abi.encodeWithSignature("addToAllowList(address)", strategyProxy);
        bytes memory revokeManagerFromFactory =
            abi.encodeWithSignature("revokeRole(bytes32,address)", managerRole, address(factory));
        bytes memory revokeManagerFromTimelock =
            abi.encodeWithSignature("revokeRole(bytes32,address)", managerRole, deployment.timelock);
        bytes32 depositsPauseRole = pool.DEPOSITS_PAUSE_ROLE();
        bytes memory revokeDepositsPauseFromNodeOperator =
            abi.encodeWithSignature("revokeRole(bytes32,address)", depositsPauseRole, NODE_OPERATOR);
        bytes32 mintingPauseRole = pool.MINTING_PAUSE_ROLE();
        bytes memory revokeMintingPauseFromNodeOperator =
            abi.encodeWithSignature("revokeRole(bytes32,address)", mintingPauseRole, NODE_OPERATOR);

        // Minting was paused in Wrapper-B; resume it in Wrapper-C so the strategy can mint wstETH.
        bytes32 mintingResumeRole = pool.MINTING_RESUME_ROLE();
        bytes memory grantMintingResumeToTimelock =
            abi.encodeWithSignature("grantRole(bytes32,address)", mintingResumeRole, deployment.timelock);
        bytes memory resumeMinting = abi.encodeWithSignature("resumeMinting()");
        bytes memory revokeMintingResumeFromTimelock =
            abi.encodeWithSignature("revokeRole(bytes32,address)", mintingResumeRole, deployment.timelock);

        uint256 idx = 0;
        address[] memory targets = new address[](10);
        bytes[] memory payloads = new bytes[](10);

        targets[idx] = address(pool);
        payloads[idx] = upgradePayload;
        idx++;

        targets[idx] = address(pool);
        payloads[idx] = grantManagerToTimelock;
        idx++;

        targets[idx] = address(pool);
        payloads[idx] = allowlistStrategy;
        idx++;

        targets[idx] = address(pool);
        payloads[idx] = revokeManagerFromFactory;
        idx++;

        targets[idx] = address(pool);
        payloads[idx] = revokeManagerFromTimelock;
        idx++;

        targets[idx] = address(pool);
        payloads[idx] = revokeDepositsPauseFromNodeOperator;
        idx++;

        targets[idx] = address(pool);
        payloads[idx] = revokeMintingPauseFromNodeOperator;
        idx++;

        targets[idx] = address(pool);
        payloads[idx] = grantMintingResumeToTimelock;
        idx++;

        targets[idx] = address(pool);
        payloads[idx] = resumeMinting;
        idx++;

        targets[idx] = address(pool);
        payloads[idx] = revokeMintingResumeFromTimelock;
        idx++;

        // Ensure we filled all array entries
        assertEq(idx, targets.length, "all target/payload entries should be filled");

        _timelockScheduleAndExecuteBatch(targets, payloads);

        // Verify upgrade: poolType is now strategy pool
        assertEq(pool.poolType(), factory.STRATEGY_POOL_TYPE(), "expected Wrapper-C type");
        assertTrue(pool.ALLOW_LIST_ENABLED(), "allowlist must be enabled in Wrapper-C");

        // Check that the factory no longer has the ALLOW_LIST_MANAGER_ROLE after upgrade
        assertFalse(pool.hasRole(managerRole, address(factory)), "Factory should not have ALLOW_LIST_MANAGER_ROLE");
        assertFalse(pool.hasRole(depositsPauseRole, NODE_OPERATOR), "NodeOperator should not pause deposits");
        assertFalse(pool.hasRole(mintingPauseRole, NODE_OPERATOR), "NodeOperator should not pause minting");
        WithdrawalQueue wq = WithdrawalQueue(payable(deployment.withdrawalQueue));
        IDashboard dashboard = IDashboard(payable(deployment.dashboard));

        // Verify state continuity: user's STV balance didn't change during upgrade
        assertEq(pool.balanceOf(USER1), userStvBefore, "user STV should be preserved");

        uint256 userStvBefore3 = pool.balanceOf(USER1);
        console.log("userStvBefore3", userStvBefore3);

        // Keep report fresh for subsequent operations
        core.applyVaultReport(deployment.vault, address(deployment.vault).balance, 0, 0, 0);

        // Direct user deposits are blocked by allowlist after upgrade.
        vm.prank(USER1);
        vm.expectRevert();
        pool.depositETH{value: 1 ether}(USER1, address(0));

        // User can deposit existing STV (from Wrapper-B) into strategy and receive wstETH (like GGV).
        uint256 stvToDepositIntoStrategy = userStvBefore / 2;
        assertGt(stvToDepositIntoStrategy, 0, "stvToDepositIntoStrategy must be > 0");

        // Determine a safe wstETH amount to mint based on the deposited STV collateral.
        uint256 maxWstethToMint = pool.calcStethSharesToMintForStv(stvToDepositIntoStrategy);
        uint256 wstethToMint = maxWstethToMint / 10;
        if (wstethToMint == 0) wstethToMint = 1;

        vm.prank(USER1);
        pool.approve(strategyProxy, stvToDepositIntoStrategy);

        address wsteth = address(pool.WSTETH());
        uint256 userWstethBefore = IERC20(wsteth).balanceOf(USER1);

        vm.prank(USER1);
        MockStrategy(strategyProxy).depositStvAndMintWsteth(stvToDepositIntoStrategy, wstethToMint);

        uint256 userStvBefore4 = pool.balanceOf(USER1);
        console.log("userStvBefore4", userStvBefore4);

        // User's STV moved into strategy
        assertEq(pool.balanceOf(USER1), userStvBefore - stvToDepositIntoStrategy, "user STV should decrease");
        assertEq(pool.balanceOf(strategyProxy), stvToDepositIntoStrategy, "strategy STV should increase");

        // User received wstETH
        uint256 userWstethAfter = IERC20(wsteth).balanceOf(USER1);
        assertEq(userWstethAfter - userWstethBefore, wstethToMint, "user must receive wstETH");
    }
}
