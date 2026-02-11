// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {Vm} from "forge-std/Vm.sol";
import {Factory} from "src/Factory.sol";
import {StvPool} from "src/StvPool.sol";
import {WithdrawalQueue} from "src/WithdrawalQueue.sol";
import {StvPoolHarness} from "test/utils/StvPoolHarness.sol";
import {FactoryHelper} from "test/utils/FactoryHelper.sol";
import {Factory} from "src/Factory.sol";
import {IDashboard} from "src/interfaces/core/IDashboard.sol";
import {IOssifiableProxy} from "src/interfaces/core/IOssifiableProxy.sol";
import {Vm} from "forge-std/Vm.sol";
import {DummyImplementation} from "src/proxy/DummyImplementation.sol";
import {GGVStrategyFactory} from "src/factories/GGVStrategyFactory.sol";

contract FactoryIntegrationTest is StvPoolHarness {
    Factory internal factory;
    address internal constant ALLOW_LIST_MANAGER = address(0xA110);
    address internal strategyGGVFactory;


    function setUp() public {
        _initializeCore();

        FactoryHelper helper = new FactoryHelper();

        factory = helper.deployMainFactory(address(core.locator()));

        address dummyTeller = address(new DummyImplementation());
        address dummyQueue = address(new DummyImplementation());
        strategyGGVFactory = address(new GGVStrategyFactory(dummyTeller, dummyQueue));
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
        pure
        returns (
            Factory.VaultConfig memory vaultConfig,
            Factory.CommonPoolConfig memory commonPoolConfig,
            Factory.AuxiliaryPoolConfig memory auxiliaryConfig,
            Factory.TimelockConfig memory timelockConfig
        )
    {
        vaultConfig = Factory.VaultConfig({
            nodeOperator: NODE_OPERATOR,
            nodeOperatorManager: NODE_OPERATOR,
            nodeOperatorFeeBP: 500,
            confirmExpiry: CONFIRM_EXPIRY
        });

        timelockConfig = Factory.TimelockConfig({minDelaySeconds: 0, proposer: NODE_OPERATOR, executor: NODE_OPERATOR});

        commonPoolConfig = Factory.CommonPoolConfig({minWithdrawalDelayTime: 1 days, name: name, symbol: symbol, emergencyCommittee: address(0)});

        auxiliaryConfig = Factory.AuxiliaryPoolConfig({
            allowListEnabled: allowListEnabled,
            allowListManager: allowListManager,
            mintingEnabled: mintingEnabled,
            reserveRatioGapBP: reserveRatioGapBP
        });
    }

    function _deployThroughFactory(
        Factory.VaultConfig memory vaultConfig,
        Factory.TimelockConfig memory timelockConfig,
        Factory.CommonPoolConfig memory commonPoolConfig,
        Factory.AuxiliaryPoolConfig memory auxiliaryConfig,
        address strategyFactory
    ) internal returns (Factory.PoolIntermediate memory, Factory.PoolDeployment memory) {
        vm.startPrank(vaultConfig.nodeOperator);
        Factory.PoolIntermediate memory intermediate = factory.createPoolStart(
            vaultConfig, timelockConfig, commonPoolConfig, auxiliaryConfig, strategyFactory, ""
        );
        Factory.PoolDeployment memory deployment = factory.createPoolFinish{value: CONNECT_DEPOSIT}(
            vaultConfig, timelockConfig, commonPoolConfig, auxiliaryConfig, strategyFactory, "", intermediate
        );
        vm.stopPrank();

        return (intermediate, deployment);
    }

    function test_createPoolFinish_reverts_without_exact_connect_deposit() public {
        (
            Factory.VaultConfig memory vaultConfig,
            Factory.CommonPoolConfig memory commonPoolConfig,
            Factory.AuxiliaryPoolConfig memory auxiliaryConfig,
            Factory.TimelockConfig memory timelockConfig
        ) = _buildConfigs(false, address(0), false, 0, "Factory Test Pool", "FT-STV");
        address strategyFactory = address(0);

        assertGt(CONNECT_DEPOSIT, 1, "CONNECT_DEPOSIT must be > 1 for this test");

        vm.startPrank(vaultConfig.nodeOperator);
        Factory.PoolIntermediate memory intermediate = factory.createPoolStart(
            vaultConfig, timelockConfig, commonPoolConfig, auxiliaryConfig, strategyFactory, ""
        );

        vm.expectRevert(
            abi.encodeWithSelector(Factory.InsufficientConnectDeposit.selector, CONNECT_DEPOSIT - 1, CONNECT_DEPOSIT)
        );
        factory.createPoolFinish{value: CONNECT_DEPOSIT - 1}(
            vaultConfig, timelockConfig, commonPoolConfig, auxiliaryConfig, strategyFactory, "", intermediate
        );
        vm.stopPrank();
    }

    function test_createPool_without_minting_configures_roles() public {
        (
            Factory.VaultConfig memory vaultConfig,
            Factory.CommonPoolConfig memory commonPoolConfig,
            Factory.AuxiliaryPoolConfig memory auxiliaryConfig,
            Factory.TimelockConfig memory timelockConfig
        ) = _buildConfigs(false, address(0), false, 0, "Factory No Mint", "FNM");
        address strategyFactory = address(0);

        (, Factory.PoolDeployment memory deployment) =
            _deployThroughFactory(vaultConfig, timelockConfig, commonPoolConfig, auxiliaryConfig, strategyFactory);

        assertEq(deployment.strategy, address(0), "strategy should not be deployed");

        IDashboard dashboard = IDashboard(payable(deployment.dashboard));
        StvPool pool = StvPool(payable(deployment.pool));

        assertTrue(dashboard.hasRole(dashboard.FUND_ROLE(), deployment.pool), "pool should have FUND_ROLE");
        assertTrue(
            dashboard.hasRole(dashboard.WITHDRAW_ROLE(), deployment.withdrawalQueue),
            "withdrawal queue should have WITHDRAW_ROLE"
        );
        assertFalse(dashboard.hasRole(dashboard.MINT_ROLE(), deployment.pool), "mint role should not be granted");
        assertTrue(pool.hasRole(pool.DEFAULT_ADMIN_ROLE(), deployment.timelock), "timelock should own pool");
    }

    function test_createPool_with_minting_grants_mint_and_burn_roles() public {
        (
            Factory.VaultConfig memory vaultConfig,
            Factory.CommonPoolConfig memory commonPoolConfig,
            Factory.AuxiliaryPoolConfig memory auxiliaryConfig,
            Factory.TimelockConfig memory timelockConfig
        ) = _buildConfigs(false, address(0), true, 0, "Factory Mint Pool", "FMP");
        address strategyFactory = address(0);

        (, Factory.PoolDeployment memory deployment) =
            _deployThroughFactory(vaultConfig, timelockConfig, commonPoolConfig, auxiliaryConfig, strategyFactory);

        IDashboard dashboard = IDashboard(payable(deployment.dashboard));

        assertTrue(dashboard.hasRole(dashboard.MINT_ROLE(), deployment.pool), "mint role should be granted");
        assertTrue(dashboard.hasRole(dashboard.BURN_ROLE(), deployment.pool), "burn role should be granted");
    }

    function test_createPool_with_strategy_deploys_strategy_and_allowlists_it() public {
        (
            Factory.VaultConfig memory vaultConfig,
            Factory.CommonPoolConfig memory commonPoolConfig,
            Factory.AuxiliaryPoolConfig memory auxiliaryConfig,
            Factory.TimelockConfig memory timelockConfig
        ) = _buildConfigs(true, address(0), true, 500, "Factory Strategy Pool", "FSP");

        (, Factory.PoolDeployment memory deployment) =
            _deployThroughFactory(vaultConfig, timelockConfig, commonPoolConfig, auxiliaryConfig, strategyGGVFactory);

        assertTrue(deployment.strategy != address(0), "strategy should be deployed");

        StvPool pool = StvPool(payable(deployment.pool));
        assertTrue(pool.ALLOW_LIST_ENABLED(), "allowlist should be enabled");
        assertTrue(pool.isAllowListed(deployment.strategy), "strategy should be allowlisted");

        // Verify strategy is behind a proxy owned by timelock
        assertEq(
            IOssifiableProxy(deployment.strategy).proxy__getAdmin(),
            deployment.timelock,
            "strategy proxy should be owned by timelock"
        );

        // Verify the implementation exists
        address strategyImpl = IOssifiableProxy(deployment.strategy).proxy__getImplementation();
        assertTrue(strategyImpl != address(0), "strategy implementation should exist");
        assertGt(strategyImpl.code.length, 0, "strategy implementation should have code");
    }

    function test_createPoolFinish_reverts_with_modified_intermediate() public {
        (
            Factory.VaultConfig memory vaultConfig,
            Factory.CommonPoolConfig memory commonPoolConfig,
            Factory.AuxiliaryPoolConfig memory auxiliaryConfig,
            Factory.TimelockConfig memory timelockConfig
        ) = _buildConfigs(false, address(0), false, 0, "Factory Tamper", "FTAMP");

        address strategyFactory = address(0);

        vm.startPrank(vaultConfig.nodeOperator);
        Factory.PoolIntermediate memory intermediate = factory.createPoolStart(
            vaultConfig, timelockConfig, commonPoolConfig, auxiliaryConfig, strategyFactory, ""
        );

        // Tamper with the intermediate before finishing to ensure the deployment hash is checked.
        intermediate.poolProxy = address(0xdead);

        vm.expectRevert(abi.encodeWithSelector(Factory.InvalidConfiguration.selector, "deploy not started"));
        factory.createPoolFinish{value: CONNECT_DEPOSIT}(
            vaultConfig, timelockConfig, commonPoolConfig, auxiliaryConfig, strategyFactory, "", intermediate
        );
        vm.stopPrank();
    }

    function test_createPoolFinish_reverts_with_modified_config() public {
        (
            Factory.VaultConfig memory vaultConfig,
            Factory.CommonPoolConfig memory commonPoolConfig,
            Factory.AuxiliaryPoolConfig memory auxiliaryConfig,
            Factory.TimelockConfig memory timelockConfig
        ) = _buildConfigs(false, address(0), false, 0, "Factory Tamper Config", "FTCFG");

        address strategyFactory = address(0);

        vm.startPrank(vaultConfig.nodeOperator);
        Factory.PoolIntermediate memory intermediate = factory.createPoolStart(
            vaultConfig,
            timelockConfig,
            commonPoolConfig,
            auxiliaryConfig,
            strategyFactory,
            ""
        );

        // Tamper with the configuration before finishing
        vaultConfig.nodeOperatorFeeBP = 999;

        vm.expectRevert(abi.encodeWithSelector(Factory.InvalidConfiguration.selector, "deploy not started"));
        factory.createPoolFinish{value: CONNECT_DEPOSIT}(
            vaultConfig, timelockConfig, commonPoolConfig, auxiliaryConfig, strategyFactory, "", intermediate
        );
        vm.stopPrank();
    }

    function test_createPoolFinish_reverts_with_different_sender() public {
        (
            Factory.VaultConfig memory vaultConfig,
            Factory.CommonPoolConfig memory commonPoolConfig,
            Factory.AuxiliaryPoolConfig memory auxiliaryConfig,
            Factory.TimelockConfig memory timelockConfig
        ) = _buildConfigs(false, address(0), false, 0, "Factory Wrong Sender", "FWS");

        address strategyFactory = address(0);

        vm.startPrank(vaultConfig.nodeOperator);
        Factory.PoolIntermediate memory intermediate = factory.createPoolStart(
            vaultConfig, timelockConfig, commonPoolConfig, auxiliaryConfig, strategyFactory, ""
        );
        vm.stopPrank();

        address otherSender = address(0xbeef);
        vm.deal(otherSender, CONNECT_DEPOSIT);
        vm.startPrank(otherSender);
        vm.expectRevert(abi.encodeWithSelector(Factory.InvalidConfiguration.selector, "deploy not started"));
        factory.createPoolFinish{value: CONNECT_DEPOSIT}(
            vaultConfig, timelockConfig, commonPoolConfig, auxiliaryConfig, strategyFactory, "", intermediate
        );
        vm.stopPrank();
    }

    function test_createPoolFinish_reverts_when_called_twice() public {
        (
            Factory.VaultConfig memory vaultConfig,
            Factory.CommonPoolConfig memory commonPoolConfig,
            Factory.AuxiliaryPoolConfig memory auxiliaryConfig,
            Factory.TimelockConfig memory timelockConfig
        ) = _buildConfigs(false, address(0), false, 0, "Factory Double Finish", "FDF");

        address strategyFactory = address(0);

        vm.startPrank(vaultConfig.nodeOperator);
        Factory.PoolIntermediate memory intermediate = factory.createPoolStart(
            vaultConfig, timelockConfig, commonPoolConfig, auxiliaryConfig, strategyFactory, ""
        );

        factory.createPoolFinish{value: CONNECT_DEPOSIT}(
            vaultConfig, timelockConfig, commonPoolConfig, auxiliaryConfig, strategyFactory, "", intermediate
        );

        // The intermediate hash is set to DEPLOY_COMPLETE after the first successful call; the second should fail.
        vm.expectRevert(abi.encodeWithSelector(Factory.InvalidConfiguration.selector, "deploy already finished"));
        factory.createPoolFinish{value: CONNECT_DEPOSIT}(
            vaultConfig, timelockConfig, commonPoolConfig, auxiliaryConfig, strategyFactory, "", intermediate
        );
        vm.stopPrank();
    }

    function test_emits_pool_creation_started_event() public {
        (
            Factory.VaultConfig memory vaultConfig,
            Factory.CommonPoolConfig memory commonPoolConfig,
            Factory.AuxiliaryPoolConfig memory auxiliaryConfig,
            Factory.TimelockConfig memory timelockConfig
        ) = _buildConfigs(false, address(0), false, 0, "Factory Event Pool", "FEP");
        address strategyFactory = address(0);

        vm.startPrank(vaultConfig.nodeOperator);
        vm.recordLogs();
        Factory.PoolIntermediate memory intermediate = factory.createPoolStart(
            vaultConfig, timelockConfig, commonPoolConfig, auxiliaryConfig, strategyFactory, ""
        );
        vm.stopPrank();

        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 expectedTopic = keccak256(
            "PoolCreationStarted(address,(address,address,uint256,uint256),(uint256,string,string,address),(bool,address,bool,uint256),(uint256,address,address),address,bytes,(address,address,address,address,address,address),uint256)"
        );

        bool found;
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].emitter != address(factory)) continue;
            if (entries[i].topics.length == 0 || entries[i].topics[0] != expectedTopic) continue;

            // Extract indexed parameters from topics
            address sender = address(uint160(uint256(entries[i].topics[1])));
            address emittedStrategyFactory = address(uint160(uint256(entries[i].topics[2])));

            // Decode non-indexed event data
            (
                Factory.VaultConfig memory emittedVaultConfig,
                Factory.CommonPoolConfig memory emittedCommonPoolConfig,
                Factory.AuxiliaryPoolConfig memory emittedAuxiliaryConfig,
                Factory.TimelockConfig memory emittedTimelockConfig,
                bytes memory emittedStrategyDeployBytes,
                Factory.PoolIntermediate memory emittedIntermediate,
                uint256 emittedFinishDeadline
            ) = abi.decode(
                entries[i].data,
                (
                    Factory.VaultConfig,
                    Factory.CommonPoolConfig,
                    Factory.AuxiliaryPoolConfig,
                    Factory.TimelockConfig,
                    bytes,
                    Factory.PoolIntermediate,
                    uint256
                )
            );

            // Verify all the emitted values match the inputs
            assertEq(sender, vaultConfig.nodeOperator, "sender should match node operator");
            assertEq(emittedVaultConfig.nodeOperator, vaultConfig.nodeOperator, "nodeOperator should match");
            assertEq(emittedVaultConfig.nodeOperatorManager, vaultConfig.nodeOperatorManager, "nodeOperatorManager should match");
            assertEq(emittedVaultConfig.nodeOperatorFeeBP, vaultConfig.nodeOperatorFeeBP, "nodeOperatorFeeBP should match");
            assertEq(emittedVaultConfig.confirmExpiry, vaultConfig.confirmExpiry, "confirmExpiry should match");

            assertEq(emittedCommonPoolConfig.minWithdrawalDelayTime, commonPoolConfig.minWithdrawalDelayTime, "minWithdrawalDelayTime should match");
            assertEq(emittedCommonPoolConfig.name, commonPoolConfig.name, "name should match");
            assertEq(emittedCommonPoolConfig.symbol, commonPoolConfig.symbol, "symbol should match");

            assertEq(emittedAuxiliaryConfig.allowListEnabled, auxiliaryConfig.allowListEnabled, "allowListEnabled should match");
            assertEq(emittedAuxiliaryConfig.allowListManager, auxiliaryConfig.allowListManager, "allowListManager should match");
            assertEq(emittedAuxiliaryConfig.mintingEnabled, auxiliaryConfig.mintingEnabled, "mintingEnabled should match");
            assertEq(emittedAuxiliaryConfig.reserveRatioGapBP, auxiliaryConfig.reserveRatioGapBP, "reserveRatioGapBP should match");

            assertEq(emittedTimelockConfig.minDelaySeconds, timelockConfig.minDelaySeconds, "minDelaySeconds should match");
            assertEq(emittedTimelockConfig.proposer, timelockConfig.proposer, "proposer should match");
            assertEq(emittedTimelockConfig.executor, timelockConfig.executor, "executor should match");

            assertEq(emittedStrategyFactory, strategyFactory, "strategyFactory should match");
            assertEq(emittedStrategyDeployBytes, "", "strategyDeployBytes should be empty");

            assertEq(emittedIntermediate.dashboard, intermediate.dashboard, "dashboard address should match");
            assertEq(emittedIntermediate.poolProxy, intermediate.poolProxy, "poolProxy address should match");
            assertEq(emittedIntermediate.poolImpl, intermediate.poolImpl, "poolImpl address should match");
            assertEq(emittedIntermediate.withdrawalQueueProxy, intermediate.withdrawalQueueProxy, "withdrawalQueueProxy should match");
            assertEq(emittedIntermediate.wqImpl, intermediate.wqImpl, "wqImpl address should match");
            assertEq(emittedIntermediate.timelock, intermediate.timelock, "timelock should match");

            assertGt(emittedFinishDeadline, block.timestamp, "finish deadline should be in the future");

            found = true;
            break;
        }

        assertTrue(found, "PoolCreationStarted event should be emitted");
    }

    function test_initial_acl_configuration() public {
        // Test all four pool configurations:
        // i=0: StvPool (no minting, no allowlist)
        // i=1: StvStETHPool (minting, no allowlist)
        // i=2: StvPool with allowlist (allowListManager configured)
        // i=3: StvStrategyPool (strategy, allowlist with timelock as manager)
        for (uint256 i = 0; i < 4; i++) {
            bool allowListEnabled = (i >= 2);
            bool mintingEnabled = (i == 1 || i == 3);
            uint256 reserveRatioGapBP = (i == 3) ? 500 : 0;
            address strategyFactory = (i == 3) ? strategyGGVFactory : address(0);
            // For strategy pools, allowListManager config is ignored (timelock is used)
            // For non-strategy pools with allowlist, use ALLOW_LIST_MANAGER
            address allowListManagerConfig = (i == 2) ? ALLOW_LIST_MANAGER : address(0);

            string memory poolName = i == 0 ? "Factory StvPool" : i == 1 ? "Factory StvStETHPool" : i == 2 ? "Factory StvPoolAllowlist" : "Factory StrategyPool";
            string memory poolSymbol = i == 0 ? "FSTV" : i == 1 ? "FSTETH" : i == 2 ? "FSTVA" : "FSTRAT";

            (
                Factory.VaultConfig memory vaultConfig,
                Factory.CommonPoolConfig memory commonPoolConfig,
                Factory.AuxiliaryPoolConfig memory auxiliaryConfig,
                Factory.TimelockConfig memory timelockConfig
            ) = _buildConfigs(allowListEnabled, allowListManagerConfig, mintingEnabled, reserveRatioGapBP, poolName, poolSymbol);

            (, Factory.PoolDeployment memory deployment) =
                _deployThroughFactory(vaultConfig, timelockConfig, commonPoolConfig, auxiliaryConfig, strategyFactory);

            bytes32 poolType = factory.derivePoolType(auxiliaryConfig, strategyFactory);

            IDashboard dashboard = IDashboard(payable(deployment.dashboard));
            StvPool pool = StvPool(payable(deployment.pool));
            WithdrawalQueue wq = WithdrawalQueue(payable(deployment.withdrawalQueue));
            address timelock = deployment.timelock;
            address deployer = vaultConfig.nodeOperator;

            // === Verify pool type ===
            assertEq(deployment.poolType, poolType, "deployment pool type should match derived pool type");

            if (poolType == factory.STV_POOL_TYPE()) {
                assertEq(poolType, factory.STV_POOL_TYPE(), "pool type should be STV_POOL_TYPE");
            } else if (poolType == factory.STV_STETH_POOL_TYPE()) {
                assertEq(poolType, factory.STV_STETH_POOL_TYPE(), "pool type should be STV_STETH_POOL_TYPE");
            } else if (poolType == factory.STRATEGY_POOL_TYPE()) {
                assertEq(poolType, factory.STRATEGY_POOL_TYPE(), "pool type should be STRATEGY_POOL_TYPE");
            }

            // === Dashboard AccessControl Roles ===
            assertTrue(
                dashboard.hasRole(dashboard.FUND_ROLE(), deployment.pool),
                "pool should have FUND_ROLE on dashboard"
            );
            assertTrue(
                dashboard.hasRole(dashboard.REBALANCE_ROLE(), deployment.pool),
                "pool should have REBALANCE_ROLE on dashboard"
            );
            assertTrue(
                dashboard.hasRole(dashboard.WITHDRAW_ROLE(), deployment.withdrawalQueue),
                "withdrawal queue should have WITHDRAW_ROLE on dashboard"
            );

            // Check minting roles based on pool type
            if (mintingEnabled) {
                assertTrue(
                    dashboard.hasRole(dashboard.MINT_ROLE(), deployment.pool),
                    "pool should have MINT_ROLE when minting enabled"
                );
                assertTrue(
                    dashboard.hasRole(dashboard.BURN_ROLE(), deployment.pool),
                    "pool should have BURN_ROLE when minting enabled"
                );
            } else {
                assertFalse(
                    dashboard.hasRole(dashboard.MINT_ROLE(), deployment.pool),
                    "pool should not have MINT_ROLE when minting disabled"
                );
                assertFalse(
                    dashboard.hasRole(dashboard.BURN_ROLE(), deployment.pool),
                    "pool should not have BURN_ROLE when minting disabled"
                );
            }

            assertTrue(
                dashboard.hasRole(dashboard.DEFAULT_ADMIN_ROLE(), timelock),
                "timelock should have DEFAULT_ADMIN_ROLE on dashboard"
            );

            // === Pool (StvPool) AccessControl Roles ===
            assertTrue(
                pool.hasRole(pool.DEFAULT_ADMIN_ROLE(), timelock),
                "timelock should have DEFAULT_ADMIN_ROLE on pool"
            );
            assertFalse(
                pool.hasRole(pool.DEFAULT_ADMIN_ROLE(), address(factory)),
                "factory should not have DEFAULT_ADMIN_ROLE on pool"
            );
            assertFalse(
                pool.hasRole(pool.DEFAULT_ADMIN_ROLE(), deployer),
                "deployer should not have DEFAULT_ADMIN_ROLE on pool"
            );

            // Check ALLOW_LIST_MANAGER_ROLE based on allowlist configuration
            if (allowListEnabled) {
                // For strategy pools, ALLOW_LIST_MANAGER_ROLE is not assigned to anyone
                // For non-strategy pools, it goes to the configured allowListManager
                if (strategyFactory != address(0)) {
                    // Strategy pool: no one has ALLOW_LIST_MANAGER_ROLE
                    assertFalse(
                        pool.hasRole(pool.ALLOW_LIST_MANAGER_ROLE(), timelock),
                        "timelock should not have ALLOW_LIST_MANAGER_ROLE for strategy pools"
                    );
                } else {
                    // Non-strategy pool: allowListManager has the role
                    assertTrue(
                        pool.hasRole(pool.ALLOW_LIST_MANAGER_ROLE(), allowListManagerConfig),
                        "allowListManager should have ALLOW_LIST_MANAGER_ROLE when allowlist enabled"
                    );
                    assertFalse(
                        pool.hasRole(pool.ALLOW_LIST_MANAGER_ROLE(), timelock),
                        "timelock should not have ALLOW_LIST_MANAGER_ROLE for non-strategy pools"
                    );
                }
                assertFalse(
                    pool.hasRole(pool.ALLOW_LIST_MANAGER_ROLE(), address(factory)),
                    "factory should not have ALLOW_LIST_MANAGER_ROLE on pool"
                );
                assertFalse(
                    pool.hasRole(pool.ALLOW_LIST_MANAGER_ROLE(), deployer),
                    "deployer should not have ALLOW_LIST_MANAGER_ROLE on pool"
                );
            }

            // === WithdrawalQueue AccessControl Roles ===
            assertTrue(
                wq.hasRole(wq.DEFAULT_ADMIN_ROLE(), timelock),
                "timelock should have DEFAULT_ADMIN_ROLE on withdrawal queue"
            );
            assertTrue(
                wq.hasRole(wq.FINALIZE_ROLE(), vaultConfig.nodeOperator),
                "node operator should have FINALIZE_ROLE on withdrawal queue"
            );
            assertFalse(
                wq.hasRole(wq.DEFAULT_ADMIN_ROLE(), address(factory)),
                "factory should not have DEFAULT_ADMIN_ROLE on withdrawal queue"
            );
            assertFalse(
                wq.hasRole(wq.DEFAULT_ADMIN_ROLE(), deployer),
                "deployer should not have DEFAULT_ADMIN_ROLE on withdrawal queue"
            );

            // === Proxy Ownership (OssifiableProxy) ===
            assertEq(
                IOssifiableProxy(deployment.pool).proxy__getAdmin(),
                timelock,
                "pool proxy should be owned by timelock"
            );
            assertNotEq(
                IOssifiableProxy(deployment.pool).proxy__getAdmin(),
                address(factory),
                "pool proxy should not be owned by factory"
            );
            assertNotEq(
                IOssifiableProxy(deployment.pool).proxy__getAdmin(),
                deployer,
                "pool proxy should not be owned by deployer"
            );

            assertEq(
                IOssifiableProxy(deployment.withdrawalQueue).proxy__getAdmin(),
                timelock,
                "withdrawal queue proxy should be owned by timelock"
            );
            assertNotEq(
                IOssifiableProxy(deployment.withdrawalQueue).proxy__getAdmin(),
                address(factory),
                "withdrawal queue proxy should not be owned by factory"
            );
            assertNotEq(
                IOssifiableProxy(deployment.withdrawalQueue).proxy__getAdmin(),
                deployer,
                "withdrawal queue proxy should not be owned by deployer"
            );

            // === Distributor AccessControl Roles ===
            assertTrue(
                pool.DISTRIBUTOR().hasRole(pool.DISTRIBUTOR().DEFAULT_ADMIN_ROLE(), timelock),
                "timelock should have DEFAULT_ADMIN_ROLE on distributor"
            );
            assertTrue(
                pool.DISTRIBUTOR().hasRole(pool.DISTRIBUTOR().MANAGER_ROLE(), vaultConfig.nodeOperatorManager),
                "node operator manager should have MANAGER_ROLE on distributor"
            );
            assertFalse(
                pool.DISTRIBUTOR().hasRole(pool.DISTRIBUTOR().DEFAULT_ADMIN_ROLE(), address(factory)),
                "factory should not have DEFAULT_ADMIN_ROLE on distributor"
            );
            assertFalse(
                pool.DISTRIBUTOR().hasRole(pool.DISTRIBUTOR().DEFAULT_ADMIN_ROLE(), deployer),
                "deployer should not have DEFAULT_ADMIN_ROLE on distributor"
            );

            // === Vault Ownership ===
            assertEq(
                core.vaultHub().vaultConnection(address(pool.VAULT())).owner,
                deployment.dashboard,
                "dashboard should be the owner of the vault via VaultHub connection"
            );

            // === Strategy-specific checks ===
            if (poolType == factory.STRATEGY_POOL_TYPE()) {
                assertTrue(deployment.strategy != address(0), "strategy should be deployed");
                assertTrue(pool.isAllowListed(deployment.strategy), "strategy should be allowlisted on pool");
                assertTrue(pool.ALLOW_LIST_ENABLED(), "allowlist should be enabled for strategy pools");

                // Strategy proxy ownership checks
                assertEq(
                    IOssifiableProxy(deployment.strategy).proxy__getAdmin(),
                    timelock,
                    "strategy proxy should be owned by timelock"
                );
                assertNotEq(
                    IOssifiableProxy(deployment.strategy).proxy__getAdmin(),
                    address(factory),
                    "strategy proxy should not be owned by factory"
                );
                assertNotEq(
                    IOssifiableProxy(deployment.strategy).proxy__getAdmin(),
                    deployer,
                    "strategy proxy should not be owned by deployer"
                );

                // Verify strategy implementation exists
                address strategyImpl = IOssifiableProxy(deployment.strategy).proxy__getImplementation();
                assertTrue(strategyImpl != address(0), "strategy implementation should exist");
                assertGt(strategyImpl.code.length, 0, "strategy implementation should have code");
            } else {
                assertEq(deployment.strategy, address(0), "strategy should not be deployed for non-strategy pools");
            }
        }
    }


}
