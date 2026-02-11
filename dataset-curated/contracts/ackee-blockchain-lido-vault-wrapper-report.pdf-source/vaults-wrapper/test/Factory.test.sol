// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";

import {Factory} from "src/Factory.sol";
import {DistributorFactory} from "src/factories/DistributorFactory.sol";
import {GGVStrategyFactory} from "src/factories/GGVStrategyFactory.sol";
import {StvPoolFactory} from "src/factories/StvPoolFactory.sol";
import {StvStETHPoolFactory} from "src/factories/StvStETHPoolFactory.sol";
import {TimelockFactory} from "src/factories/TimelockFactory.sol";
import {WithdrawalQueueFactory} from "src/factories/WithdrawalQueueFactory.sol";

import {Distributor} from "src/Distributor.sol";
import {StvPool} from "src/StvPool.sol";
import {StvStETHPool} from "src/StvStETHPool.sol";
import {WithdrawalQueue} from "src/WithdrawalQueue.sol";
import {IDashboard} from "src/interfaces/core/IDashboard.sol";

import {DummyImplementation} from "src/proxy/DummyImplementation.sol";
import {MockDashboard} from "test/mocks/MockDashboard.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {MockLazyOracle} from "test/mocks/MockLazyOracle.sol";
import {MockLidoLocator} from "test/mocks/MockLidoLocator.sol";
import {MockVaultFactory} from "test/mocks/MockVaultFactory.sol";
import {MockVaultHub} from "test/mocks/MockVaultHub.sol";

contract FactoryTest is Test {
    Factory public wrapperFactory;

    MockVaultHub public vaultHub;
    MockVaultFactory public vaultFactory;
    MockERC20 public stETH;
    MockERC20 public wstETH;
    MockLazyOracle public lazyOracle;
    MockLidoLocator public locator;

    address public admin = address(0x1);
    address public nodeOperator = address(0x2);
    address public nodeOperatorManager = address(0x3);
    address public allowListManager = address(0x4);

    uint256 public connectDeposit = 1 ether;
    uint256 internal immutable FUSAKA_TX_GAS_LIMIT = 16_777_216;

    function setUp() public {
        vaultHub = new MockVaultHub();
        vaultFactory = new MockVaultFactory(address(vaultHub));
        stETH = new MockERC20("Staked Ether", "stETH");
        wstETH = new MockERC20("Wrapped Staked Ether", "wstETH");
        lazyOracle = new MockLazyOracle();

        locator = new MockLidoLocator(
            address(stETH), address(wstETH), address(lazyOracle), address(vaultHub), address(vaultFactory)
        );

        Factory.SubFactories memory subFactories;
        subFactories.stvPoolFactory = address(new StvPoolFactory());
        subFactories.stvStETHPoolFactory = address(new StvStETHPoolFactory());
        subFactories.withdrawalQueueFactory = address(new WithdrawalQueueFactory());
        subFactories.distributorFactory = address(new DistributorFactory());

        subFactories.timelockFactory = address(new TimelockFactory());

        wrapperFactory = new Factory(address(locator), subFactories);

        vm.deal(admin, 100 ether);
    }

    function _buildConfigs(
        bool allowListEnabled,
        address allowListManager,
        bool mintingEnabled,
        uint256 reserveRatioGapBP,
        string memory name,
        string memory symbol
    )
        internal
        view
        returns (
            Factory.VaultConfig memory vaultConfig,
            Factory.CommonPoolConfig memory commonPoolConfig,
            Factory.AuxiliaryPoolConfig memory auxiliaryConfig
        )
    {
        vaultConfig = Factory.VaultConfig({
            nodeOperator: nodeOperator,
            nodeOperatorManager: nodeOperatorManager,
            nodeOperatorFeeBP: 100,
            confirmExpiry: 3600
        });

        commonPoolConfig = Factory.CommonPoolConfig({
            minWithdrawalDelayTime: 1 days, name: name, symbol: symbol, emergencyCommittee: address(0)
        });

        auxiliaryConfig = Factory.AuxiliaryPoolConfig({
            allowListEnabled: allowListEnabled,
            allowListManager: allowListManager,
            mintingEnabled: mintingEnabled,
            reserveRatioGapBP: reserveRatioGapBP
        });
    }

    function _defaultTimelockConfig() internal view returns (Factory.TimelockConfig memory) {
        return Factory.TimelockConfig({minDelaySeconds: 0, proposer: address(this), executor: admin});
    }

    function test_canCreatePool() public {
        (
            Factory.VaultConfig memory vaultConfig,
            Factory.CommonPoolConfig memory commonPoolConfig,
            Factory.AuxiliaryPoolConfig memory auxiliaryConfig
        ) = _buildConfigs(false, address(0), false, 0, "Factory STV Pool", "FSTV");

        Factory.TimelockConfig memory timelockConfig = _defaultTimelockConfig();
        address strategyFactory = address(0);

        vm.startPrank(admin);
        Factory.PoolIntermediate memory intermediate = wrapperFactory.createPoolStart(
            vaultConfig, timelockConfig, commonPoolConfig, auxiliaryConfig, strategyFactory, ""
        );
        Factory.PoolDeployment memory deployment = wrapperFactory.createPoolFinish{value: connectDeposit}(
            vaultConfig, timelockConfig, commonPoolConfig, auxiliaryConfig, strategyFactory, "", intermediate
        );
        vm.stopPrank();

        StvPool pool = StvPool(payable(deployment.pool));
        WithdrawalQueue withdrawalQueue = WithdrawalQueue(payable(deployment.withdrawalQueue));
        IDashboard dashboard = IDashboard(payable(deployment.dashboard));
        Distributor distributor = pool.DISTRIBUTOR();

        assertEq(address(pool.DASHBOARD()), address(dashboard));
        assertEq(address(pool.WITHDRAWAL_QUEUE()), address(withdrawalQueue));
        assertEq(address(pool.DISTRIBUTOR()), address(distributor));

        assertEq(deployment.vault, address(dashboard.stakingVault()));
        assertEq(address(pool.VAULT()), deployment.vault);

        MockDashboard mockDashboard = MockDashboard(payable(address(dashboard)));
        assertTrue(mockDashboard.hasRole(mockDashboard.DEFAULT_ADMIN_ROLE(), deployment.timelock));

        assertEq(pool.ALLOW_LIST_ENABLED(), false);
        assertEq(deployment.distributor, address(distributor));
        assertEq(deployment.strategy, address(0));
        assertEq(deployment.poolType, wrapperFactory.STV_POOL_TYPE());
    }

    function test_revertWithoutConnectDeposit() public {
        (
            Factory.VaultConfig memory vaultConfig,
            Factory.CommonPoolConfig memory commonPoolConfig,
            Factory.AuxiliaryPoolConfig memory auxiliaryConfig
        ) = _buildConfigs(false, address(0), false, 0, "Factory STV Pool", "FSTV");

        Factory.TimelockConfig memory timelockConfig = _defaultTimelockConfig();
        address strategyFactory = address(0);

        vm.startPrank(admin);
        Factory.PoolIntermediate memory intermediate = wrapperFactory.createPoolStart(
            vaultConfig, timelockConfig, commonPoolConfig, auxiliaryConfig, strategyFactory, ""
        );
        vm.expectRevert();
        wrapperFactory.createPoolFinish(
            vaultConfig, timelockConfig, commonPoolConfig, auxiliaryConfig, strategyFactory, "", intermediate
        );
        vm.stopPrank();
    }

    function test_canCreateWithStrategy() public {
        (
            Factory.VaultConfig memory vaultConfig,
            Factory.CommonPoolConfig memory commonPoolConfig,
            Factory.AuxiliaryPoolConfig memory auxiliaryConfig
        ) = _buildConfigs(true, address(0), true, 0, "Factory stETH Pool", "FSTETH");

        Factory.TimelockConfig memory timelockConfig = _defaultTimelockConfig();

        address dummyTeller = address(new DummyImplementation());
        address dummyQueue = address(new DummyImplementation());
        address strategyFactory = address(new GGVStrategyFactory(dummyTeller, dummyQueue));

        vm.startPrank(admin);
        Factory.PoolIntermediate memory intermediate = wrapperFactory.createPoolStart(
            vaultConfig, timelockConfig, commonPoolConfig, auxiliaryConfig, strategyFactory, ""
        );
        uint256 nonceBefore = vm.getNonce(strategyFactory);
        Factory.PoolDeployment memory deployment = wrapperFactory.createPoolFinish{value: connectDeposit}(
            vaultConfig, timelockConfig, commonPoolConfig, auxiliaryConfig, strategyFactory, "", intermediate
        );
        vm.stopPrank();

        StvStETHPool pool = StvStETHPool(payable(deployment.pool));

        uint256 nonceAfter = vm.getNonce(strategyFactory);
        assertTrue(nonceAfter >= nonceBefore);
        assertTrue(deployment.strategy != address(0));
        assertTrue(pool.isAllowListed(deployment.strategy));

        MockDashboard mockDashboard = MockDashboard(payable(deployment.dashboard));
        assertTrue(mockDashboard.hasRole(mockDashboard.MINT_ROLE(), address(pool)));
        assertTrue(mockDashboard.hasRole(mockDashboard.BURN_ROLE(), address(pool)));
        assertEq(deployment.poolType, wrapperFactory.STRATEGY_POOL_TYPE());
    }

    function test_allowListEnabled() public {
        (
            Factory.VaultConfig memory vaultConfig,
            Factory.CommonPoolConfig memory commonPoolConfig,
            Factory.AuxiliaryPoolConfig memory auxiliaryConfig
        ) = _buildConfigs(true, allowListManager, false, 0, "Factory STV Pool", "FSTV");

        Factory.TimelockConfig memory timelockConfig = _defaultTimelockConfig();
        address strategyFactory = address(0);

        vm.startPrank(admin);
        Factory.PoolIntermediate memory intermediate = wrapperFactory.createPoolStart(
            vaultConfig, timelockConfig, commonPoolConfig, auxiliaryConfig, strategyFactory, ""
        );
        Factory.PoolDeployment memory deployment = wrapperFactory.createPoolFinish{value: connectDeposit}(
            vaultConfig, timelockConfig, commonPoolConfig, auxiliaryConfig, strategyFactory, "", intermediate
        );
        vm.stopPrank();

        StvPool pool = StvPool(payable(deployment.pool));
        assertTrue(pool.ALLOW_LIST_ENABLED());
        assertEq(deployment.poolType, wrapperFactory.STV_POOL_TYPE());
    }

    function test_createPoolStartGasConsumptionBelowFusakaLimit() public {
        (
            Factory.VaultConfig memory vaultConfig,
            Factory.CommonPoolConfig memory commonPoolConfig,
            Factory.AuxiliaryPoolConfig memory auxiliaryConfig
        ) = _buildConfigs(false, address(0), false, 0, "Factory STV Pool", "FSTV");

        Factory.TimelockConfig memory timelockConfig = _defaultTimelockConfig();
        address strategyFactory = address(0);

        vm.startPrank(admin);
        uint256 gasBefore = gasleft();
        Factory.PoolIntermediate memory intermediate = wrapperFactory.createPoolStart(
            vaultConfig, timelockConfig, commonPoolConfig, auxiliaryConfig, strategyFactory, ""
        );
        uint256 gasUsedStart = gasBefore - gasleft();

        uint256 gasBeforeFinish = gasleft();
        wrapperFactory.createPoolFinish{value: connectDeposit}(
            vaultConfig, timelockConfig, commonPoolConfig, auxiliaryConfig, strategyFactory, "", intermediate
        );
        uint256 gasUsedFinish = gasBeforeFinish - gasleft();
        vm.stopPrank();

        emit log_named_uint("createPoolStart gas", gasUsedStart);
        emit log_named_uint("createPoolFinish gas", gasUsedFinish);
        assertLt(gasUsedStart, FUSAKA_TX_GAS_LIMIT, "createPoolStart gas exceeds Fusaka limit");
        assertLt(gasUsedFinish, FUSAKA_TX_GAS_LIMIT, "createPoolFinish gas exceeds Fusaka limit");
    }

    function test_createPoolStartGasConsumptionBelowFusakaLimitForStvSteth() public {
        (
            Factory.VaultConfig memory vaultConfig,
            Factory.CommonPoolConfig memory commonPoolConfig,
            Factory.AuxiliaryPoolConfig memory auxiliaryConfig
        ) = _buildConfigs(false, address(0), true, 0, "Factory stETH Pool", "FSTETH");

        Factory.TimelockConfig memory timelockConfig = _defaultTimelockConfig();
        address strategyFactory = address(0);

        vm.startPrank(admin);
        uint256 gasBefore = gasleft();
        Factory.PoolIntermediate memory intermediate = wrapperFactory.createPoolStart(
            vaultConfig, timelockConfig, commonPoolConfig, auxiliaryConfig, strategyFactory, ""
        );
        uint256 gasUsedStart = gasBefore - gasleft();

        uint256 gasBeforeFinish = gasleft();
        wrapperFactory.createPoolFinish{value: connectDeposit}(
            vaultConfig, timelockConfig, commonPoolConfig, auxiliaryConfig, strategyFactory, "", intermediate
        );
        uint256 gasUsedFinish = gasBeforeFinish - gasleft();
        vm.stopPrank();

        emit log_named_uint("createPoolStart stv steth gas", gasUsedStart);
        emit log_named_uint("createPoolFinish stv steth gas", gasUsedFinish);
        assertLt(gasUsedStart, FUSAKA_TX_GAS_LIMIT, "createPoolStart stv steth gas exceeds Fusaka limit");
        assertLt(gasUsedFinish, FUSAKA_TX_GAS_LIMIT, "createPoolFinish stv steth gas exceeds Fusaka limit");
    }

    function test_createPoolStartGasConsumptionBelowFusakaLimitForStvGgv() public {
        (
            Factory.VaultConfig memory vaultConfig,
            Factory.CommonPoolConfig memory commonPoolConfig,
            Factory.AuxiliaryPoolConfig memory auxiliaryConfig
        ) = _buildConfigs(true, address(0), true, 0, "Factory Strategy Pool", "FSP");

        Factory.TimelockConfig memory timelockConfig = _defaultTimelockConfig();

        address dummyTeller = address(new DummyImplementation());
        address dummyQueue = address(new DummyImplementation());
        address strategyFactory = address(new GGVStrategyFactory(dummyTeller, dummyQueue));

        vm.startPrank(admin);
        uint256 gasBefore = gasleft();
        Factory.PoolIntermediate memory intermediate = wrapperFactory.createPoolStart(
            vaultConfig, timelockConfig, commonPoolConfig, auxiliaryConfig, strategyFactory, ""
        );
        uint256 gasUsedStart = gasBefore - gasleft();

        uint256 gasBeforeFinish = gasleft();
        wrapperFactory.createPoolFinish{value: connectDeposit}(
            vaultConfig, timelockConfig, commonPoolConfig, auxiliaryConfig, strategyFactory, "", intermediate
        );
        uint256 gasUsedFinish = gasBeforeFinish - gasleft();
        vm.stopPrank();

        emit log_named_uint("createPoolStart stv ggv gas", gasUsedStart);
        emit log_named_uint("createPoolFinish stv ggv gas", gasUsedFinish);
        assertLt(gasUsedStart, FUSAKA_TX_GAS_LIMIT, "createPoolStart stv ggv gas exceeds Fusaka limit");
        assertLt(gasUsedFinish, FUSAKA_TX_GAS_LIMIT, "createPoolFinish stv ggv gas exceeds Fusaka limit");
    }

    // ============ Finish Deadline Tests ============

    function test_finishWithinDeadline() public {
        // Test that finishing within the deadline (1 day) works correctly
        (
            Factory.VaultConfig memory vaultConfig,
            Factory.CommonPoolConfig memory commonPoolConfig,
            Factory.AuxiliaryPoolConfig memory auxiliaryConfig
        ) = _buildConfigs(false, address(0), false, 0, "Deadline Test Pool", "DTP");

        Factory.TimelockConfig memory timelockConfig = _defaultTimelockConfig();
        address strategyFactory = address(0);

        vm.startPrank(admin);
        Factory.PoolIntermediate memory intermediate = wrapperFactory.createPoolStart(
            vaultConfig, timelockConfig, commonPoolConfig, auxiliaryConfig, strategyFactory, ""
        );

        // Move time forward but still within deadline (23 hours)
        vm.warp(block.timestamp + 23 hours);

        // Should succeed
        Factory.PoolDeployment memory deployment = wrapperFactory.createPoolFinish{value: connectDeposit}(
            vaultConfig, timelockConfig, commonPoolConfig, auxiliaryConfig, strategyFactory, "", intermediate
        );
        vm.stopPrank();

        // Verify deployment was successful
        assertTrue(deployment.pool != address(0), "Pool should be deployed");
        assertTrue(deployment.dashboard != address(0), "Dashboard should be deployed");
    }

    function test_finishAtExactDeadline() public {
        // Test that finishing exactly at the deadline works
        (
            Factory.VaultConfig memory vaultConfig,
            Factory.CommonPoolConfig memory commonPoolConfig,
            Factory.AuxiliaryPoolConfig memory auxiliaryConfig
        ) = _buildConfigs(false, address(0), false, 0, "Deadline Test Pool", "DTP");

        Factory.TimelockConfig memory timelockConfig = _defaultTimelockConfig();
        address strategyFactory = address(0);

        vm.startPrank(admin);
        Factory.PoolIntermediate memory intermediate = wrapperFactory.createPoolStart(
            vaultConfig, timelockConfig, commonPoolConfig, auxiliaryConfig, strategyFactory, ""
        );

        // Move time forward to exactly the deadline (1 day)
        vm.warp(block.timestamp + wrapperFactory.DEPLOY_START_FINISH_SPAN_SECONDS());

        // Should succeed (deadline is inclusive)
        Factory.PoolDeployment memory deployment = wrapperFactory.createPoolFinish{value: connectDeposit}(
            vaultConfig, timelockConfig, commonPoolConfig, auxiliaryConfig, strategyFactory, "", intermediate
        );
        vm.stopPrank();

        assertTrue(deployment.pool != address(0), "Pool should be deployed at exact deadline");
    }

    function test_revertFinishAfterDeadlineExpired() public {
        // Test that finishing after the deadline reverts
        (
            Factory.VaultConfig memory vaultConfig,
            Factory.CommonPoolConfig memory commonPoolConfig,
            Factory.AuxiliaryPoolConfig memory auxiliaryConfig
        ) = _buildConfigs(false, address(0), false, 0, "Deadline Test Pool", "DTP");

        Factory.TimelockConfig memory timelockConfig = _defaultTimelockConfig();
        address strategyFactory = address(0);

        vm.startPrank(admin);
        Factory.PoolIntermediate memory intermediate = wrapperFactory.createPoolStart(
            vaultConfig, timelockConfig, commonPoolConfig, auxiliaryConfig, strategyFactory, ""
        );

        // Move time forward past the deadline (1 day + 1 second)
        vm.warp(block.timestamp + wrapperFactory.DEPLOY_START_FINISH_SPAN_SECONDS() + 1);

        // Should revert with deadline passed error
        vm.expectRevert(abi.encodeWithSignature("InvalidConfiguration(string)", "deploy finish deadline passed"));
        wrapperFactory.createPoolFinish{value: connectDeposit}(
            vaultConfig, timelockConfig, commonPoolConfig, auxiliaryConfig, strategyFactory, "", intermediate
        );
        vm.stopPrank();
    }

    function test_revertFinishWithoutStart() public {
        // Test that calling finish without start reverts
        (
            Factory.VaultConfig memory vaultConfig,
            Factory.CommonPoolConfig memory commonPoolConfig,
            Factory.AuxiliaryPoolConfig memory auxiliaryConfig
        ) = _buildConfigs(false, address(0), false, 0, "Fake Pool", "FAKE");

        Factory.TimelockConfig memory timelockConfig = _defaultTimelockConfig();
        address strategyFactory = address(0);

        // Create an intermediate struct but don't call createPoolStart
        Factory.PoolIntermediate memory fakeIntermediate = Factory.PoolIntermediate({
            dashboard: address(0x123),
            poolProxy: address(0x456),
            poolImpl: address(0x111),
            withdrawalQueueProxy: address(0x789),
            wqImpl: address(0x222),
            timelock: address(0xabc)
        });

        vm.startPrank(admin);
        // Should revert with "deploy not started" error
        vm.expectRevert(abi.encodeWithSignature("InvalidConfiguration(string)", "deploy not started"));
        wrapperFactory.createPoolFinish{value: connectDeposit}(
            vaultConfig, timelockConfig, commonPoolConfig, auxiliaryConfig, strategyFactory, "", fakeIntermediate
        );
        vm.stopPrank();
    }

    function test_revertDoubleFinish() public {
        // Test that calling finish twice on the same deployment reverts
        (
            Factory.VaultConfig memory vaultConfig,
            Factory.CommonPoolConfig memory commonPoolConfig,
            Factory.AuxiliaryPoolConfig memory auxiliaryConfig
        ) = _buildConfigs(false, address(0), false, 0, "Deadline Test Pool", "DTP");

        Factory.TimelockConfig memory timelockConfig = _defaultTimelockConfig();
        address strategyFactory = address(0);

        vm.startPrank(admin);
        Factory.PoolIntermediate memory intermediate = wrapperFactory.createPoolStart(
            vaultConfig, timelockConfig, commonPoolConfig, auxiliaryConfig, strategyFactory, ""
        );

        // First finish should succeed
        wrapperFactory.createPoolFinish{value: connectDeposit}(
            vaultConfig, timelockConfig, commonPoolConfig, auxiliaryConfig, strategyFactory, "", intermediate
        );

        // Second finish should revert with "deploy already finished"
        vm.expectRevert(abi.encodeWithSignature("InvalidConfiguration(string)", "deploy already finished"));
        wrapperFactory.createPoolFinish{value: connectDeposit}(
            vaultConfig, timelockConfig, commonPoolConfig, auxiliaryConfig, strategyFactory, "", intermediate
        );
        vm.stopPrank();
    }

    function test_finishDeadlineIndependentPerDeployer() public {
        // Test that different deployers have independent deadlines for the same config
        (
            Factory.VaultConfig memory vaultConfig,
            Factory.CommonPoolConfig memory commonPoolConfig,
            Factory.AuxiliaryPoolConfig memory auxiliaryConfig
        ) = _buildConfigs(false, address(0), false, 0, "Deadline Test Pool", "DTP");

        Factory.TimelockConfig memory timelockConfig = _defaultTimelockConfig();
        address strategyFactory = address(0);

        address deployer1 = address(0x1001);
        address deployer2 = address(0x1002);
        vm.deal(deployer1, 10 ether);
        vm.deal(deployer2, 10 ether);

        // Deployer 1 starts deployment
        vm.prank(deployer1);
        Factory.PoolIntermediate memory intermediate1 = wrapperFactory.createPoolStart(
            vaultConfig, timelockConfig, commonPoolConfig, auxiliaryConfig, strategyFactory, ""
        );

        // Move time forward
        vm.warp(block.timestamp + 12 hours);

        // Deployer 2 starts deployment
        vm.prank(deployer2);
        Factory.PoolIntermediate memory intermediate2 = wrapperFactory.createPoolStart(
            vaultConfig, timelockConfig, commonPoolConfig, auxiliaryConfig, strategyFactory, ""
        );

        // Move time forward past deployer1's deadline but within deployer2's deadline
        vm.warp(block.timestamp + 13 hours); // Total: 25 hours from deployer1's start, 13 hours from deployer2's start

        // Deployer 1's finish should fail (past deadline)
        vm.prank(deployer1);
        vm.expectRevert(abi.encodeWithSignature("InvalidConfiguration(string)", "deploy finish deadline passed"));
        wrapperFactory.createPoolFinish{value: connectDeposit}(
            vaultConfig, timelockConfig, commonPoolConfig, auxiliaryConfig, strategyFactory, "", intermediate1
        );

        // Deployer 2's finish should succeed (within deadline)
        vm.prank(deployer2);
        Factory.PoolDeployment memory deployment2 = wrapperFactory.createPoolFinish{value: connectDeposit}(
            vaultConfig, timelockConfig, commonPoolConfig, auxiliaryConfig, strategyFactory, "", intermediate2
        );
        assertTrue(deployment2.pool != address(0), "Deployer 2 should successfully finish");
    }

    // ============ Proposer and Executor Validation Tests ============

    function test_revertCreatePoolWithZeroProposer() public {
        // Test that creating a pool with proposer = address(0) reverts
        (
            Factory.VaultConfig memory vaultConfig,
            Factory.CommonPoolConfig memory commonPoolConfig,
            Factory.AuxiliaryPoolConfig memory auxiliaryConfig
        ) = _buildConfigs(false, address(0), false, 0, "Test Pool", "TP");

        Factory.TimelockConfig memory timelockConfig = Factory.TimelockConfig({
            minDelaySeconds: 0,
            proposer: address(0), // Invalid proposer
            executor: admin
        });
        address strategyFactory = address(0);

        vm.startPrank(admin);
        // Should revert with "proposer must not be zero address" error
        vm.expectRevert(abi.encodeWithSignature("InvalidConfiguration(string)", "proposer must not be zero address"));
        wrapperFactory.createPoolStart(
            vaultConfig, timelockConfig, commonPoolConfig, auxiliaryConfig, strategyFactory, ""
        );
        vm.stopPrank();
    }

    function test_revertCreatePoolWithZeroExecutor() public {
        // Test that creating a pool with executor = address(0) reverts
        (
            Factory.VaultConfig memory vaultConfig,
            Factory.CommonPoolConfig memory commonPoolConfig,
            Factory.AuxiliaryPoolConfig memory auxiliaryConfig
        ) = _buildConfigs(false, address(0), false, 0, "Test Pool", "TP");

        Factory.TimelockConfig memory timelockConfig = Factory.TimelockConfig({
            minDelaySeconds: 0,
            proposer: address(this),
            executor: address(0) // Invalid executor
        });
        address strategyFactory = address(0);

        vm.startPrank(admin);
        // Should revert with "executor must not be zero address" error
        vm.expectRevert(abi.encodeWithSignature("InvalidConfiguration(string)", "executor must not be zero address"));
        wrapperFactory.createPoolStart(
            vaultConfig, timelockConfig, commonPoolConfig, auxiliaryConfig, strategyFactory, ""
        );
        vm.stopPrank();
    }
}
