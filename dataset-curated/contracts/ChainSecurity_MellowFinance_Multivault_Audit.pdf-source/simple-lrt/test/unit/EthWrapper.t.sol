// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "../BaseTest.sol";
import "../mocks/MockERC4626Vault.sol";

contract Unit is BaseTest {
    function testConstructor() external {
        {
            EthWrapper ethWrapper =
                new EthWrapper(Constants.WETH(), Constants.WSTETH(), Constants.STETH());
            assertEq(ethWrapper.WETH(), Constants.WETH());
            assertEq(ethWrapper.wstETH(), Constants.WSTETH());
            assertEq(ethWrapper.stETH(), Constants.STETH());
        }

        // zero params
        {
            EthWrapper ethWrapper = new EthWrapper(address(0), address(0), address(0));
            assertEq(ethWrapper.WETH(), address(0));
            assertEq(ethWrapper.wstETH(), address(0));
            assertEq(ethWrapper.stETH(), address(0));
        }
    }

    function testEthDeposit() external {
        {
            EthWrapper ethWrapper =
                new EthWrapper(Constants.WETH(), Constants.WSTETH(), Constants.STETH());

            address user = makeAddr("user");

            MockERC4626Vault vault = new MockERC4626Vault("MockERC4626Vault", 1);
            address token = Constants.WSTETH();
            vault.initializeERC4626(
                makeAddr("admin"),
                100 ether,
                false,
                false,
                false,
                token,
                "MockERC4626Vault",
                "MERC4626"
            );

            vm.startPrank(user);

            uint256 amount = 0.1 ether;
            deal(user, amount);

            address eth = ethWrapper.ETH();

            vm.expectRevert();
            ethWrapper.deposit{value: amount}(eth, 0, address(vault), user, address(0));

            vm.expectRevert();
            ethWrapper.deposit{value: amount}(address(1), 1, address(vault), user, address(0));

            vm.expectRevert();
            ethWrapper.deposit{value: amount}(eth, amount - 1, address(vault), user, address(0));

            vm.expectRevert();
            ethWrapper.deposit{value: amount}(
                Constants.WETH(), amount, address(vault), user, address(0)
            );

            ethWrapper.deposit{value: amount}(eth, amount, address(vault), user, address(0));

            assertApproxEqAbs(
                vault.balanceOf(user), IWSTETH(Constants.WSTETH()).getWstETHByStETH(amount), 1 wei
            );

            vm.stopPrank();
        }

        {
            EthWrapper ethWrapper =
                new EthWrapper(Constants.WETH(), Constants.WSTETH(), Constants.STETH());

            address user = makeAddr("user");

            MockERC4626Vault vault = new MockERC4626Vault("MockERC4626Vault", 1);
            address token = Constants.WSTETH();
            vault.initializeERC4626(
                makeAddr("admin"),
                100 ether,
                false,
                false,
                false,
                token,
                "MockERC4626Vault",
                "MERC4626"
            );

            vm.startPrank(user);

            uint256 amount = 1e10 ether;
            address eth = ethWrapper.ETH();
            deal(user, amount);

            vm.expectRevert();
            ethWrapper.deposit{value: amount}(eth, amount, address(vault), user, address(0));

            vm.stopPrank();
        }
    }

    function testWethDeposit() external {
        {
            EthWrapper ethWrapper =
                new EthWrapper(Constants.WETH(), Constants.WSTETH(), Constants.STETH());

            address user = makeAddr("user");
            MockERC4626Vault vault = new MockERC4626Vault("MockERC4626Vault", 1);
            address token = Constants.WSTETH();
            vault.initializeERC4626(
                makeAddr("admin"),
                100 ether,
                false,
                false,
                false,
                token,
                "MockERC4626Vault",
                "MERC4626"
            );

            vm.startPrank(user);

            uint256 amount = 0.1 ether;
            deal(Constants.WETH(), user, amount);

            IERC20(Constants.WETH()).approve(address(ethWrapper), amount);
            ethWrapper.deposit(Constants.WETH(), amount, address(vault), user, address(0));

            assertApproxEqAbs(
                vault.balanceOf(user), IWSTETH(Constants.WSTETH()).getWstETHByStETH(amount), 1 wei
            );

            vm.stopPrank();
        }

        {
            EthWrapper ethWrapper =
                new EthWrapper(Constants.WETH(), Constants.WSTETH(), Constants.STETH());

            address user = makeAddr("user");

            MockERC4626Vault vault = new MockERC4626Vault("MockERC4626Vault", 1);
            address token = Constants.WSTETH();
            vault.initializeERC4626(
                makeAddr("admin"),
                100 ether,
                false,
                false,
                false,
                token,
                "MockERC4626Vault",
                "MERC4626"
            );

            vm.startPrank(user);

            uint256 amount = 1e10 ether;
            deal(Constants.WETH(), user, amount);

            IERC20(Constants.WETH()).approve(address(ethWrapper), amount);
            vm.expectRevert();
            ethWrapper.deposit(Constants.WETH(), amount, address(vault), user, address(0));

            vm.stopPrank();
        }

        {
            EthWrapper oldWrapper =
                new EthWrapper(Constants.WETH(), Constants.WSTETH(), Constants.STETH());
            EthWrapper ethWrapper =
                new EthWrapper(Constants.WETH(), address(oldWrapper), Constants.STETH());

            address user = makeAddr("user");

            MockERC4626Vault vault = new MockERC4626Vault("MockERC4626Vault", 1);
            address token = Constants.WSTETH();
            vault.initializeERC4626(
                makeAddr("admin"),
                100 ether,
                false,
                false,
                false,
                token,
                "MockERC4626Vault",
                "MERC4626"
            );

            vm.startPrank(user);

            uint256 amount = 1 ether;
            deal(Constants.WETH(), user, amount);

            IERC20(Constants.WETH()).approve(address(ethWrapper), amount);
            vm.expectRevert();
            ethWrapper.deposit(Constants.WETH(), amount, address(vault), user, address(0));

            vm.stopPrank();
        }

        {
            EthWrapper ethWrapper =
                new EthWrapper(address(0), Constants.WSTETH(), Constants.WSTETH());

            address user = makeAddr("user");

            MockERC4626Vault vault = new MockERC4626Vault("MockERC4626Vault", 1);
            address token = Constants.WSTETH();
            vault.initializeERC4626(
                makeAddr("admin"),
                100 ether,
                false,
                false,
                false,
                token,
                "MockERC4626Vault",
                "MERC4626"
            );

            vm.startPrank(user);

            uint256 amount = 0.1 ether;
            deal(Constants.WETH(), user, amount);

            IERC20(Constants.WETH()).approve(address(ethWrapper), amount);

            vm.expectRevert();
            ethWrapper.deposit(address(0), amount, address(vault), user, address(0));
            vm.stopPrank();
        }
    }

    function testWstethDeposit() external {
        EthWrapper ethWrapper =
            new EthWrapper(Constants.WETH(), Constants.WSTETH(), Constants.STETH());

        address user = makeAddr("user");

        MockERC4626Vault vault = new MockERC4626Vault("MockERC4626Vault", 1);
        address token = Constants.WSTETH();
        vault.initializeERC4626(
            makeAddr("admin"), 100 ether, false, false, false, token, "MockERC4626Vault", "MERC4626"
        );

        vm.startPrank(user);

        uint256 amount = 0.1 ether;
        deal(Constants.WSTETH(), user, amount);

        IERC20(Constants.WSTETH()).approve(address(ethWrapper), amount);
        ethWrapper.deposit(Constants.WSTETH(), amount, address(vault), user, address(0));

        assertApproxEqAbs(vault.balanceOf(user), amount, 1 wei);

        vm.stopPrank();
    }

    function testStethDeposit() external {
        {
            EthWrapper ethWrapper =
                new EthWrapper(Constants.WETH(), Constants.WSTETH(), Constants.STETH());

            address user = makeAddr("user");

            MockERC4626Vault vault = new MockERC4626Vault("MockERC4626Vault", 1);
            address token = Constants.WSTETH();
            vault.initializeERC4626(
                makeAddr("admin"),
                100 ether,
                false,
                false,
                false,
                token,
                "MockERC4626Vault",
                "MERC4626"
            );
            vm.startPrank(user);

            uint256 amount = 0.1 ether;
            deal(user, amount);

            ISTETH(Constants.STETH()).submit{value: amount}(address(0));
            IERC20(Constants.STETH()).approve(address(address(ethWrapper)), amount);

            ethWrapper.deposit(Constants.STETH(), amount, address(vault), user, address(0));

            assertApproxEqAbs(
                vault.balanceOf(user), IWSTETH(Constants.WSTETH()).getWstETHByStETH(amount), 1 wei
            );

            vm.stopPrank();
        }

        {
            EthWrapper ethWrapper =
                new EthWrapper(Constants.WETH(), Constants.WSTETH(), Constants.WSTETH());

            address user = makeAddr("user");

            MockERC4626Vault vault = new MockERC4626Vault("MockERC4626Vault", 1);
            address token = Constants.WSTETH();
            vault.initializeERC4626(
                makeAddr("admin"),
                100 ether,
                false,
                false,
                false,
                token,
                "MockERC4626Vault",
                "MERC4626"
            );

            vm.startPrank(user);

            uint256 amount = 0.1 ether;
            deal(user, amount);

            ISTETH(Constants.STETH()).submit{value: amount}(address(0));
            IERC20(Constants.STETH()).approve(address(address(ethWrapper)), amount);

            vm.expectRevert();
            ethWrapper.deposit(Constants.STETH(), amount, address(vault), user, address(0));

            vm.stopPrank();
        }
    }
}
