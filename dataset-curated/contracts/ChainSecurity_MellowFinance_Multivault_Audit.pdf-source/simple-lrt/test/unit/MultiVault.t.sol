// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "../BaseTest.sol";
import "../mocks/MockSymbioticFarm.sol";

contract Unit is BaseTest {
    using RandomLib for RandomLib.Storage;

    function testConstructor() external {
        MultiVault c = new MultiVault("test", 1);
        assertNotEq(address(c), address(0));
    }

    function testInitialize() external {
        MultiVault c;
        {
            TransparentUpgradeableProxy c_ = new TransparentUpgradeableProxy(
                address(new MultiVault("test", 1)), vm.createWallet("proxyAdmin").addr, new bytes(0)
            );
            c = MultiVault(address(c_));
        }

        assertEq(c.getRoleMemberCount(c.DEFAULT_ADMIN_ROLE()), 0);
        assertEq(c.limit(), 0);
        assertEq(c.depositPause(), false);
        assertEq(c.withdrawalPause(), false);
        assertEq(c.depositWhitelist(), false);
        assertEq(c.asset(), address(0));
        assertEq(c.name(), "");
        assertEq(c.symbol(), "");
        assertEq(address(c.depositStrategy()), address(0));
        assertEq(address(c.withdrawalStrategy()), address(0));
        assertEq(address(c.rebalanceStrategy()), address(0));
        assertEq(address(c.defaultCollateral()), address(0));
        assertEq(address(c.symbioticAdapter()), address(0));
        assertEq(address(c.eigenLayerAdapter()), address(0));
        assertEq(address(c.erc4626Adapter()), address(0));

        IMultiVault.InitParams memory initParams;
        initParams.admin = rnd.randAddress();
        initParams.limit = rnd.randInt(100 ether);
        initParams.depositPause = true;
        initParams.withdrawalPause = true;
        initParams.depositWhitelist = true;
        initParams.asset = Constants.WSTETH();
        initParams.name = "MultiVault test";
        initParams.symbol = "MVTEST";
        initParams.depositStrategy = address(1);
        initParams.withdrawalStrategy = address(2);
        initParams.rebalanceStrategy = address(3);
        initParams.defaultCollateral = Constants.WSTETH_SYMBIOTIC_COLLATERAL();
        initParams.symbioticAdapter = address(4);
        initParams.eigenLayerAdapter = address(5);
        initParams.erc4626Adapter = address(6);
        c.initialize(initParams);

        assertEq(c.getRoleMemberCount(c.DEFAULT_ADMIN_ROLE()), 1);
        assertEq(c.limit(), initParams.limit);
        assertEq(c.depositPause(), initParams.depositPause);
        assertEq(c.withdrawalPause(), initParams.withdrawalPause);
        assertEq(c.depositWhitelist(), initParams.depositWhitelist);
        assertEq(c.asset(), initParams.asset);
        assertEq(c.name(), initParams.name);
        assertEq(c.symbol(), initParams.symbol);
        assertEq(address(c.depositStrategy()), initParams.depositStrategy);
        assertEq(address(c.withdrawalStrategy()), initParams.withdrawalStrategy);
        assertEq(address(c.rebalanceStrategy()), initParams.rebalanceStrategy);
        assertEq(address(c.defaultCollateral()), initParams.defaultCollateral);
        assertEq(address(c.symbioticAdapter()), initParams.symbioticAdapter);
        assertEq(address(c.eigenLayerAdapter()), initParams.eigenLayerAdapter);
        assertEq(address(c.erc4626Adapter()), initParams.erc4626Adapter);
    }

    function testAddSubvault() external {
        MultiVault vault;
        {
            TransparentUpgradeableProxy c_ = new TransparentUpgradeableProxy(
                address(new MultiVault("test", 1)), vm.createWallet("proxyAdmin").addr, new bytes(0)
            );
            vault = MultiVault(address(c_));
        }

        address vaultAdmin = rnd.randAddress();
        RatiosStrategy strategy = new RatiosStrategy();
        Claimer claimer = new Claimer();
        SymbioticAdapter symbioticAdapter = new SymbioticAdapter(
            address(vault),
            Constants.symbioticDeployment().vaultFactory,
            address(new SymbioticWithdrawalQueue(address(new Claimer()))),
            vm.createWallet("proxyAdmin").addr
        );
        address wsteth = Constants.WSTETH();
        IsolatedEigenLayerVaultFactory factory = new IsolatedEigenLayerVaultFactory(
            Constants.HOLESKY_EL_DELEGATION_MANAGER,
            address(new IsolatedEigenLayerWstETHVault(Constants.WSTETH())),
            address(
                new EigenLayerWstETHWithdrawalQueue(
                    address(claimer), Constants.HOLESKY_EL_DELEGATION_MANAGER
                )
            ),
            vm.createWallet("proxyAdmin").addr
        );
        EigenLayerAdapter eigenLayerAdapter = new EigenLayerAdapter(
            address(factory),
            address(vault),
            IStrategyManager(Constants.HOLESKY_EL_STRATEGY_MANAGER),
            IRewardsCoordinator(Constants.HOLESKY_EL_REWARDS_COORDINATOR)
        );
        ERC4626Adapter erc4626Adapter = new ERC4626Adapter(address(vault));

        vault.initialize(
            IMultiVault.InitParams({
                admin: vaultAdmin,
                limit: type(uint256).max,
                depositPause: false,
                withdrawalPause: false,
                depositWhitelist: false,
                asset: Constants.WSTETH(),
                name: "MultiVault test",
                symbol: "MVT",
                depositStrategy: address(strategy),
                withdrawalStrategy: address(strategy),
                rebalanceStrategy: address(strategy),
                defaultCollateral: Constants.WSTETH_SYMBIOTIC_COLLATERAL(),
                symbioticAdapter: address(symbioticAdapter),
                eigenLayerAdapter: address(eigenLayerAdapter),
                erc4626Adapter: address(erc4626Adapter)
            })
        );

        vm.startPrank(vaultAdmin);

        (address symbioticSubvault,,,) =
            symbioticHelper.createDefaultSymbioticVault(Constants.WSTETH());

        vm.expectRevert();
        vault.addSubvault(symbioticSubvault, IMultiVaultStorage.Protocol.SYMBIOTIC);

        vault.grantRole(vault.ADD_SUBVAULT_ROLE(), vaultAdmin);
        vault.addSubvault(symbioticSubvault, IMultiVaultStorage.Protocol.SYMBIOTIC);
        assertEq(vault.subvaultsCount(), 1);

        (address symbioticSubvaultWrongAsset,,,) =
            symbioticHelper.createDefaultSymbioticVault(Constants.STETH());
        vm.expectRevert();
        vault.addSubvault(symbioticSubvaultWrongAsset, IMultiVaultStorage.Protocol.SYMBIOTIC);

        vm.stopPrank();
    }

    function testRemoveSubvault() external {
        MultiVault vault;
        {
            TransparentUpgradeableProxy c_ = new TransparentUpgradeableProxy(
                address(new MultiVault("test", 1)), vm.createWallet("proxyAdmin").addr, new bytes(0)
            );
            vault = MultiVault(address(c_));
        }

        address vaultAdmin = rnd.randAddress();
        RatiosStrategy strategy = new RatiosStrategy();
        Claimer claimer = new Claimer();
        SymbioticAdapter symbioticAdapter = new SymbioticAdapter(
            address(vault),
            Constants.symbioticDeployment().vaultFactory,
            address(new SymbioticWithdrawalQueue(address(new Claimer()))),
            vm.createWallet("proxyAdmin").addr
        );
        address wsteth = Constants.WSTETH();
        address delegationManager = Constants.HOLESKY_EL_DELEGATION_MANAGER;
        IsolatedEigenLayerVaultFactory factory = new IsolatedEigenLayerVaultFactory(
            Constants.HOLESKY_EL_DELEGATION_MANAGER,
            address(new IsolatedEigenLayerWstETHVault(Constants.WSTETH())),
            address(
                new EigenLayerWstETHWithdrawalQueue(
                    address(claimer), Constants.HOLESKY_EL_DELEGATION_MANAGER
                )
            ),
            vm.createWallet("proxyAdmin").addr
        );
        EigenLayerAdapter eigenLayerAdapter = new EigenLayerAdapter(
            address(factory),
            address(vault),
            IStrategyManager(Constants.HOLESKY_EL_STRATEGY_MANAGER),
            IRewardsCoordinator(Constants.HOLESKY_EL_REWARDS_COORDINATOR)
        );
        ERC4626Adapter erc4626Adapter = new ERC4626Adapter(address(vault));

        vault.initialize(
            IMultiVault.InitParams({
                admin: vaultAdmin,
                limit: type(uint256).max,
                depositPause: false,
                withdrawalPause: false,
                depositWhitelist: false,
                asset: Constants.WSTETH(),
                name: "MultiVault test",
                symbol: "MVT",
                depositStrategy: address(strategy),
                withdrawalStrategy: address(strategy),
                rebalanceStrategy: address(strategy),
                defaultCollateral: Constants.WSTETH_SYMBIOTIC_COLLATERAL(),
                symbioticAdapter: address(symbioticAdapter),
                eigenLayerAdapter: address(eigenLayerAdapter),
                erc4626Adapter: address(erc4626Adapter)
            })
        );

        vm.startPrank(vaultAdmin);

        (address symbioticSubvault,,,) =
            symbioticHelper.createDefaultSymbioticVault(Constants.WSTETH());

        vm.expectRevert();
        vault.addSubvault(symbioticSubvault, IMultiVaultStorage.Protocol.SYMBIOTIC);

        vault.grantRole(vault.ADD_SUBVAULT_ROLE(), vaultAdmin);
        vault.addSubvault(symbioticSubvault, IMultiVaultStorage.Protocol.SYMBIOTIC);
        assertEq(vault.subvaultsCount(), 1);

        (address symbioticSubvaultWrongAsset,,,) =
            symbioticHelper.createDefaultSymbioticVault(Constants.STETH());
        vm.expectRevert();
        vault.addSubvault(symbioticSubvaultWrongAsset, IMultiVaultStorage.Protocol.SYMBIOTIC);

        vm.expectRevert();
        vault.removeSubvault(symbioticSubvault);

        vault.grantRole(vault.REMOVE_SUBVAULT_ROLE(), vaultAdmin);
        vault.removeSubvault(symbioticSubvault);
        assertEq(vault.subvaultsCount(), 0);

        vm.expectRevert();
        vault.removeSubvault(symbioticSubvaultWrongAsset);

        vm.stopPrank();
    }

    function testSetDepositStrategy() external {
        MultiVault vault;
        {
            TransparentUpgradeableProxy c_ = new TransparentUpgradeableProxy(
                address(new MultiVault("test", 1)), vm.createWallet("proxyAdmin").addr, new bytes(0)
            );
            vault = MultiVault(address(c_));
        }

        address vaultAdmin = rnd.randAddress();
        RatiosStrategy strategy = new RatiosStrategy();
        Claimer claimer = new Claimer();
        SymbioticAdapter symbioticAdapter = new SymbioticAdapter(
            address(vault),
            Constants.symbioticDeployment().vaultFactory,
            address(new SymbioticWithdrawalQueue(address(new Claimer()))),
            vm.createWallet("proxyAdmin").addr
        );
        address wsteth = Constants.WSTETH();
        address delegationManager = Constants.HOLESKY_EL_DELEGATION_MANAGER;
        IsolatedEigenLayerVaultFactory factory = new IsolatedEigenLayerVaultFactory(
            Constants.HOLESKY_EL_DELEGATION_MANAGER,
            address(new IsolatedEigenLayerWstETHVault(Constants.WSTETH())),
            address(
                new EigenLayerWstETHWithdrawalQueue(
                    address(claimer), Constants.HOLESKY_EL_DELEGATION_MANAGER
                )
            ),
            vm.createWallet("proxyAdmin").addr
        );
        EigenLayerAdapter eigenLayerAdapter = new EigenLayerAdapter(
            address(factory),
            address(vault),
            IStrategyManager(Constants.HOLESKY_EL_STRATEGY_MANAGER),
            IRewardsCoordinator(Constants.HOLESKY_EL_REWARDS_COORDINATOR)
        );
        ERC4626Adapter erc4626Adapter = new ERC4626Adapter(address(vault));

        vault.initialize(
            IMultiVault.InitParams({
                admin: vaultAdmin,
                limit: type(uint256).max,
                depositPause: false,
                withdrawalPause: false,
                depositWhitelist: false,
                asset: Constants.WSTETH(),
                name: "MultiVault test",
                symbol: "MVT",
                depositStrategy: address(strategy),
                withdrawalStrategy: address(strategy),
                rebalanceStrategy: address(strategy),
                defaultCollateral: Constants.WSTETH_SYMBIOTIC_COLLATERAL(),
                symbioticAdapter: address(symbioticAdapter),
                eigenLayerAdapter: address(eigenLayerAdapter),
                erc4626Adapter: address(erc4626Adapter)
            })
        );

        vm.startPrank(vaultAdmin);

        vm.expectRevert();
        vault.setDepositStrategy(address(strategy));

        assertEq(address(vault.depositStrategy()), address(strategy));

        vault.grantRole(vault.SET_STRATEGY_ROLE(), vaultAdmin);
        vault.setDepositStrategy(address(strategy));

        assertEq(address(vault.depositStrategy()), address(strategy));

        vault.setDepositStrategy(address(123));

        assertEq(address(vault.depositStrategy()), address(123));

        vm.expectRevert("MultiVault: deposit strategy cannot be zero address");
        vault.setDepositStrategy(address(0));

        vm.stopPrank();
    }

    function testSetWithdrawalStrategy() external {
        MultiVault vault;
        {
            TransparentUpgradeableProxy c_ = new TransparentUpgradeableProxy(
                address(new MultiVault("test", 1)), vm.createWallet("proxyAdmin").addr, new bytes(0)
            );
            vault = MultiVault(address(c_));
        }

        address vaultAdmin = rnd.randAddress();
        RatiosStrategy strategy = new RatiosStrategy();
        Claimer claimer = new Claimer();
        SymbioticAdapter symbioticAdapter = new SymbioticAdapter(
            address(vault),
            Constants.symbioticDeployment().vaultFactory,
            address(new SymbioticWithdrawalQueue(address(new Claimer()))),
            vm.createWallet("proxyAdmin").addr
        );
        address wsteth = Constants.WSTETH();
        address delegationManager = Constants.HOLESKY_EL_DELEGATION_MANAGER;
        IsolatedEigenLayerVaultFactory factory = new IsolatedEigenLayerVaultFactory(
            Constants.HOLESKY_EL_DELEGATION_MANAGER,
            address(new IsolatedEigenLayerWstETHVault(Constants.WSTETH())),
            address(
                new EigenLayerWstETHWithdrawalQueue(
                    address(claimer), Constants.HOLESKY_EL_DELEGATION_MANAGER
                )
            ),
            vm.createWallet("proxyAdmin").addr
        );
        EigenLayerAdapter eigenLayerAdapter = new EigenLayerAdapter(
            address(factory),
            address(vault),
            IStrategyManager(Constants.HOLESKY_EL_STRATEGY_MANAGER),
            IRewardsCoordinator(Constants.HOLESKY_EL_REWARDS_COORDINATOR)
        );
        ERC4626Adapter erc4626Adapter = new ERC4626Adapter(address(vault));

        vault.initialize(
            IMultiVault.InitParams({
                admin: vaultAdmin,
                limit: type(uint256).max,
                depositPause: false,
                withdrawalPause: false,
                depositWhitelist: false,
                asset: Constants.WSTETH(),
                name: "MultiVault test",
                symbol: "MVT",
                depositStrategy: address(strategy),
                withdrawalStrategy: address(strategy),
                rebalanceStrategy: address(strategy),
                defaultCollateral: Constants.WSTETH_SYMBIOTIC_COLLATERAL(),
                symbioticAdapter: address(symbioticAdapter),
                eigenLayerAdapter: address(eigenLayerAdapter),
                erc4626Adapter: address(erc4626Adapter)
            })
        );

        vm.startPrank(vaultAdmin);

        vm.expectRevert();
        vault.setWithdrawalStrategy(address(strategy));

        assertEq(address(vault.withdrawalStrategy()), address(strategy));

        vault.grantRole(vault.SET_STRATEGY_ROLE(), vaultAdmin);
        vault.setWithdrawalStrategy(address(strategy));

        assertEq(address(vault.withdrawalStrategy()), address(strategy));

        vault.setWithdrawalStrategy(address(123));

        assertEq(address(vault.withdrawalStrategy()), address(123));

        vm.expectRevert("MultiVault: withdrawal strategy cannot be zero address");
        vault.setWithdrawalStrategy(address(0));

        vm.stopPrank();
    }

    function testSetRebalanceStrategy() external {
        MultiVault vault;
        {
            TransparentUpgradeableProxy c_ = new TransparentUpgradeableProxy(
                address(new MultiVault("test", 1)), vm.createWallet("proxyAdmin").addr, new bytes(0)
            );
            vault = MultiVault(address(c_));
        }
        address vaultAdmin = rnd.randAddress();
        RatiosStrategy strategy = new RatiosStrategy();
        Claimer claimer = new Claimer();
        SymbioticAdapter symbioticAdapter = new SymbioticAdapter(
            address(vault),
            Constants.symbioticDeployment().vaultFactory,
            address(new SymbioticWithdrawalQueue(address(new Claimer()))),
            vm.createWallet("proxyAdmin").addr
        );
        address wsteth = Constants.WSTETH();
        address delegationManager = Constants.HOLESKY_EL_DELEGATION_MANAGER;
        IsolatedEigenLayerVaultFactory factory = new IsolatedEigenLayerVaultFactory(
            Constants.HOLESKY_EL_DELEGATION_MANAGER,
            address(new IsolatedEigenLayerWstETHVault(Constants.WSTETH())),
            address(
                new EigenLayerWstETHWithdrawalQueue(
                    address(claimer), Constants.HOLESKY_EL_DELEGATION_MANAGER
                )
            ),
            vm.createWallet("proxyAdmin").addr
        );
        EigenLayerAdapter eigenLayerAdapter = new EigenLayerAdapter(
            address(factory),
            address(vault),
            IStrategyManager(Constants.HOLESKY_EL_STRATEGY_MANAGER),
            IRewardsCoordinator(Constants.HOLESKY_EL_REWARDS_COORDINATOR)
        );
        ERC4626Adapter erc4626Adapter = new ERC4626Adapter(address(vault));

        vault.initialize(
            IMultiVault.InitParams({
                admin: vaultAdmin,
                limit: type(uint256).max,
                depositPause: false,
                withdrawalPause: false,
                depositWhitelist: false,
                asset: Constants.WSTETH(),
                name: "MultiVault test",
                symbol: "MVT",
                depositStrategy: address(strategy),
                withdrawalStrategy: address(strategy),
                rebalanceStrategy: address(strategy),
                defaultCollateral: Constants.WSTETH_SYMBIOTIC_COLLATERAL(),
                symbioticAdapter: address(symbioticAdapter),
                eigenLayerAdapter: address(eigenLayerAdapter),
                erc4626Adapter: address(erc4626Adapter)
            })
        );

        vm.startPrank(vaultAdmin);

        vm.expectRevert();
        vault.setRebalanceStrategy(address(strategy));

        assertEq(address(vault.rebalanceStrategy()), address(strategy));

        vault.grantRole(vault.SET_STRATEGY_ROLE(), vaultAdmin);
        vault.setRebalanceStrategy(address(strategy));

        assertEq(address(vault.rebalanceStrategy()), address(strategy));

        vault.setRebalanceStrategy(address(123));

        assertEq(address(vault.rebalanceStrategy()), address(123));

        vm.expectRevert("MultiVault: rebalance strategy cannot be zero address");
        vault.setRebalanceStrategy(address(0));

        vm.stopPrank();
    }

    function testSetDefaultCollateral() external {
        MultiVault vault;
        {
            TransparentUpgradeableProxy c_ = new TransparentUpgradeableProxy(
                address(new MultiVault("test", 1)), vm.createWallet("proxyAdmin").addr, new bytes(0)
            );
            vault = MultiVault(address(c_));
        }
        address vaultAdmin = rnd.randAddress();
        RatiosStrategy strategy = new RatiosStrategy();
        Claimer claimer = new Claimer();
        SymbioticAdapter symbioticAdapter = new SymbioticAdapter(
            address(vault),
            Constants.symbioticDeployment().vaultFactory,
            address(new SymbioticWithdrawalQueue(address(new Claimer()))),
            vm.createWallet("proxyAdmin").addr
        );
        address wsteth = Constants.WSTETH();
        address delegationManager = Constants.HOLESKY_EL_DELEGATION_MANAGER;
        IsolatedEigenLayerVaultFactory factory = new IsolatedEigenLayerVaultFactory(
            Constants.HOLESKY_EL_DELEGATION_MANAGER,
            address(new IsolatedEigenLayerWstETHVault(Constants.WSTETH())),
            address(
                new EigenLayerWstETHWithdrawalQueue(
                    address(claimer), Constants.HOLESKY_EL_DELEGATION_MANAGER
                )
            ),
            vm.createWallet("proxyAdmin").addr
        );
        EigenLayerAdapter eigenLayerAdapter = new EigenLayerAdapter(
            address(factory),
            address(vault),
            IStrategyManager(Constants.HOLESKY_EL_STRATEGY_MANAGER),
            IRewardsCoordinator(Constants.HOLESKY_EL_REWARDS_COORDINATOR)
        );
        ERC4626Adapter erc4626Adapter = new ERC4626Adapter(address(vault));

        vault.initialize(
            IMultiVault.InitParams({
                admin: vaultAdmin,
                limit: type(uint256).max,
                depositPause: false,
                withdrawalPause: false,
                depositWhitelist: false,
                asset: Constants.WSTETH(),
                name: "MultiVault test",
                symbol: "MVT",
                depositStrategy: address(strategy),
                withdrawalStrategy: address(strategy),
                rebalanceStrategy: address(strategy),
                defaultCollateral: address(0),
                symbioticAdapter: address(symbioticAdapter),
                eigenLayerAdapter: address(eigenLayerAdapter),
                erc4626Adapter: address(erc4626Adapter)
            })
        );

        vm.startPrank(vaultAdmin);

        address wstethDefaultCollateral = Constants.WSTETH_SYMBIOTIC_COLLATERAL();

        vm.expectRevert();
        vault.setDefaultCollateral(wstethDefaultCollateral);

        assertEq(address(vault.defaultCollateral()), address(0));

        vault.grantRole(vault.SET_DEFAULT_COLLATERAL_ROLE(), vaultAdmin);

        vm.expectRevert("MultiVault: default collateral already set or cannot be zero address");
        vault.setDefaultCollateral(address(0));

        vault.setDefaultCollateral(wstethDefaultCollateral);
        assertEq(address(vault.defaultCollateral()), wstethDefaultCollateral);

        vm.expectRevert("MultiVault: default collateral already set or cannot be zero address");
        vault.setDefaultCollateral(wstethDefaultCollateral);

        vm.stopPrank();
    }

    function testSetSymbioticAdapter() external {
        MultiVault vault;
        {
            TransparentUpgradeableProxy c_ = new TransparentUpgradeableProxy(
                address(new MultiVault("test", 1)), vm.createWallet("proxyAdmin").addr, new bytes(0)
            );
            vault = MultiVault(address(c_));
        }
        address vaultAdmin = rnd.randAddress();
        RatiosStrategy strategy = new RatiosStrategy();
        Claimer claimer = new Claimer();
        SymbioticAdapter symbioticAdapter = new SymbioticAdapter(
            address(vault),
            Constants.symbioticDeployment().vaultFactory,
            address(new SymbioticWithdrawalQueue(address(new Claimer()))),
            vm.createWallet("proxyAdmin").addr
        );
        address wsteth = Constants.WSTETH();
        address delegationManager = Constants.HOLESKY_EL_DELEGATION_MANAGER;
        IsolatedEigenLayerVaultFactory factory = new IsolatedEigenLayerVaultFactory(
            Constants.HOLESKY_EL_DELEGATION_MANAGER,
            address(new IsolatedEigenLayerWstETHVault(Constants.WSTETH())),
            address(
                new EigenLayerWstETHWithdrawalQueue(
                    address(claimer), Constants.HOLESKY_EL_DELEGATION_MANAGER
                )
            ),
            vm.createWallet("proxyAdmin").addr
        );
        EigenLayerAdapter eigenLayerAdapter = new EigenLayerAdapter(
            address(factory),
            address(vault),
            IStrategyManager(Constants.HOLESKY_EL_STRATEGY_MANAGER),
            IRewardsCoordinator(Constants.HOLESKY_EL_REWARDS_COORDINATOR)
        );
        ERC4626Adapter erc4626Adapter = new ERC4626Adapter(address(vault));

        vault.initialize(
            IMultiVault.InitParams({
                admin: vaultAdmin,
                limit: type(uint256).max,
                depositPause: false,
                withdrawalPause: false,
                depositWhitelist: false,
                asset: Constants.WSTETH(),
                name: "MultiVault test",
                symbol: "MVT",
                depositStrategy: address(strategy),
                withdrawalStrategy: address(strategy),
                rebalanceStrategy: address(strategy),
                defaultCollateral: Constants.WSTETH_SYMBIOTIC_COLLATERAL(),
                symbioticAdapter: address(symbioticAdapter),
                eigenLayerAdapter: address(eigenLayerAdapter),
                erc4626Adapter: address(erc4626Adapter)
            })
        );

        vm.startPrank(vaultAdmin);

        vm.expectRevert();
        vault.setSymbioticAdapter(address(symbioticAdapter));

        assertEq(address(vault.symbioticAdapter()), address(symbioticAdapter));

        vault.grantRole(vault.SET_ADAPTER_ROLE(), vaultAdmin);
        vault.setSymbioticAdapter(address(symbioticAdapter));

        assertEq(address(vault.symbioticAdapter()), address(symbioticAdapter));

        vault.setSymbioticAdapter(address(123));

        assertEq(address(vault.symbioticAdapter()), address(123));

        vm.expectRevert("MultiVault: adapter cannot be zero address");
        vault.setSymbioticAdapter(address(0));

        vm.stopPrank();
    }

    function testSetEigenLayerAdapter() external {
        MultiVault vault;
        {
            TransparentUpgradeableProxy c_ = new TransparentUpgradeableProxy(
                address(new MultiVault("test", 1)), vm.createWallet("proxyAdmin").addr, new bytes(0)
            );
            vault = MultiVault(address(c_));
        }
        address vaultAdmin = rnd.randAddress();
        RatiosStrategy strategy = new RatiosStrategy();
        Claimer claimer = new Claimer();
        SymbioticAdapter symbioticAdapter = new SymbioticAdapter(
            address(vault),
            Constants.symbioticDeployment().vaultFactory,
            address(new SymbioticWithdrawalQueue(address(new Claimer()))),
            vm.createWallet("proxyAdmin").addr
        );
        address wsteth = Constants.WSTETH();
        address delegationManager = Constants.HOLESKY_EL_DELEGATION_MANAGER;
        IsolatedEigenLayerVaultFactory factory = new IsolatedEigenLayerVaultFactory(
            Constants.HOLESKY_EL_DELEGATION_MANAGER,
            address(new IsolatedEigenLayerWstETHVault(Constants.WSTETH())),
            address(
                new EigenLayerWstETHWithdrawalQueue(
                    address(claimer), Constants.HOLESKY_EL_DELEGATION_MANAGER
                )
            ),
            vm.createWallet("proxyAdmin").addr
        );
        EigenLayerAdapter eigenLayerAdapter = new EigenLayerAdapter(
            address(factory),
            address(vault),
            IStrategyManager(Constants.HOLESKY_EL_STRATEGY_MANAGER),
            IRewardsCoordinator(Constants.HOLESKY_EL_REWARDS_COORDINATOR)
        );
        ERC4626Adapter erc4626Adapter = new ERC4626Adapter(address(vault));

        vault.initialize(
            IMultiVault.InitParams({
                admin: vaultAdmin,
                limit: type(uint256).max,
                depositPause: false,
                withdrawalPause: false,
                depositWhitelist: false,
                asset: Constants.WSTETH(),
                name: "MultiVault test",
                symbol: "MVT",
                depositStrategy: address(strategy),
                withdrawalStrategy: address(strategy),
                rebalanceStrategy: address(strategy),
                defaultCollateral: Constants.WSTETH_SYMBIOTIC_COLLATERAL(),
                symbioticAdapter: address(symbioticAdapter),
                eigenLayerAdapter: address(eigenLayerAdapter),
                erc4626Adapter: address(erc4626Adapter)
            })
        );

        vm.startPrank(vaultAdmin);

        vm.expectRevert();
        vault.setEigenLayerAdapter(address(eigenLayerAdapter));

        assertEq(address(vault.eigenLayerAdapter()), address(eigenLayerAdapter));

        vault.grantRole(vault.SET_ADAPTER_ROLE(), vaultAdmin);
        vault.setEigenLayerAdapter(address(eigenLayerAdapter));
        assertEq(address(vault.eigenLayerAdapter()), address(eigenLayerAdapter));

        vault.setEigenLayerAdapter(address(123));
        assertEq(address(vault.eigenLayerAdapter()), address(123));

        vm.expectRevert("MultiVault: adapter cannot be zero address");
        vault.setEigenLayerAdapter(address(0));

        vm.stopPrank();
    }

    function testSetERC4626Adapter() external {
        MultiVault vault;
        {
            TransparentUpgradeableProxy c_ = new TransparentUpgradeableProxy(
                address(new MultiVault("test", 1)), vm.createWallet("proxyAdmin").addr, new bytes(0)
            );
            vault = MultiVault(address(c_));
        }
        address vaultAdmin = rnd.randAddress();
        RatiosStrategy strategy = new RatiosStrategy();
        Claimer claimer = new Claimer();
        SymbioticAdapter symbioticAdapter = new SymbioticAdapter(
            address(vault),
            Constants.symbioticDeployment().vaultFactory,
            address(new SymbioticWithdrawalQueue(address(new Claimer()))),
            vm.createWallet("proxyAdmin").addr
        );
        address wsteth = Constants.WSTETH();
        address delegationManager = Constants.HOLESKY_EL_DELEGATION_MANAGER;
        IsolatedEigenLayerVaultFactory factory = new IsolatedEigenLayerVaultFactory(
            Constants.HOLESKY_EL_DELEGATION_MANAGER,
            address(new IsolatedEigenLayerWstETHVault(Constants.WSTETH())),
            address(
                new EigenLayerWstETHWithdrawalQueue(
                    address(claimer), Constants.HOLESKY_EL_DELEGATION_MANAGER
                )
            ),
            vm.createWallet("proxyAdmin").addr
        );
        EigenLayerAdapter eigenLayerAdapter = new EigenLayerAdapter(
            address(factory),
            address(vault),
            IStrategyManager(Constants.HOLESKY_EL_STRATEGY_MANAGER),
            IRewardsCoordinator(Constants.HOLESKY_EL_REWARDS_COORDINATOR)
        );
        ERC4626Adapter erc4626Adapter = new ERC4626Adapter(address(vault));

        vault.initialize(
            IMultiVault.InitParams({
                admin: vaultAdmin,
                limit: type(uint256).max,
                depositPause: false,
                withdrawalPause: false,
                depositWhitelist: false,
                asset: Constants.WSTETH(),
                name: "MultiVault test",
                symbol: "MVT",
                depositStrategy: address(strategy),
                withdrawalStrategy: address(strategy),
                rebalanceStrategy: address(strategy),
                defaultCollateral: Constants.WSTETH_SYMBIOTIC_COLLATERAL(),
                symbioticAdapter: address(symbioticAdapter),
                eigenLayerAdapter: address(eigenLayerAdapter),
                erc4626Adapter: address(erc4626Adapter)
            })
        );

        vm.startPrank(vaultAdmin);

        vm.expectRevert();
        vault.setERC4626Adapter(address(erc4626Adapter));

        assertEq(address(vault.erc4626Adapter()), address(erc4626Adapter));

        vault.grantRole(vault.SET_ADAPTER_ROLE(), vaultAdmin);
        vault.setERC4626Adapter(address(erc4626Adapter));
        assertEq(address(vault.erc4626Adapter()), address(erc4626Adapter));

        vault.setERC4626Adapter(address(123));
        assertEq(address(vault.erc4626Adapter()), address(123));

        vm.expectRevert("MultiVault: adapter cannot be zero address");
        vault.setERC4626Adapter(address(0));

        vm.stopPrank();
    }

    function testSetRewardsData() external {
        MultiVault vault;
        {
            TransparentUpgradeableProxy c_ = new TransparentUpgradeableProxy(
                address(new MultiVault("test", 1)), vm.createWallet("proxyAdmin").addr, new bytes(0)
            );
            vault = MultiVault(address(c_));
        }
        address vaultAdmin = rnd.randAddress();
        RatiosStrategy strategy = new RatiosStrategy();
        Claimer claimer = new Claimer();
        SymbioticAdapter symbioticAdapter = new SymbioticAdapter(
            address(vault),
            Constants.symbioticDeployment().vaultFactory,
            address(new SymbioticWithdrawalQueue(address(new Claimer()))),
            vm.createWallet("proxyAdmin").addr
        );
        address wsteth = Constants.WSTETH();
        address delegationManager = Constants.HOLESKY_EL_DELEGATION_MANAGER;
        IsolatedEigenLayerVaultFactory factory = new IsolatedEigenLayerVaultFactory(
            Constants.HOLESKY_EL_DELEGATION_MANAGER,
            address(new IsolatedEigenLayerWstETHVault(Constants.WSTETH())),
            address(
                new EigenLayerWstETHWithdrawalQueue(
                    address(claimer), Constants.HOLESKY_EL_DELEGATION_MANAGER
                )
            ),
            vm.createWallet("proxyAdmin").addr
        );
        EigenLayerAdapter eigenLayerAdapter = new EigenLayerAdapter(
            address(factory),
            address(vault),
            IStrategyManager(Constants.HOLESKY_EL_STRATEGY_MANAGER),
            IRewardsCoordinator(Constants.HOLESKY_EL_REWARDS_COORDINATOR)
        );
        ERC4626Adapter erc4626Adapter = new ERC4626Adapter(address(vault));

        vault.initialize(
            IMultiVault.InitParams({
                admin: vaultAdmin,
                limit: type(uint256).max,
                depositPause: false,
                withdrawalPause: false,
                depositWhitelist: false,
                asset: Constants.WSTETH(),
                name: "MultiVault test",
                symbol: "MVT",
                depositStrategy: address(strategy),
                withdrawalStrategy: address(strategy),
                rebalanceStrategy: address(strategy),
                defaultCollateral: Constants.WSTETH_SYMBIOTIC_COLLATERAL(),
                symbioticAdapter: address(symbioticAdapter),
                eigenLayerAdapter: address(eigenLayerAdapter),
                erc4626Adapter: address(erc4626Adapter)
            })
        );

        vm.startPrank(vaultAdmin);

        vm.expectRevert();
        vault.setRewardsData(
            0,
            IMultiVaultStorage.RewardData({
                token: address(1),
                curatorFeeD6: 0,
                distributionFarm: address(2),
                curatorTreasury: address(0),
                protocol: IMultiVaultStorage.Protocol.SYMBIOTIC,
                data: new bytes(0)
            })
        );

        vault.grantRole(vault.SET_FARM_ROLE(), vaultAdmin);
        vm.expectRevert("MultiVault: curator fee exceeds 100%");
        vault.setRewardsData(
            0,
            IMultiVaultStorage.RewardData({
                token: address(1),
                curatorFeeD6: 1e6 + 1,
                distributionFarm: address(0),
                curatorTreasury: address(0),
                protocol: IMultiVaultStorage.Protocol.SYMBIOTIC,
                data: new bytes(0)
            })
        );

        vm.expectRevert("MultiVault: distribution farm address cannot be zero");
        vault.setRewardsData(
            0,
            IMultiVaultStorage.RewardData({
                token: address(1),
                curatorFeeD6: 1e6,
                distributionFarm: address(0),
                curatorTreasury: address(0),
                protocol: IMultiVaultStorage.Protocol.SYMBIOTIC,
                data: new bytes(0)
            })
        );

        vm.expectRevert("MultiVault: curator treasury address cannot be zero when fee is set");
        vault.setRewardsData(
            0,
            IMultiVaultStorage.RewardData({
                token: address(1),
                curatorFeeD6: 1e6,
                distributionFarm: address(1),
                curatorTreasury: address(0),
                protocol: IMultiVaultStorage.Protocol.SYMBIOTIC,
                data: new bytes(0)
            })
        );

        vm.expectRevert("SymbioticAdapter: invalid reward data");
        vault.setRewardsData(
            0,
            IMultiVaultStorage.RewardData({
                token: address(1),
                curatorFeeD6: 1e6,
                distributionFarm: address(1),
                curatorTreasury: address(2),
                protocol: IMultiVaultStorage.Protocol.SYMBIOTIC,
                data: new bytes(0)
            })
        );

        vm.expectRevert("SymbioticAdapter: invalid reward data");
        vault.setRewardsData(
            0,
            IMultiVaultStorage.RewardData({
                token: address(1),
                curatorFeeD6: 1e6,
                distributionFarm: address(1),
                curatorTreasury: address(2),
                protocol: IMultiVaultStorage.Protocol.SYMBIOTIC,
                data: abi.encode(address(0))
            })
        );

        vault.setRewardsData(
            0,
            IMultiVaultStorage.RewardData({
                token: address(1),
                curatorFeeD6: 1e6,
                distributionFarm: address(1),
                curatorTreasury: address(2),
                protocol: IMultiVaultStorage.Protocol.SYMBIOTIC,
                data: abi.encode(address(1))
            })
        );

        vm.expectRevert("EigenLayerAdapter: invalid reward data");
        vault.setRewardsData(
            0,
            IMultiVaultStorage.RewardData({
                token: address(1),
                curatorFeeD6: 1e6,
                distributionFarm: address(1),
                curatorTreasury: address(2),
                protocol: IMultiVaultStorage.Protocol.EIGEN_LAYER,
                data: new bytes(0)
            })
        );

        vm.expectRevert("EigenLayerAdapter: invalid reward data");
        vault.setRewardsData(
            0,
            IMultiVaultStorage.RewardData({
                token: address(1),
                curatorFeeD6: 1e6,
                distributionFarm: address(1),
                curatorTreasury: address(2),
                protocol: IMultiVaultStorage.Protocol.EIGEN_LAYER,
                data: abi.encode(address(0))
            })
        );

        vm.expectRevert("EigenLayerAdapter: invalid reward data");
        vault.setRewardsData(
            0,
            IMultiVaultStorage.RewardData({
                token: address(1),
                curatorFeeD6: 1e6,
                distributionFarm: address(1),
                curatorTreasury: address(2),
                protocol: IMultiVaultStorage.Protocol.EIGEN_LAYER,
                data: abi.encode(address(1))
            })
        );

        ISignatureUtils.SignatureWithExpiry memory signature;
        (address isolatedVault,) = factory.getOrCreate(
            address(vault),
            0x7D704507b76571a51d9caE8AdDAbBFd0ba0e63d3,
            0xbF8a8B0d0450c8812ADDf04E1BcB7BfBA0E82937,
            abi.encode(signature, bytes32(0))
        );

        vault.setRewardsData(
            0,
            IMultiVaultStorage.RewardData({
                token: address(1),
                curatorFeeD6: 1e6,
                distributionFarm: address(1),
                curatorTreasury: address(2),
                protocol: IMultiVaultStorage.Protocol.EIGEN_LAYER,
                data: abi.encode(isolatedVault)
            })
        );

        vm.expectRevert();
        vault.setRewardsData(
            0,
            IMultiVaultStorage.RewardData({
                token: address(1),
                curatorFeeD6: 1e6,
                distributionFarm: address(1),
                curatorTreasury: address(2),
                protocol: IMultiVaultStorage.Protocol.ERC4626,
                data: new bytes(0)
            })
        );

        // removal of rewards data
        vault.setRewardsData(
            0,
            IMultiVaultStorage.RewardData({
                token: address(0),
                curatorFeeD6: 1e6,
                distributionFarm: address(1),
                curatorTreasury: address(2),
                protocol: IMultiVaultStorage.Protocol.ERC4626,
                data: new bytes(0)
            })
        );

        vm.stopPrank();
    }

    function testPushRewards() external {
        MultiVault vault;
        {
            TransparentUpgradeableProxy c_ = new TransparentUpgradeableProxy(
                address(new MultiVault("test", 1)), vm.createWallet("proxyAdmin").addr, new bytes(0)
            );
            vault = MultiVault(address(c_));
        }
        address vaultAdmin = rnd.randAddress();
        RatiosStrategy strategy = new RatiosStrategy();
        Claimer claimer = new Claimer();
        SymbioticAdapter symbioticAdapter = new SymbioticAdapter(
            address(vault),
            Constants.symbioticDeployment().vaultFactory,
            address(new SymbioticWithdrawalQueue(address(new Claimer()))),
            vm.createWallet("proxyAdmin").addr
        );
        address wsteth = Constants.WSTETH();
        address delegationManager = Constants.HOLESKY_EL_DELEGATION_MANAGER;
        IsolatedEigenLayerVaultFactory factory = new IsolatedEigenLayerVaultFactory(
            Constants.HOLESKY_EL_DELEGATION_MANAGER,
            address(new IsolatedEigenLayerWstETHVault(Constants.WSTETH())),
            address(
                new EigenLayerWstETHWithdrawalQueue(
                    address(claimer), Constants.HOLESKY_EL_DELEGATION_MANAGER
                )
            ),
            vm.createWallet("proxyAdmin").addr
        );
        EigenLayerAdapter eigenLayerAdapter = new EigenLayerAdapter(
            address(factory),
            address(vault),
            IStrategyManager(Constants.HOLESKY_EL_STRATEGY_MANAGER),
            IRewardsCoordinator(Constants.HOLESKY_EL_REWARDS_COORDINATOR)
        );
        ERC4626Adapter erc4626Adapter = new ERC4626Adapter(address(vault));

        vault.initialize(
            IMultiVault.InitParams({
                admin: vaultAdmin,
                limit: type(uint256).max,
                depositPause: false,
                withdrawalPause: false,
                depositWhitelist: false,
                asset: Constants.WSTETH(),
                name: "MultiVault test",
                symbol: "MVT",
                depositStrategy: address(strategy),
                withdrawalStrategy: address(strategy),
                rebalanceStrategy: address(strategy),
                defaultCollateral: Constants.WSTETH_SYMBIOTIC_COLLATERAL(),
                symbioticAdapter: address(symbioticAdapter),
                eigenLayerAdapter: address(eigenLayerAdapter),
                erc4626Adapter: address(erc4626Adapter)
            })
        );

        address distributionFarm = rnd.randAddress();
        address curatorTreasury = rnd.randAddress();

        vm.startPrank(vaultAdmin);
        vault.grantRole(vault.SET_FARM_ROLE(), vaultAdmin);
        MockSymbioticFarm mockSymbioticFarm = new MockSymbioticFarm();
        vault.setRewardsData(
            0,
            IMultiVaultStorage.RewardData({
                token: Constants.WETH(),
                curatorFeeD6: 1e5,
                distributionFarm: distributionFarm,
                curatorTreasury: curatorTreasury,
                protocol: IMultiVaultStorage.Protocol.SYMBIOTIC,
                data: abi.encode(address(mockSymbioticFarm))
            })
        );

        deal(Constants.WETH(), address(mockSymbioticFarm), 1 ether);
        vm.stopPrank();

        IERC20 weth = IERC20(Constants.WETH());
        assertEq(weth.balanceOf(distributionFarm), 0, "distribution farm balance should be zero");
        assertEq(weth.balanceOf(curatorTreasury), 0, "curator treasury balance should be zero");

        vault.pushRewards(0, new bytes(0));

        assertEq(
            weth.balanceOf(distributionFarm),
            0.9 ether,
            "distribution farm balance should be 90% of 1 ether"
        );
        assertEq(
            weth.balanceOf(curatorTreasury),
            0.1 ether,
            "curator treasury balance should be 10% of 1 ether"
        );

        vault.pushRewards(0, new bytes(0));

        assertEq(
            weth.balanceOf(distributionFarm),
            0.9 ether,
            "distribution farm balance should not change"
        );
        assertEq(
            weth.balanceOf(curatorTreasury), 0.1 ether, "curator treasury balance should not change"
        );

        vm.expectRevert("MultiVault: farm not found");
        vault.pushRewards(1, new bytes(0));
    }

    function testDeposit() external {
        MultiVault vault;
        {
            TransparentUpgradeableProxy c_ = new TransparentUpgradeableProxy(
                address(new MultiVault("test", 1)), vm.createWallet("proxyAdmin").addr, new bytes(0)
            );
            vault = MultiVault(address(c_));
        }
        address vaultAdmin = rnd.randAddress();
        RatiosStrategy strategy = new RatiosStrategy();
        Claimer claimer = new Claimer();
        SymbioticAdapter symbioticAdapter = new SymbioticAdapter(
            address(vault),
            Constants.symbioticDeployment().vaultFactory,
            address(new SymbioticWithdrawalQueue(address(new Claimer()))),
            vm.createWallet("proxyAdmin").addr
        );
        IsolatedEigenLayerVaultFactory factory = new IsolatedEigenLayerVaultFactory(
            Constants.HOLESKY_EL_DELEGATION_MANAGER,
            address(new IsolatedEigenLayerWstETHVault(Constants.WSTETH())),
            address(
                new EigenLayerWstETHWithdrawalQueue(
                    address(claimer), Constants.HOLESKY_EL_DELEGATION_MANAGER
                )
            ),
            vm.createWallet("proxyAdmin").addr
        );
        EigenLayerAdapter eigenLayerAdapter = new EigenLayerAdapter(
            address(factory),
            address(vault),
            IStrategyManager(Constants.HOLESKY_EL_STRATEGY_MANAGER),
            IRewardsCoordinator(Constants.HOLESKY_EL_REWARDS_COORDINATOR)
        );
        ERC4626Adapter erc4626Adapter = new ERC4626Adapter(address(vault));
        vault.initialize(
            IMultiVault.InitParams({
                admin: vaultAdmin,
                limit: type(uint256).max,
                depositPause: false,
                withdrawalPause: false,
                depositWhitelist: false,
                asset: Constants.WSTETH(),
                name: "MultiVault test",
                symbol: "MVT",
                depositStrategy: address(strategy),
                withdrawalStrategy: address(strategy),
                rebalanceStrategy: address(strategy),
                defaultCollateral: Constants.WSTETH_SYMBIOTIC_COLLATERAL(),
                symbioticAdapter: address(symbioticAdapter),
                eigenLayerAdapter: address(eigenLayerAdapter),
                erc4626Adapter: address(erc4626Adapter)
            })
        );

        // deposit without subvaults

        address user = rnd.randAddress();

        vm.startPrank(user);

        IERC20 wsteth = IERC20(Constants.WSTETH());
        deal(address(wsteth), user, 1 ether);
        wsteth.approve(address(vault), type(uint256).max);
        vault.deposit(1 ether, user);
        IDefaultCollateral defaultCollateral = vault.defaultCollateral();
        assertEq(defaultCollateral.balanceOf(address(vault)), 1 ether);
        assertEq(wsteth.balanceOf(address(vault)), 0);
        assertEq(vault.balanceOf(user), 1 ether);

        uint256 leftover = defaultCollateral.limit() - defaultCollateral.totalSupply();

        deal(address(wsteth), user, 10000 ether);
        vault.deposit(10000 ether, user);
        assertEq(
            defaultCollateral.balanceOf(address(vault)) + wsteth.balanceOf(address(vault)),
            10001 ether
        );
        assertEq(defaultCollateral.balanceOf(address(vault)), 1 ether + leftover);
        assertEq(wsteth.balanceOf(address(vault)), 10000 ether - leftover);
        assertEq(vault.balanceOf(user), 10001 ether);

        deal(address(wsteth), user, 1 ether);
        vault.deposit(1 ether, user);
        assertEq(
            defaultCollateral.balanceOf(address(vault)) + wsteth.balanceOf(address(vault)),
            10002 ether
        );
        assertEq(defaultCollateral.balanceOf(address(vault)), 1 ether + leftover);
        assertEq(wsteth.balanceOf(address(vault)), 10001 ether - leftover);
        assertEq(vault.balanceOf(user), 10002 ether);

        vm.stopPrank();
    }

    function testWithdrawal() external {
        MultiVault vault;
        {
            TransparentUpgradeableProxy c_ = new TransparentUpgradeableProxy(
                address(new MultiVault("test", 1)), vm.createWallet("proxyAdmin").addr, new bytes(0)
            );
            vault = MultiVault(address(c_));
        }
        address vaultAdmin = rnd.randAddress();
        RatiosStrategy strategy = new RatiosStrategy();
        Claimer claimer = new Claimer();
        SymbioticAdapter symbioticAdapter = new SymbioticAdapter(
            address(vault),
            Constants.symbioticDeployment().vaultFactory,
            address(new SymbioticWithdrawalQueue(address(new Claimer()))),
            vm.createWallet("proxyAdmin").addr
        );
        IsolatedEigenLayerVaultFactory factory = new IsolatedEigenLayerVaultFactory(
            Constants.HOLESKY_EL_DELEGATION_MANAGER,
            address(new IsolatedEigenLayerWstETHVault(Constants.WSTETH())),
            address(
                new EigenLayerWstETHWithdrawalQueue(
                    address(claimer), Constants.HOLESKY_EL_DELEGATION_MANAGER
                )
            ),
            vm.createWallet("proxyAdmin").addr
        );
        EigenLayerAdapter eigenLayerAdapter = new EigenLayerAdapter(
            address(factory),
            address(vault),
            IStrategyManager(Constants.HOLESKY_EL_STRATEGY_MANAGER),
            IRewardsCoordinator(Constants.HOLESKY_EL_REWARDS_COORDINATOR)
        );
        ERC4626Adapter erc4626Adapter = new ERC4626Adapter(address(vault));
        vault.initialize(
            IMultiVault.InitParams({
                admin: vaultAdmin,
                limit: type(uint256).max,
                depositPause: false,
                withdrawalPause: false,
                depositWhitelist: false,
                asset: Constants.WSTETH(),
                name: "MultiVault test",
                symbol: "MVT",
                depositStrategy: address(strategy),
                withdrawalStrategy: address(strategy),
                rebalanceStrategy: address(strategy),
                defaultCollateral: Constants.WSTETH_SYMBIOTIC_COLLATERAL(),
                symbioticAdapter: address(symbioticAdapter),
                eigenLayerAdapter: address(eigenLayerAdapter),
                erc4626Adapter: address(erc4626Adapter)
            })
        );

        // deposit without subvaults

        address user = rnd.randAddress();

        vm.startPrank(user);

        IERC20 wsteth = IERC20(Constants.WSTETH());
        deal(address(wsteth), user, 20001 ether);
        wsteth.approve(address(vault), type(uint256).max);

        vault.deposit(1 ether, user);
        vault.redeem(vault.balanceOf(user), user, user);

        vault.deposit(10000 ether, user);
        vault.redeem(vault.balanceOf(user), user, user);

        vault.deposit(20000 ether, user);
        address user2 = rnd.randAddress();
        vault.approve(user2, 10000 ether);
        vm.stopPrank();

        vm.startPrank(user2);
        vault.redeem(vault.balanceOf(user2), user2, user);
        vm.stopPrank();

        vm.startPrank(vaultAdmin);
        vault.grantRole(vault.ADD_SUBVAULT_ROLE(), vaultAdmin);
        vault.grantRole(vault.REBALANCE_ROLE(), vaultAdmin);
        vault.grantRole(strategy.RATIOS_STRATEGY_SET_RATIOS_ROLE(), vaultAdmin);

        (address symbioticVault,,,) =
            symbioticHelper.createDefaultSymbioticVault(Constants.WSTETH());
        vault.addSubvault(symbioticVault, IMultiVaultStorage.Protocol.SYMBIOTIC);
        address[] memory subvaults = new address[](1);
        subvaults[0] = symbioticVault;
        IRatiosStrategy.Ratio[] memory ratios = new IRatiosStrategy.Ratio[](1);
        ratios[0] = IRatiosStrategy.Ratio(0, 1 ether);
        strategy.setRatios(address(vault), subvaults, ratios);
        vault.rebalance();
        ratios[0] = IRatiosStrategy.Ratio(0, 0.5 ether);
        strategy.setRatios(address(vault), subvaults, ratios);
        vault.rebalance();
        skip(3 weeks);
        vm.stopPrank();

        vm.startPrank(user);
        vault.redeem(vault.balanceOf(user), user, user);
        vault.withdraw(0, user, user);
        vault.deposit(0, user);
        vault.deposit(0, user, user);
        vault.mint(0, user);
        // vault.maxDeposit(0);
        // vault.assetsOf(0);
        vault.totalAssets();

        vm.stopPrank();
    }
}
