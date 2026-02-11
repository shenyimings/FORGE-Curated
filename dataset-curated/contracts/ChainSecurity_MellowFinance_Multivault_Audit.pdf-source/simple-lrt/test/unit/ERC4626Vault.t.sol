// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "../BaseTest.sol";

import "../mocks/MockERC4626Vault.sol";

contract Unit is BaseTest {
    address admin = makeAddr("admin");
    address user1 = makeAddr("user1");
    address user2 = makeAddr("user2");

    uint64 vaultVersion = 1;
    address vaultOwner = makeAddr("vaultOwner");
    address vaultAdmin = makeAddr("vaultAdmin");
    uint48 epochDuration = 3600;

    function testInitializeERC4626() external {
        MockERC4626Vault vault = new MockERC4626Vault("Vault", vaultVersion);
        vault.initializeERC4626(
            admin,
            1000,
            false,
            false,
            false,
            Constants.WSTETH(),
            "Wrapped stETH",
            "Constants.WSTETH()"
        );

        assertEq(vault.name(), "Wrapped stETH");
        assertEq(vault.symbol(), "Constants.WSTETH()");
        assertEq(vault.decimals(), 18);
        assertEq(vault.totalSupply(), 0);
        assertEq(vault.limit(), 1000);
        assertEq(vault.depositPause(), false);
        assertEq(vault.withdrawalPause(), false);
        assertEq(vault.depositWhitelist(), false);
        assertEq(vault.asset(), Constants.WSTETH());

        // DEFAULT_ADMIN_ROLE
        assertTrue(vault.hasRole(bytes32(0), admin));

        // second initalization should fail
        vm.expectRevert();
        vault.initializeERC4626(
            admin,
            1000,
            false,
            false,
            false,
            Constants.WSTETH(),
            "Wrapped stETH",
            "Constants.WSTETH()"
        );
    }

    function testMaxMint() external {
        {
            MockERC4626Vault vault = new MockERC4626Vault("Vault", vaultVersion);
            vault.initializeERC4626(
                admin,
                1000,
                false,
                false,
                false,
                Constants.WSTETH(),
                "Wrapped stETH",
                "Constants.WSTETH()"
            );

            assertEq(vault.maxMint(address(this)), 1000);
        }

        {
            MockERC4626Vault vault = new MockERC4626Vault("Vault", vaultVersion);
            vault.initializeERC4626(
                admin,
                type(uint256).max,
                false,
                false,
                false,
                Constants.WSTETH(),
                "Wrapped stETH",
                "Constants.WSTETH()"
            );

            assertEq(vault.maxMint(address(this)), type(uint256).max);
        }

        {
            MockERC4626Vault vault = new MockERC4626Vault("Vault", vaultVersion);
            vault.initializeERC4626(
                admin,
                type(uint256).max,
                false,
                false,
                true,
                Constants.WSTETH(),
                "Wrapped stETH",
                "Constants.WSTETH()"
            );

            assertEq(vault.maxMint(address(this)), 0);
        }

        {
            MockERC4626Vault vault = new MockERC4626Vault("Vault", vaultVersion);
            vault.initializeERC4626(
                admin,
                type(uint256).max,
                false,
                false,
                true,
                Constants.WSTETH(),
                "Wrapped stETH",
                "Constants.WSTETH()"
            );

            vm.startPrank(admin);
            vault.grantRole(keccak256("SET_DEPOSITOR_WHITELIST_STATUS_ROLE"), admin);
            vault.setDepositorWhitelistStatus(address(this), true);

            vm.stopPrank();

            assertEq(vault.maxMint(address(this)), type(uint256).max);
        }
    }

    function testMaxDeposit() external {
        {
            MockERC4626Vault vault = new MockERC4626Vault("Vault", vaultVersion);
            vault.initializeERC4626(
                admin,
                1000,
                false,
                false,
                false,
                Constants.WSTETH(),
                "Wrapped stETH",
                "Constants.WSTETH()"
            );

            assertEq(vault.maxDeposit(address(this)), 1000);
        }

        {
            MockERC4626Vault vault = new MockERC4626Vault("Vault", vaultVersion);
            vault.initializeERC4626(
                admin,
                type(uint256).max,
                false,
                false,
                false,
                Constants.WSTETH(),
                "Wrapped stETH",
                "Constants.WSTETH()"
            );

            assertEq(vault.maxDeposit(address(this)), type(uint256).max);
        }

        {
            MockERC4626Vault vault = new MockERC4626Vault("Vault", vaultVersion);
            vault.initializeERC4626(
                admin,
                type(uint256).max,
                true,
                true,
                true,
                Constants.WSTETH(),
                "Wrapped stETH",
                "Constants.WSTETH()"
            );

            assertEq(vault.maxDeposit(address(this)), 0);
        }

        {
            MockERC4626Vault vault = new MockERC4626Vault("Vault", vaultVersion);
            vault.initializeERC4626(
                admin,
                type(uint256).max,
                false,
                false,
                false,
                Constants.WSTETH(),
                "Wrapped stETH",
                "Constants.WSTETH()"
            );

            assertEq(vault.maxDeposit(address(this)), type(uint256).max);
        }

        {
            MockERC4626Vault vault = new MockERC4626Vault("Vault", vaultVersion);
            vault.initializeERC4626(
                admin,
                type(uint256).max,
                false,
                false,
                false,
                Constants.WSTETH(),
                "Wrapped stETH",
                "Constants.WSTETH()"
            );

            assertEq(vault.maxDeposit(address(this)), type(uint256).max);
        }

        {
            MockERC4626Vault vault = new MockERC4626Vault("Vault", vaultVersion);
            vault.initializeERC4626(
                admin,
                type(uint256).max,
                false,
                false,
                true,
                Constants.WSTETH(),
                "Wrapped stETH",
                "Constants.WSTETH()"
            );

            assertEq(vault.maxDeposit(address(this)), 0);
        }

        {
            MockERC4626Vault vault = new MockERC4626Vault("Vault", vaultVersion);
            vault.initializeERC4626(
                admin,
                type(uint256).max,
                false,
                false,
                true,
                Constants.WSTETH(),
                "Wrapped stETH",
                "Constants.WSTETH()"
            );

            vm.startPrank(admin);
            vault.grantRole(keccak256("SET_DEPOSITOR_WHITELIST_STATUS_ROLE"), admin);
            vault.setDepositorWhitelistStatus(address(this), true);

            vm.stopPrank();

            assertEq(vault.maxDeposit(address(this)), type(uint256).max);
        }
    }

    function testDeposit() external {
        vm.startPrank(user1);
        {
            MockERC4626Vault vault = new MockERC4626Vault("Vault", vaultVersion);
            vault.initializeERC4626(
                admin,
                1000,
                false,
                false,
                false,
                Constants.WSTETH(),
                "Wrapped stETH",
                "Constants.WSTETH()"
            );

            uint256 amount = 100;
            deal(Constants.WSTETH(), user1, amount);
            IERC20(Constants.WSTETH()).approve(address(vault), amount);
            vault.deposit(amount, user1);

            assertEq(vault.balanceOf(user1), amount);
            assertEq(vault.totalSupply(), amount);
        }
        {
            MockERC4626Vault vault = new MockERC4626Vault("Vault", vaultVersion);
            vault.initializeERC4626(
                admin,
                1000,
                true,
                true,
                true,
                Constants.WSTETH(),
                "Wrapped stETH",
                "Constants.WSTETH()"
            );

            uint256 amount = 100;
            deal(Constants.WSTETH(), user1, amount);
            IERC20(Constants.WSTETH()).approve(address(vault), amount);
            vm.expectRevert();
            vault.deposit(amount, user1);
        }
        vm.stopPrank();
    }

    function testDepositReferral() external {
        vm.startPrank(user1);
        {
            address referral = makeAddr("referral");
            MockERC4626Vault vault = new MockERC4626Vault("Vault", vaultVersion);
            vault.initializeERC4626(
                admin,
                1000,
                false,
                false,
                false,
                Constants.WSTETH(),
                "Wrapped stETH",
                "Constants.WSTETH()"
            );

            uint256 amount = 100;
            deal(Constants.WSTETH(), user1, amount);
            IERC20(Constants.WSTETH()).approve(address(vault), amount);
            vm.recordLogs();
            vault.deposit(amount, user1, referral);

            Vm.Log[] memory logs = vm.getRecordedLogs();
            assertEq(logs.length, 5);
            assertEq(logs[4].emitter, address(vault));
            assertEq(logs[4].topics[0], keccak256("ReferralDeposit(uint256,address,address)"));

            assertEq(vault.balanceOf(user1), amount);
            assertEq(vault.totalSupply(), amount);
        }
        {
            MockERC4626Vault vault = new MockERC4626Vault("Vault", vaultVersion);
            vault.initializeERC4626(
                admin,
                1000,
                true,
                true,
                true,
                Constants.WSTETH(),
                "Wrapped stETH",
                "Constants.WSTETH()"
            );

            uint256 amount = 100;
            deal(Constants.WSTETH(), user1, amount);
            IERC20(Constants.WSTETH()).approve(address(vault), amount);
            vm.expectRevert();
            vault.deposit(amount, user1);
        }
        vm.stopPrank();
    }

    function testMint() external {
        vm.startPrank(user1);
        {
            MockERC4626Vault vault = new MockERC4626Vault("Vault", vaultVersion);
            vault.initializeERC4626(
                admin,
                1000,
                false,
                false,
                false,
                Constants.WSTETH(),
                "Wrapped stETH",
                "Constants.WSTETH()"
            );

            uint256 amount = 100;
            deal(Constants.WSTETH(), user1, amount);
            IERC20(Constants.WSTETH()).approve(address(vault), amount);
            vault.mint(amount, user1);

            assertEq(vault.balanceOf(user1), amount);
            assertEq(vault.totalSupply(), amount);
        }

        {
            MockERC4626Vault vault = new MockERC4626Vault("Vault", vaultVersion);
            vault.initializeERC4626(
                admin,
                1000,
                true,
                true,
                true,
                Constants.WSTETH(),
                "Wrapped stETH",
                "Constants.WSTETH()"
            );

            uint256 amount = 100;
            deal(Constants.WSTETH(), user1, amount);
            IERC20(Constants.WSTETH()).approve(address(vault), amount);
            vm.expectRevert();
            vault.mint(amount, user1);
        }

        vm.stopPrank();
    }

    function testMaxWithdraw() external {
        vm.startPrank(user1);
        {
            MockERC4626Vault vault = new MockERC4626Vault("Vault", vaultVersion);
            vault.initializeERC4626(
                admin,
                1000,
                false,
                true,
                false,
                Constants.WSTETH(),
                "Wrapped stETH",
                "Constants.WSTETH()"
            );

            uint256 amount = 100;
            deal(Constants.WSTETH(), user1, amount);
            IERC20(Constants.WSTETH()).approve(address(vault), amount);
            vault.mint(amount, user1);

            assertEq(vault.balanceOf(user1), amount);
            assertEq(vault.totalSupply(), amount);
            assertEq(vault.maxWithdraw(user1), 0);
        }

        {
            MockERC4626Vault vault = new MockERC4626Vault("Vault", vaultVersion);
            vault.initializeERC4626(
                admin,
                1000,
                false,
                false,
                false,
                Constants.WSTETH(),
                "Wrapped stETH",
                "Constants.WSTETH()"
            );

            uint256 amount = 100;
            deal(Constants.WSTETH(), user1, amount);
            IERC20(Constants.WSTETH()).approve(address(vault), amount);
            vault.mint(amount, user1);

            assertEq(vault.balanceOf(user1), amount);
            assertEq(vault.totalSupply(), amount);
            assertEq(vault.maxWithdraw(user1), amount);
        }
        vm.stopPrank();
    }

    function testMaxRedeem() external {
        vm.startPrank(user1);
        {
            MockERC4626Vault vault = new MockERC4626Vault("Vault", vaultVersion);
            vault.initializeERC4626(
                admin,
                1000,
                false,
                true,
                false,
                Constants.WSTETH(),
                "Wrapped stETH",
                "Constants.WSTETH()"
            );

            uint256 amount = 100;
            deal(Constants.WSTETH(), user1, amount);
            IERC20(Constants.WSTETH()).approve(address(vault), amount);
            vault.mint(amount, user1);

            assertEq(vault.balanceOf(user1), amount);
            assertEq(vault.totalSupply(), amount);
            assertEq(vault.maxRedeem(user1), 0);
        }

        {
            MockERC4626Vault vault = new MockERC4626Vault("Vault", vaultVersion);
            vault.initializeERC4626(
                admin,
                1000,
                false,
                false,
                false,
                Constants.WSTETH(),
                "Wrapped stETH",
                "Constants.WSTETH()"
            );

            uint256 amount = 100;
            deal(Constants.WSTETH(), user1, amount);
            IERC20(Constants.WSTETH()).approve(address(vault), amount);
            vault.mint(amount, user1);

            assertEq(vault.balanceOf(user1), amount);
            assertEq(vault.totalSupply(), amount);
            assertEq(vault.maxRedeem(user1), amount);
        }
        vm.stopPrank();
    }

    function testWithdraw() external {
        vm.startPrank(user1);
        {
            MockERC4626Vault vault = new MockERC4626Vault("Vault", vaultVersion);
            vault.initializeERC4626(
                admin,
                1000,
                false,
                false,
                false,
                Constants.WSTETH(),
                "Wrapped stETH",
                "Constants.WSTETH()"
            );

            uint256 amount = 100;
            deal(Constants.WSTETH(), user1, amount);
            IERC20(Constants.WSTETH()).approve(address(vault), amount);
            vault.mint(amount, user1);

            assertEq(vault.balanceOf(user1), amount);
            assertEq(vault.totalSupply(), amount);

            vault.withdraw(amount, user1, user1);

            assertEq(vault.balanceOf(user1), 0);
            assertEq(vault.totalSupply(), 0);
        }

        {
            MockERC4626Vault vault = new MockERC4626Vault("Vault", vaultVersion);
            vault.initializeERC4626(
                admin,
                1000,
                false,
                true,
                false,
                Constants.WSTETH(),
                "Wrapped stETH",
                "Constants.WSTETH()"
            );

            uint256 amount = 100;
            deal(Constants.WSTETH(), user1, amount);
            IERC20(Constants.WSTETH()).approve(address(vault), amount);
            vault.mint(amount, user1);

            assertEq(vault.balanceOf(user1), amount);
            assertEq(vault.totalSupply(), amount);

            vm.expectRevert();
            vault.withdraw(amount, user1, user1);
        }

        vm.stopPrank();
    }

    function testRedeem() external {
        vm.startPrank(user1);
        {
            MockERC4626Vault vault = new MockERC4626Vault("Vault", vaultVersion);
            vault.initializeERC4626(
                admin,
                1000,
                false,
                false,
                false,
                Constants.WSTETH(),
                "Wrapped stETH",
                "Constants.WSTETH()"
            );

            uint256 amount = 100;
            deal(Constants.WSTETH(), user1, amount);
            IERC20(Constants.WSTETH()).approve(address(vault), amount);
            vault.mint(amount, user1);

            assertEq(vault.balanceOf(user1), amount);
            assertEq(vault.totalSupply(), amount);

            vault.redeem(amount, user1, user1);

            assertEq(vault.balanceOf(user1), 0);
            assertEq(vault.totalSupply(), 0);
        }

        {
            MockERC4626Vault vault = new MockERC4626Vault("Vault", vaultVersion);
            vault.initializeERC4626(
                admin,
                1000,
                false,
                true,
                false,
                Constants.WSTETH(),
                "Wrapped stETH",
                "Constants.WSTETH()"
            );

            uint256 amount = 100;
            deal(Constants.WSTETH(), user1, amount);
            IERC20(Constants.WSTETH()).approve(address(vault), amount);
            vault.mint(amount, user1);

            assertEq(vault.balanceOf(user1), amount);
            assertEq(vault.totalSupply(), amount);

            vm.expectRevert();
            vault.redeem(amount, user1, user1);
        }

        vm.stopPrank();
    }
}
