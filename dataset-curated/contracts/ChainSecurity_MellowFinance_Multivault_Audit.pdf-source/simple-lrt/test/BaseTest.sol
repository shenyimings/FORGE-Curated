// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "./Imports.sol";

abstract contract BaseTest is Test {
    SymbioticHelper public immutable symbioticHelper = new SymbioticHelper();
    RandomLib.Storage public rnd = RandomLib.Storage(0);

    function createDefaultMultiVaultWithSymbioticVault(address vaultAdmin)
        internal
        returns (
            MultiVault vault,
            SymbioticAdapter adapter,
            RatiosStrategy strategy,
            address symbioticVault
        )
    {
        {
            TransparentUpgradeableProxy c_ = new TransparentUpgradeableProxy(
                address(new MultiVault(bytes32("MultiVaultTest"), 1)),
                vm.createWallet("proxyAdmin").addr,
                new bytes(0)
            );
            vault = MultiVault(address(c_));
        }
        adapter = new SymbioticAdapter(
            address(vault),
            Constants.symbioticDeployment().vaultFactory,
            address(new SymbioticWithdrawalQueue(address(new Claimer()))),
            vm.createWallet("proxyAdmin").addr
        );

        strategy = new RatiosStrategy();

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
                symbioticAdapter: address(adapter),
                eigenLayerAdapter: address(0),
                erc4626Adapter: address(0)
            })
        );

        (symbioticVault,,,) = symbioticHelper.createDefaultSymbioticVault(Constants.WSTETH());
        {
            vm.startPrank(vaultAdmin);
            vault.grantRole(strategy.RATIOS_STRATEGY_SET_RATIOS_ROLE(), vaultAdmin);
            vault.grantRole(vault.ADD_SUBVAULT_ROLE(), vaultAdmin);
            vault.addSubvault(address(symbioticVault), IMultiVaultStorage.Protocol.SYMBIOTIC);
            address[] memory subvaults = new address[](1);
            subvaults[0] = symbioticVault;
            IRatiosStrategy.Ratio[] memory ratios = new IRatiosStrategy.Ratio[](1);
            ratios[0] = IRatiosStrategy.Ratio(0.5 ether, 1 ether);
            strategy.setRatios(address(vault), subvaults, ratios);
            vm.stopPrank();
        }
    }

    function createDefaultMultiVaultWithEigenWstETHVault(address vaultAdmin)
        internal
        returns (
            MultiVault vault,
            EigenLayerAdapter eigenLayerAdapter,
            RatiosStrategy strategy,
            address eigenLayerVault
        )
    {
        {
            TransparentUpgradeableProxy c_ = new TransparentUpgradeableProxy(
                address(new MultiVault("test", 1)), vm.createWallet("proxyAdmin").addr, new bytes(0)
            );
            vault = MultiVault(address(c_));
        }
        strategy = new RatiosStrategy();

        IsolatedEigenLayerVaultFactory factory = new IsolatedEigenLayerVaultFactory(
            Constants.HOLESKY_EL_DELEGATION_MANAGER,
            address(new IsolatedEigenLayerWstETHVault(Constants.WSTETH())),
            address(
                new EigenLayerWstETHWithdrawalQueue(
                    address(new Claimer()), Constants.HOLESKY_EL_DELEGATION_MANAGER
                )
            ),
            vm.createWallet("proxyAdmin").addr
        );
        eigenLayerAdapter = new EigenLayerWstETHAdapter(
            address(factory),
            address(vault),
            IStrategyManager(Constants.HOLESKY_EL_STRATEGY_MANAGER),
            IRewardsCoordinator(Constants.HOLESKY_EL_REWARDS_COORDINATOR),
            Constants.WSTETH()
        );

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
                symbioticAdapter: address(0),
                eigenLayerAdapter: address(eigenLayerAdapter),
                erc4626Adapter: address(0)
            })
        );

        {
            ISignatureUtils.SignatureWithExpiry memory signature;
            bytes32 salt = 0;
            address operator = 0xbF8a8B0d0450c8812ADDf04E1BcB7BfBA0E82937; // random operator
            address eigenLayerStrategy = 0x7D704507b76571a51d9caE8AdDAbBFd0ba0e63d3;
            (eigenLayerVault,) = factory.getOrCreate(
                address(vault), eigenLayerStrategy, operator, abi.encode(signature, salt)
            );

            vm.startPrank(vaultAdmin);
            vault.grantRole(strategy.RATIOS_STRATEGY_SET_RATIOS_ROLE(), vaultAdmin);
            vault.grantRole(vault.ADD_SUBVAULT_ROLE(), vaultAdmin);
            vault.addSubvault(eigenLayerVault, IMultiVaultStorage.Protocol.EIGEN_LAYER);
            address[] memory subvaults = new address[](1);
            subvaults[0] = eigenLayerVault;
            IRatiosStrategy.Ratio[] memory ratios = new IRatiosStrategy.Ratio[](1);
            ratios[0] = IRatiosStrategy.Ratio(0.5 ether, 1 ether);
            strategy.setRatios(address(vault), subvaults, ratios);
            vm.stopPrank();
        }
    }

    function testBaseMock() private pure {}
}
