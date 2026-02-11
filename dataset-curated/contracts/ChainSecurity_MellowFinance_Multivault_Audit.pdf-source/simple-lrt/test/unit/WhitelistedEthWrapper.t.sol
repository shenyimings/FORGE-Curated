// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "../BaseTest.sol";
import "../mocks/MockERC4626Vault.sol";

contract Unit is BaseTest {
    using RandomLib for RandomLib.Storage;

    function testConstructor() external {
        {
            WhitelistedEthWrapper ethWrapper =
                new WhitelistedEthWrapper(Constants.WETH(), Constants.WSTETH(), Constants.STETH());
            assertEq(ethWrapper.WETH(), Constants.WETH());
            assertEq(ethWrapper.wstETH(), Constants.WSTETH());
            assertEq(ethWrapper.stETH(), Constants.STETH());
        }

        // zero params
        {
            WhitelistedEthWrapper ethWrapper =
                new WhitelistedEthWrapper(address(0), address(0), address(0));
            assertEq(ethWrapper.WETH(), address(0));
            assertEq(ethWrapper.wstETH(), address(0));
            assertEq(ethWrapper.stETH(), address(0));
        }
    }

    function testDeposit() external {
        MultiVault vault;
        {
            TransparentUpgradeableProxy c_ = new TransparentUpgradeableProxy(
                address(new MultiVault(bytes32("MultiVaultTest"), 1)),
                vm.createWallet("proxyAdmin").addr,
                new bytes(0)
            );
            vault = MultiVault(address(c_));
        }
        address vaultAdmin = rnd.randAddress();
        RatiosStrategy strategy = new RatiosStrategy();
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
                symbioticAdapter: address(0),
                eigenLayerAdapter: address(0),
                erc4626Adapter: address(0)
            })
        );

        WhitelistedEthWrapper ethWrapper =
            new WhitelistedEthWrapper(Constants.WETH(), Constants.WSTETH(), Constants.STETH());

        address user = rnd.randAddress();

        vm.startPrank(vaultAdmin);

        vm.expectRevert("WhitelistedEthWrapper: forbidden");
        ethWrapper.setDepositWhitelist(address(vault), true);
        vm.expectRevert("WhitelistedEthWrapper: forbidden");
        ethWrapper.setDepositorWhitelistStatus(address(vault), user, true);

        vault.grantRole(ethWrapper.SET_DEPOSIT_WHITELIST_ROLE(), vaultAdmin);
        vault.grantRole(ethWrapper.SET_DEPOSITOR_WHITELIST_STATUS_ROLE(), vaultAdmin);

        ethWrapper.setDepositWhitelist(address(vault), true);
        ethWrapper.setDepositorWhitelistStatus(address(vault), user, true);

        vm.stopPrank();

        address weth = Constants.WETH();
        address wstETH = Constants.WSTETH();
        address stETH = Constants.STETH();

        vm.expectRevert("WhitelistedEthWrapper: deposit not whitelisted");
        ethWrapper.deposit(weth, 0, address(vault), address(0), address(0));
        vm.expectRevert("EthWrapper: invalid depositToken");
        ethWrapper.deposit(stETH, 0, address(vault), address(0), address(0));
        vm.expectRevert("EthWrapper: invalid depositToken");
        ethWrapper.deposit(wstETH, 0, address(vault), address(0), address(0));

        vm.startPrank(user);

        deal(user, 1 ether);
        ethWrapper.deposit{value: 1 ether}(ethWrapper.ETH(), 1 ether, address(vault), user, user);

        vm.stopPrank();
    }
}
