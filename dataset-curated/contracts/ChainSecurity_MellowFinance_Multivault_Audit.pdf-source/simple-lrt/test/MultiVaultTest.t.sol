// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "./Imports.sol";
import "./mocks/MockERC4626.sol";

contract MultiVaultTest is Test {
    using RandomLib for RandomLib.Storage;

    string private constant NAME = "MultiVaultTest";
    uint256 private constant VERSION = 1;

    RandomLib.Storage private rnd;

    address private admin = vm.createWallet("multi-vault-admin").addr;
    uint256 private limit = 1000 ether;
    address private wsteth = 0x8d09a4502Cc8Cf1547aD300E066060D043f6982D;
    address private vaultConfigurator = 0xD2191FE92987171691d552C219b8caEf186eb9cA;

    address private delegationManager = 0xA44151489861Fe9e3055d95adC98FbD462B948e7;
    address private strategyManager = 0xdfB5f6CE42aAA7830E94ECFCcAd411beF4d4D5b6;
    address private rewardsCoordinator = 0xAcc1fb458a1317E886dB376Fc8141540537E68fE;

    struct CreationParams {
        address vaultOwner;
        address vaultAdmin;
        uint48 epochDuration;
        address asset;
        bool isDepositLimit;
        uint256 depositLimit;
    }

    function generateAddress(string memory key) internal returns (address) {
        return vm.createWallet(key).addr;
    }

    function createNewSymbioticVault(CreationParams memory params)
        public
        returns (address symbioticVault)
    {
        IFullRestakeDelegator.InitParams memory initParams = IFullRestakeDelegator.InitParams({
            baseParams: IBaseDelegator.BaseParams({
                defaultAdminRoleHolder: generateAddress("defaultAdminRoleHolder"),
                hook: address(0),
                hookSetRoleHolder: generateAddress("hookSetRoleHolder")
            }),
            networkLimitSetRoleHolders: new address[](0),
            operatorNetworkLimitSetRoleHolders: new address[](0)
        });
        (symbioticVault,,) = IVaultConfigurator(vaultConfigurator).create(
            IVaultConfigurator.InitParams({
                version: 1,
                owner: params.vaultOwner,
                vaultParams: abi.encode(
                    ISymbioticVault.InitParams({
                        collateral: params.asset,
                        burner: address(0),
                        epochDuration: params.epochDuration,
                        depositWhitelist: false,
                        isDepositLimit: params.isDepositLimit,
                        depositLimit: params.depositLimit,
                        defaultAdminRoleHolder: params.vaultAdmin,
                        depositWhitelistSetRoleHolder: params.vaultAdmin,
                        depositorWhitelistRoleHolder: params.vaultAdmin,
                        isDepositLimitSetRoleHolder: params.vaultAdmin,
                        depositLimitSetRoleHolder: params.vaultAdmin
                    })
                ),
                delegatorIndex: 0,
                delegatorParams: abi.encode(initParams),
                withSlasher: false,
                slasherIndex: 0,
                slasherParams: ""
            })
        );
    }

    function testMultiVaultSymbiotic() public {
        MultiVault mv;
        {
            TransparentUpgradeableProxy c_ = new TransparentUpgradeableProxy(
                address(new MultiVault(bytes32("MultiVaultTest"), VERSION)),
                vm.createWallet("proxyAdmin").addr,
                new bytes(0)
            );
            mv = MultiVault(address(c_));
        }

        Claimer claimer = new Claimer();
        SymbioticAdapter symbioticAdapter = new SymbioticAdapter(
            address(mv),
            Constants.symbioticDeployment().vaultFactory,
            address(new SymbioticWithdrawalQueue(address(claimer))),
            vm.createWallet("proxyAdmin").addr
        );
        IsolatedEigenLayerVaultFactory factory = new IsolatedEigenLayerVaultFactory(
            delegationManager,
            address(new IsolatedEigenLayerWstETHVault(wsteth)),
            address(new EigenLayerWstETHWithdrawalQueue(address(claimer), delegationManager)),
            vm.createWallet("proxyAdmin").addr
        );
        EigenLayerAdapter eigenLayerAdapter = new EigenLayerAdapter(
            address(factory),
            address(mv),
            IStrategyManager(strategyManager),
            IRewardsCoordinator(rewardsCoordinator)
        );

        address symbioticVault = createNewSymbioticVault(
            CreationParams({
                vaultOwner: admin,
                vaultAdmin: admin,
                epochDuration: 1 days,
                asset: wsteth,
                isDepositLimit: false,
                depositLimit: 0
            })
        );

        RatiosStrategy strategy = new RatiosStrategy();

        mv.initialize(
            IMultiVault.InitParams({
                admin: admin,
                limit: limit,
                depositPause: false,
                withdrawalPause: false,
                depositWhitelist: false,
                asset: wsteth,
                name: NAME,
                symbol: NAME,
                depositStrategy: address(strategy),
                withdrawalStrategy: address(strategy),
                rebalanceStrategy: address(strategy),
                defaultCollateral: address(0),
                symbioticAdapter: address(symbioticAdapter),
                eigenLayerAdapter: address(eigenLayerAdapter),
                erc4626Adapter: address(0)
            })
        );

        vm.startPrank(admin);

        mv.grantRole(keccak256("ADD_SUBVAULT_ROLE"), admin);
        mv.grantRole(keccak256("REMOVE_SUBVAULT_ROLE"), admin);
        mv.grantRole(keccak256("RATIOS_STRATEGY_SET_RATIOS_ROLE"), admin);
        mv.grantRole(keccak256("REBALANCE_ROLE"), admin);

        address[] memory subvaults = new address[](1);
        subvaults[0] = symbioticVault;
        RatiosStrategy.Ratio[] memory ratios = new RatiosStrategy.Ratio[](1);
        ratios[0].minRatioD18 = 0.94 ether;
        ratios[0].maxRatioD18 = 0.95 ether;

        mv.addSubvault(symbioticVault, IMultiVaultStorage.Protocol.SYMBIOTIC);
        strategy.setRatios(address(mv), subvaults, ratios);
        mv.removeSubvault(symbioticVault);
        mv.addSubvault(symbioticVault, IMultiVaultStorage.Protocol.SYMBIOTIC);

        address isolatedVault;
        {
            ISignatureUtils.SignatureWithExpiry memory signature;
            bytes32 salt = 0;
            address operator = 0xbF8a8B0d0450c8812ADDf04E1BcB7BfBA0E82937; // random operator
            (isolatedVault,) = factory.getOrCreate(
                address(mv),
                0x7D704507b76571a51d9caE8AdDAbBFd0ba0e63d3,
                operator,
                abi.encode(signature, salt)
            );
        }
        mv.addSubvault(isolatedVault, IMultiVaultStorage.Protocol.EIGEN_LAYER);

        mv.rebalance();

        for (uint256 i = 0; i < 7; i++) {
            uint256 amount = 1 ether;
            deal(wsteth, admin, amount);
            IERC20(wsteth).approve(address(mv), amount);
            mv.deposit(amount, admin, admin);
            if (i == 0) {
                deal(wsteth, address(mv), 100 ether);
            } else if (i == 7) {
                deal(wsteth, address(mv), 0);
            }
            mv.rebalance();
            mv.redeem(mv.balanceOf(admin), admin, admin);
        }

        skip(3 days);

        uint256[] memory vaults = new uint256[](2);
        vaults[1] = 1;

        claimer.multiAcceptAndClaim(
            address(mv), vaults, new uint256[][](2), admin, type(uint256).max
        );

        skip(3 days);

        claimer.multiAcceptAndClaim(
            address(mv), vaults, new uint256[][](2), admin, type(uint256).max
        );

        vm.stopPrank();
    }

    function testMultiVaultEigenLayer() public {
        MultiVault mv;
        {
            TransparentUpgradeableProxy c_ = new TransparentUpgradeableProxy(
                address(new MultiVault(bytes32("MultiVaultTest"), VERSION)),
                vm.createWallet("proxyAdmin").addr,
                new bytes(0)
            );
            mv = MultiVault(address(c_));
        }

        Claimer claimer = new Claimer();
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
        EigenLayerWstETHAdapter eigenLayerAdapter = new EigenLayerWstETHAdapter(
            address(factory),
            address(mv),
            IStrategyManager(strategyManager),
            IRewardsCoordinator(rewardsCoordinator),
            wsteth
        );

        RatiosStrategy strategy = new RatiosStrategy();

        mv.initialize(
            IMultiVault.InitParams({
                admin: admin,
                limit: limit,
                depositPause: false,
                withdrawalPause: false,
                depositWhitelist: false,
                asset: wsteth,
                name: NAME,
                symbol: NAME,
                depositStrategy: address(strategy),
                withdrawalStrategy: address(strategy),
                rebalanceStrategy: address(strategy),
                defaultCollateral: address(0),
                symbioticAdapter: address(0),
                eigenLayerAdapter: address(eigenLayerAdapter),
                erc4626Adapter: address(0)
            })
        );

        vm.startPrank(admin);

        mv.grantRole(keccak256("ADD_SUBVAULT_ROLE"), admin);
        mv.grantRole(keccak256("REMOVE_SUBVAULT_ROLE"), admin);
        mv.grantRole(keccak256("RATIOS_STRATEGY_SET_RATIOS_ROLE"), admin);
        mv.grantRole(keccak256("REBALANCE_ROLE"), admin);

        address isolatedVault;
        address withdrawalQueue;
        {
            ISignatureUtils.SignatureWithExpiry memory signature;
            bytes32 salt = 0;
            address operator = 0xbF8a8B0d0450c8812ADDf04E1BcB7BfBA0E82937; // random operator
            address eigenStrategy = 0x7D704507b76571a51d9caE8AdDAbBFd0ba0e63d3;
            (isolatedVault, withdrawalQueue) = factory.getOrCreate(
                address(mv), eigenStrategy, operator, abi.encode(signature, salt)
            );
        }

        address[] memory subvaults = new address[](1);
        subvaults[0] = isolatedVault;
        RatiosStrategy.Ratio[] memory ratios = new RatiosStrategy.Ratio[](1);
        ratios[0].minRatioD18 = 0.94 ether;
        ratios[0].maxRatioD18 = 0.95 ether;

        mv.addSubvault(isolatedVault, IMultiVaultStorage.Protocol.EIGEN_LAYER);
        strategy.setRatios(address(mv), subvaults, ratios);

        mv.rebalance();

        for (uint256 i = 0; i < IEigenLayerWithdrawalQueue(withdrawalQueue).MAX_WITHDRAWALS(); i++)
        {
            uint256 amount = 1 ether;
            deal(wsteth, admin, amount);
            IERC20(wsteth).approve(address(mv), amount);
            mv.deposit(amount, admin, admin);
            mv.rebalance();
            mv.redeem(mv.balanceOf(admin) / 2, admin, admin);
        }

        vm.expectRevert("EigenLayerWithdrawalQueue: max withdrawal requests reached");
        mv.redeem(0.1 ether, admin, admin);

        skip(3 days);

        uint256[] memory vaults = new uint256[](1);

        claimer.multiAcceptAndClaim(
            address(mv), vaults, new uint256[][](1), admin, type(uint256).max
        );

        skip(3 days);

        claimer.multiAcceptAndClaim(
            address(mv), vaults, new uint256[][](1), admin, type(uint256).max
        );

        vm.stopPrank();
    }

    function testEigenLayerGasTest() public {
        MultiVault mv;
        {
            TransparentUpgradeableProxy c_ = new TransparentUpgradeableProxy(
                address(new MultiVault(bytes32("MultiVaultTest"), VERSION)),
                vm.createWallet("proxyAdmin").addr,
                new bytes(0)
            );
            mv = MultiVault(address(c_));
        }

        Claimer claimer = new Claimer();
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
        EigenLayerWstETHAdapter eigenLayerAdapter = new EigenLayerWstETHAdapter(
            address(factory),
            address(mv),
            IStrategyManager(strategyManager),
            IRewardsCoordinator(rewardsCoordinator),
            wsteth
        );

        RatiosStrategy strategy = new RatiosStrategy();

        mv.initialize(
            IMultiVault.InitParams({
                admin: admin,
                limit: limit,
                depositPause: false,
                withdrawalPause: false,
                depositWhitelist: false,
                asset: wsteth,
                name: NAME,
                symbol: NAME,
                depositStrategy: address(strategy),
                withdrawalStrategy: address(strategy),
                rebalanceStrategy: address(strategy),
                defaultCollateral: address(0),
                symbioticAdapter: address(0),
                eigenLayerAdapter: address(eigenLayerAdapter),
                erc4626Adapter: address(0)
            })
        );

        vm.startPrank(admin);

        mv.grantRole(keccak256("ADD_SUBVAULT_ROLE"), admin);
        mv.grantRole(keccak256("REMOVE_SUBVAULT_ROLE"), admin);
        mv.grantRole(keccak256("RATIOS_STRATEGY_SET_RATIOS_ROLE"), admin);
        mv.grantRole(keccak256("REBALANCE_ROLE"), admin);

        address isolatedVault;
        address withdrawalQueue;
        {
            ISignatureUtils.SignatureWithExpiry memory signature;
            bytes32 salt = 0;
            address operator = 0xbF8a8B0d0450c8812ADDf04E1BcB7BfBA0E82937; // random operator
            address eigenStrategy = 0x7D704507b76571a51d9caE8AdDAbBFd0ba0e63d3;
            (isolatedVault, withdrawalQueue) = factory.getOrCreate(
                address(mv), eigenStrategy, operator, abi.encode(signature, salt)
            );
        }

        address[] memory subvaults = new address[](1);
        subvaults[0] = isolatedVault;
        RatiosStrategy.Ratio[] memory ratios = new RatiosStrategy.Ratio[](1);
        ratios[0].minRatioD18 = 1 ether;
        ratios[0].maxRatioD18 = 1 ether;

        mv.addSubvault(isolatedVault, IMultiVaultStorage.Protocol.EIGEN_LAYER);
        strategy.setRatios(address(mv), subvaults, ratios);

        mv.rebalance();

        {
            uint256 amount = 128 ether;
            deal(wsteth, admin, amount);
            IERC20(wsteth).approve(address(mv), amount);
            mv.deposit(amount, admin, admin);
        }

        uint256 n = IEigenLayerWithdrawalQueue(withdrawalQueue).MAX_WITHDRAWALS();
        for (uint256 i = 0; i < n; i++) {
            mv.redeem(mv.balanceOf(admin) / (n + 1), admin, admin);
        }

        uint256 shares = mv.balanceOf(admin);
        vm.expectRevert("EigenLayerWithdrawalQueue: max withdrawal requests reached");
        mv.redeem(shares, admin, admin);

        vm.roll(block.number + 10000);

        uint256 gasCost = gasleft();
        claimer.multiAcceptAndClaim(
            address(mv), new uint256[](1), new uint256[][](1), admin, type(uint256).max
        );
        console2.log("claim price:", gasCost - gasleft());
        vm.stopPrank();
    }

    function testMultiVaultEigenLayerUndelegate() public {
        MultiVault mv;
        {
            TransparentUpgradeableProxy c_ = new TransparentUpgradeableProxy(
                address(new MultiVault(bytes32("MultiVaultTest"), VERSION)),
                vm.createWallet("proxyAdmin").addr,
                new bytes(0)
            );
            mv = MultiVault(address(c_));
        }

        Claimer claimer = new Claimer();
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
        EigenLayerWstETHAdapter eigenLayerAdapter = new EigenLayerWstETHAdapter(
            address(factory),
            address(mv),
            IStrategyManager(strategyManager),
            IRewardsCoordinator(rewardsCoordinator),
            wsteth
        );

        RatiosStrategy strategy = new RatiosStrategy();

        mv.initialize(
            IMultiVault.InitParams({
                admin: admin,
                limit: limit,
                depositPause: false,
                withdrawalPause: false,
                depositWhitelist: false,
                asset: wsteth,
                name: NAME,
                symbol: NAME,
                depositStrategy: address(strategy),
                withdrawalStrategy: address(strategy),
                rebalanceStrategy: address(strategy),
                defaultCollateral: address(0),
                symbioticAdapter: address(0),
                eigenLayerAdapter: address(eigenLayerAdapter),
                erc4626Adapter: address(0)
            })
        );

        vm.startPrank(admin);

        mv.grantRole(keccak256("ADD_SUBVAULT_ROLE"), admin);
        mv.grantRole(keccak256("REMOVE_SUBVAULT_ROLE"), admin);
        mv.grantRole(keccak256("RATIOS_STRATEGY_SET_RATIOS_ROLE"), admin);
        mv.grantRole(keccak256("REBALANCE_ROLE"), admin);

        address isolatedVault;
        address withdrawalQueue;
        {
            ISignatureUtils.SignatureWithExpiry memory signature;
            bytes32 salt = 0;
            address operator = 0xbF8a8B0d0450c8812ADDf04E1BcB7BfBA0E82937; // random operator
            address eigenStrategy = 0x7D704507b76571a51d9caE8AdDAbBFd0ba0e63d3;
            (isolatedVault, withdrawalQueue) = factory.getOrCreate(
                address(mv), eigenStrategy, operator, abi.encode(signature, salt)
            );
        }

        address[] memory subvaults = new address[](1);
        subvaults[0] = isolatedVault;
        RatiosStrategy.Ratio[] memory ratios = new RatiosStrategy.Ratio[](1);
        ratios[0].minRatioD18 = 0.94 ether;
        ratios[0].maxRatioD18 = 0.95 ether;

        mv.addSubvault(isolatedVault, IMultiVaultStorage.Protocol.EIGEN_LAYER);
        strategy.setRatios(address(mv), subvaults, ratios);

        mv.rebalance();

        for (uint256 i = 0; i < 1; i++) {
            uint256 amount = 1 ether;
            deal(wsteth, admin, amount);
            IERC20(wsteth).approve(address(mv), amount);
            mv.deposit(amount, admin, admin);
        }
        vm.stopPrank();

        uint256 tvlBefore = mv.totalAssets();
        EigenLayerWithdrawalQueue queue = EigenLayerWithdrawalQueue(withdrawalQueue);

        uint256 shares = IStrategy(queue.strategy()).shares(queue.isolatedVault());
        uint256 blockNumber = block.number;

        {
            vm.startPrank(0xbF8a8B0d0450c8812ADDf04E1BcB7BfBA0E82937);
            IDelegationManager(Constants.HOLESKY_EL_DELEGATION_MANAGER).undelegate(isolatedVault);
            vm.stopPrank();
        }

        vm.expectRevert();
        mv.totalAssets();

        IEigenLayerWithdrawalQueue(withdrawalQueue).shutdown(uint32(blockNumber), shares);

        assertEq(tvlBefore, mv.totalAssets());

        {
            address delegationManagerOwner =
                Ownable(Constants.HOLESKY_EL_DELEGATION_MANAGER).owner();
            vm.startPrank(delegationManagerOwner);
            IDelegationManager(Constants.HOLESKY_EL_DELEGATION_MANAGER).setMinWithdrawalDelayBlocks(
                0
            );
            IStrategy[] memory strategies = new IStrategy[](1);
            strategies[0] = IStrategy(queue.strategy());
            IDelegationManager(Constants.HOLESKY_EL_DELEGATION_MANAGER)
                .setStrategyWithdrawalDelayBlocks(strategies, new uint256[](1));
            vm.stopPrank();
        }

        queue.pull(0);
        assertEq(tvlBefore, mv.totalAssets() + 1 wei); // steth->wsteth rounding
    }

    function testMultiVaultEigenLayerNoPause() public {
        MultiVault mv;
        {
            TransparentUpgradeableProxy c_ = new TransparentUpgradeableProxy(
                address(new MultiVault(bytes32("MultiVaultTest"), VERSION)),
                vm.createWallet("proxyAdmin").addr,
                new bytes(0)
            );
            mv = MultiVault(address(c_));
        }

        Claimer claimer = new Claimer();
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
        EigenLayerWstETHAdapter eigenLayerAdapter = new EigenLayerWstETHAdapter(
            address(factory),
            address(mv),
            IStrategyManager(strategyManager),
            IRewardsCoordinator(rewardsCoordinator),
            wsteth
        );

        RatiosStrategy strategy = new RatiosStrategy();

        mv.initialize(
            IMultiVault.InitParams({
                admin: admin,
                limit: limit,
                depositPause: false,
                withdrawalPause: false,
                depositWhitelist: false,
                asset: wsteth,
                name: NAME,
                symbol: NAME,
                depositStrategy: address(strategy),
                withdrawalStrategy: address(strategy),
                rebalanceStrategy: address(strategy),
                defaultCollateral: address(0),
                symbioticAdapter: address(0),
                eigenLayerAdapter: address(eigenLayerAdapter),
                erc4626Adapter: address(0)
            })
        );

        vm.startPrank(admin);

        mv.grantRole(keccak256("ADD_SUBVAULT_ROLE"), admin);
        mv.grantRole(keccak256("REMOVE_SUBVAULT_ROLE"), admin);
        mv.grantRole(keccak256("RATIOS_STRATEGY_SET_RATIOS_ROLE"), admin);
        mv.grantRole(keccak256("REBALANCE_ROLE"), admin);

        address isolatedVault;
        address delegationManagerOwner;
        address wq;
        {
            ISignatureUtils.SignatureWithExpiry memory signature;
            bytes32 salt = 0;
            address operator = 0xbF8a8B0d0450c8812ADDf04E1BcB7BfBA0E82937; // random operator
            address eigenStrategy = 0x7D704507b76571a51d9caE8AdDAbBFd0ba0e63d3;

            (isolatedVault, wq) = factory.getOrCreate(
                address(mv), eigenStrategy, operator, abi.encode(signature, salt)
            );

            vm.stopPrank();
            delegationManagerOwner = Ownable(Constants.HOLESKY_EL_DELEGATION_MANAGER).owner();
            vm.startPrank(delegationManagerOwner);
            IDelegationManager(Constants.HOLESKY_EL_DELEGATION_MANAGER).setMinWithdrawalDelayBlocks(
                0
            );
            IStrategy[] memory strategies = new IStrategy[](1);
            strategies[0] = IStrategy(eigenStrategy);
            IDelegationManager(Constants.HOLESKY_EL_DELEGATION_MANAGER)
                .setStrategyWithdrawalDelayBlocks(strategies, new uint256[](1));
            vm.stopPrank();
            vm.startPrank(admin);
        }

        address[] memory subvaults = new address[](1);
        subvaults[0] = isolatedVault;
        RatiosStrategy.Ratio[] memory ratios = new RatiosStrategy.Ratio[](1);
        ratios[0].minRatioD18 = 0.94 ether;
        ratios[0].maxRatioD18 = 0.95 ether;

        mv.addSubvault(isolatedVault, IMultiVaultStorage.Protocol.EIGEN_LAYER);
        strategy.setRatios(address(mv), subvaults, ratios);

        mv.rebalance();

        for (uint256 i = 0; i < 500; i++) {
            uint256 t = uint256(keccak256(abi.encodePacked(blockhash(block.number - i - 1), i))) % 7;

            vm.startPrank(admin);
            if (t == 0) {
                uint256 amount = 1 ether;
                uint256 stethAmount = IWSTETH(Constants.WSTETH()).getStETHByWstETH(amount) + 1;
                deal(admin, stethAmount);
                Address.sendValue(payable(Constants.WSTETH()), stethAmount);
                IERC20(wsteth).approve(address(mv), amount);
                mv.deposit(amount, admin, admin);
            } else if (t == 1) {
                mv.rebalance();
            } else if (t == 2) {
                mv.redeem(mv.balanceOf(admin), admin, admin);
            } else if (t == 3) {
                skip(1 days);
            } else if (t == 4) {
                uint256[][] memory indices = new uint256[][](1);
                (,, indices[0]) =
                    EigenLayerWithdrawalQueue(wq).getAccountData(admin, 0, 0, type(uint256).max, 0);
                claimer.multiAcceptAndClaim(
                    address(mv), new uint256[](1), indices, admin, type(uint256).max
                );
            } else if (t == 5) {
                vm.stopPrank();
                vm.startPrank(delegationManagerOwner);
                IDelegationManager(Constants.HOLESKY_EL_DELEGATION_MANAGER)
                    .setMinWithdrawalDelayBlocks(0);
            } else if (t == 6) {
                vm.stopPrank();
                vm.startPrank(delegationManagerOwner);
                IDelegationManager(Constants.HOLESKY_EL_DELEGATION_MANAGER)
                    .setMinWithdrawalDelayBlocks(1);
            }
            vm.stopPrank();
        }
    }

    function _testFuzz_Eigen(uint256 seed_) public {
        rnd.seed = seed_;
        MultiVault mv;
        {
            TransparentUpgradeableProxy c_ = new TransparentUpgradeableProxy(
                address(new MultiVault(bytes32("MultiVaultTest"), VERSION)),
                vm.createWallet("proxyAdmin").addr,
                new bytes(0)
            );
            mv = MultiVault(address(c_));
        }

        Claimer claimer = new Claimer();
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
        EigenLayerWstETHAdapter eigenLayerAdapter = new EigenLayerWstETHAdapter(
            address(factory),
            address(mv),
            IStrategyManager(strategyManager),
            IRewardsCoordinator(rewardsCoordinator),
            wsteth
        );

        RatiosStrategy strategy = new RatiosStrategy();

        mv.initialize(
            IMultiVault.InitParams({
                admin: admin,
                limit: limit,
                depositPause: false,
                withdrawalPause: false,
                depositWhitelist: false,
                asset: wsteth,
                name: NAME,
                symbol: NAME,
                depositStrategy: address(strategy),
                withdrawalStrategy: address(strategy),
                rebalanceStrategy: address(strategy),
                defaultCollateral: address(0),
                symbioticAdapter: address(0),
                eigenLayerAdapter: address(eigenLayerAdapter),
                erc4626Adapter: address(0)
            })
        );

        vm.startPrank(admin);

        mv.grantRole(keccak256("ADD_SUBVAULT_ROLE"), admin);
        mv.grantRole(keccak256("REMOVE_SUBVAULT_ROLE"), admin);
        mv.grantRole(keccak256("RATIOS_STRATEGY_SET_RATIOS_ROLE"), admin);
        mv.grantRole(keccak256("REBALANCE_ROLE"), admin);

        address isolatedVault;
        address delegationManagerOwner;
        address wq;
        {
            ISignatureUtils.SignatureWithExpiry memory signature;
            bytes32 salt = 0;
            address operator = 0xbF8a8B0d0450c8812ADDf04E1BcB7BfBA0E82937; // random operator
            address eigenStrategy = 0x7D704507b76571a51d9caE8AdDAbBFd0ba0e63d3;

            (isolatedVault, wq) = factory.getOrCreate(
                address(mv), eigenStrategy, operator, abi.encode(signature, salt)
            );

            vm.stopPrank();
            delegationManagerOwner = Ownable(Constants.HOLESKY_EL_DELEGATION_MANAGER).owner();
            vm.startPrank(delegationManagerOwner);
            IDelegationManager(Constants.HOLESKY_EL_DELEGATION_MANAGER).setMinWithdrawalDelayBlocks(
                0
            );
            IStrategy[] memory strategies = new IStrategy[](1);
            strategies[0] = IStrategy(eigenStrategy);
            IDelegationManager(Constants.HOLESKY_EL_DELEGATION_MANAGER)
                .setStrategyWithdrawalDelayBlocks(strategies, new uint256[](1));
            vm.stopPrank();
            vm.startPrank(admin);
        }

        address[] memory subvaults = new address[](1);
        subvaults[0] = isolatedVault;
        RatiosStrategy.Ratio[] memory ratios = new RatiosStrategy.Ratio[](1);
        ratios[0].minRatioD18 = 0.94 ether;
        ratios[0].maxRatioD18 = 0.95 ether;

        mv.addSubvault(isolatedVault, IMultiVaultStorage.Protocol.EIGEN_LAYER);
        strategy.setRatios(address(mv), subvaults, ratios);

        mv.rebalance();

        for (uint256 i = 0; i < 50; i++) {
            uint256 t = rnd.randInt(7);

            vm.startPrank(admin);
            if (t == 0) {
                uint256 amount = 1 ether;
                uint256 stethAmount = IWSTETH(Constants.WSTETH()).getStETHByWstETH(amount) + 1;
                deal(admin, stethAmount);
                Address.sendValue(payable(Constants.WSTETH()), stethAmount);
                IERC20(wsteth).approve(address(mv), amount);
                mv.deposit(amount, admin, admin);
            } else if (t == 1) {
                mv.rebalance();
            } else if (t == 2) {
                if (rnd.randBool()) {
                    mv.redeem(mv.balanceOf(admin), admin, admin);
                } else {
                    uint256 lpAmount = mv.balanceOf(admin);
                    if (lpAmount == 0) {
                        continue;
                    }
                    uint256 iters = rnd.randInt(1, 10);
                    for (uint256 j = 0; j < iters; j++) {
                        uint256 amount = j + 1 == iters ? mv.balanceOf(admin) : lpAmount / iters;
                        try mv.redeem(amount, admin, admin) returns (uint256) {} catch {}
                    }
                }
            } else if (t == 3) {
                skip(1 days);
            } else if (t == 4) {
                uint256[][] memory indices = new uint256[][](1);
                (,, indices[0]) =
                    EigenLayerWithdrawalQueue(wq).getAccountData(admin, 0, 0, type(uint256).max, 0);
                claimer.multiAcceptAndClaim(
                    address(mv), new uint256[](1), indices, admin, type(uint256).max
                );
            } else if (t == 5) {
                vm.stopPrank();
                vm.startPrank(delegationManagerOwner);
                IDelegationManager(Constants.HOLESKY_EL_DELEGATION_MANAGER)
                    .setMinWithdrawalDelayBlocks(0);
            } else if (t == 6) {
                vm.stopPrank();
                vm.startPrank(delegationManagerOwner);
                IDelegationManager(Constants.HOLESKY_EL_DELEGATION_MANAGER)
                    .setMinWithdrawalDelayBlocks(1);
            }
            vm.stopPrank();
        }
    }

    function logState(MultiVault mv) internal view {
        console2.log("totalSupply: %d, totalAssets: %d", mv.totalSupply(), mv.totalAssets());
    }

    function testSymbioticVaults() public {
        MultiVault mv;
        {
            TransparentUpgradeableProxy c_ = new TransparentUpgradeableProxy(
                address(new MultiVault(bytes32("MultiVaultTest"), VERSION)),
                vm.createWallet("proxyAdmin").addr,
                new bytes(0)
            );
            mv = MultiVault(address(c_));
        }

        Claimer claimer = new Claimer();
        SymbioticAdapter symbioticAdapter = new SymbioticAdapter(
            address(mv),
            Constants.symbioticDeployment().vaultFactory,
            address(new SymbioticWithdrawalQueue(address(claimer))),
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
            address(mv),
            IStrategyManager(strategyManager),
            IRewardsCoordinator(rewardsCoordinator)
        );
        ERC4626Adapter erc4626Adapter = new ERC4626Adapter(address(mv));

        RatiosStrategy strategy = new RatiosStrategy();

        address defaultCollateral = 0x23E98253F372Ee29910e22986fe75Bb287b011fC;
        mv.initialize(
            IMultiVault.InitParams({
                admin: admin,
                limit: limit,
                depositPause: false,
                withdrawalPause: false,
                depositWhitelist: false,
                asset: wsteth,
                name: NAME,
                symbol: NAME,
                depositStrategy: address(strategy),
                withdrawalStrategy: address(strategy),
                rebalanceStrategy: address(strategy),
                defaultCollateral: defaultCollateral,
                symbioticAdapter: address(symbioticAdapter),
                eigenLayerAdapter: address(eigenLayerAdapter),
                erc4626Adapter: address(erc4626Adapter)
            })
        );

        vm.startPrank(admin);

        mv.grantRole(keccak256("ADD_SUBVAULT_ROLE"), admin);
        mv.grantRole(keccak256("REMOVE_SUBVAULT_ROLE"), admin);
        mv.grantRole(keccak256("RATIOS_STRATEGY_SET_RATIOS_ROLE"), admin);
        mv.grantRole(keccak256("REBALANCE_ROLE"), admin);

        uint256 n = 12;
        address[] memory subvaults = new address[](n + 1);

        for (uint256 i = 0; i < n; i++) {
            subvaults[i] = createNewSymbioticVault(
                CreationParams({
                    vaultOwner: admin,
                    vaultAdmin: admin,
                    epochDuration: 1 days,
                    asset: wsteth,
                    isDepositLimit: true,
                    depositLimit: 1 ether
                })
            );
        }

        for (uint256 i = 0; i < n; i++) {
            mv.addSubvault(subvaults[i], IMultiVaultStorage.Protocol.SYMBIOTIC);
        }

        subvaults[n] = address(new MockERC4626(wsteth));
        mv.addSubvault(subvaults[n], IMultiVaultStorage.Protocol.ERC4626);
        RatiosStrategy.Ratio[] memory ratios = new RatiosStrategy.Ratio[](n + 1);

        for (uint256 i = 0; i < n + 1; i++) {
            ratios[i].minRatioD18 = uint64(1 ether * (i + 1) ** 2 / (n + 1) ** 2);
            ratios[i].maxRatioD18 = 1 ether;
        }
        strategy.setRatios(address(mv), subvaults, ratios);

        mv.rebalance();

        for (uint256 i = 0; i < 100; i++) {
            uint256 amount = (i + 1) * 1 ether;
            deal(wsteth, admin, amount);
            IERC20(wsteth).approve(address(mv), amount);
            mv.deposit(amount, admin, admin);
            if (i == 0) {
                deal(wsteth, address(mv), 100 ether);
            } else if (i == 7) {
                deal(wsteth, address(mv), 0);
            }
            mv.rebalance();
            mv.redeem(mv.balanceOf(admin), admin, admin);
        }

        skip(3 days);

        uint256[] memory vaults = new uint256[](2);
        vaults[1] = 1;

        claimer.multiAcceptAndClaim(
            address(mv), vaults, new uint256[][](2), admin, type(uint256).max
        );

        skip(3 days);

        claimer.multiAcceptAndClaim(
            address(mv), vaults, new uint256[][](2), admin, type(uint256).max
        );

        vm.stopPrank();
    }
}
