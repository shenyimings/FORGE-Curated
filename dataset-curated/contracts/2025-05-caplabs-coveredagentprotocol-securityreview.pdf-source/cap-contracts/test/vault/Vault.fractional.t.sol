// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IAccessControl } from "../../contracts/interfaces/IAccessControl.sol";
import { TestDeployer } from "../deploy/TestDeployer.sol";
import { MockERC4626 } from "../mocks/MockERC4626.sol";
import { console } from "forge-std/console.sol";

contract VaultFractionalTest is TestDeployer {
    address user;
    address borrower;
    uint256 constant USDT_RESERVE_AMOUNT = 10_000e6;
    uint256 constant INTEREST_RATE = 0.1e18; // 10% annual interest rate

    MockERC4626 mockFRVault;
    MockERC4626 oldFRVault;
    MockERC4626 newFRVault;

    function setUp() public {
        _deployCapTestEnvironment();

        // Setup test user
        user = makeAddr("test_user");
        borrower = makeAddr("borrower");

        // allow borrower to borrow
        vm.prank(env.users.access_control_admin);
        IAccessControl(env.infra.accessControl).grantAccess(cUSD.borrow.selector, address(cUSD), borrower);
        vm.stopPrank();

        // Initialize vault with some liquidity
        _initTestVaultLiquidity(usdVault);

        // Set initial reserve amount
        vm.prank(env.users.vault_config_admin);
        cUSD.setReserve(address(usdt), USDT_RESERVE_AMOUNT);

        // Initialize mock vaults
        mockFRVault = new MockERC4626(address(usdt), INTEREST_RATE, "Mock FR USDT Vault", "mfrUSDT");
        oldFRVault = new MockERC4626(address(usdt), INTEREST_RATE, "Old Mock FR USDT Vault", "oldMfrUSDT");
        newFRVault = new MockERC4626(address(usdt), INTEREST_RATE, "New Mock FR USDT Vault", "newMfrUSDT");
    }

    function test_set_reserve() public {
        vm.startPrank(env.users.vault_config_admin);

        // Set a new reserve amount
        uint256 newReserve = 300e6; // 300 USDT
        cUSD.setReserve(address(usdt), newReserve);

        // Verify the new reserve amount
        assertEq(cUSD.reserve(address(usdt)), newReserve, "Reserve amount should be updated");

        vm.stopPrank();
    }

    function test_invest_all() public {
        // Get initial vault balance
        uint256 initialVaultBalance = usdt.balanceOf(address(cUSD));

        vm.startPrank(env.users.vault_config_admin);

        // Set the fractional reserve vault for USDT
        cUSD.setFractionalReserveVault(address(usdt), address(mockFRVault));

        // Invest all available funds
        cUSD.investAll(address(usdt));

        // Calculate expected investment amount (total balance - reserve)
        uint256 expectedInvestment = initialVaultBalance - USDT_RESERVE_AMOUNT;

        // Verify the reserve amount remains in the vault
        assertEq(usdt.balanceOf(address(cUSD)), USDT_RESERVE_AMOUNT, "Vault should maintain reserve amount");

        // Verify the investment amount was transferred to the FR vault
        assertEq(usdt.balanceOf(address(mockFRVault)), expectedInvestment, "FR vault should receive investment amount");

        vm.stopPrank();
    }

    function test_divest_all_get_profit() public {
        uint256 initialVaultBalance = usdt.balanceOf(address(cUSD));
        uint256 investmentAmount = initialVaultBalance - USDT_RESERVE_AMOUNT;

        vm.startPrank(env.users.vault_config_admin);

        // Set FR vault and invest
        cUSD.setFractionalReserveVault(address(usdt), address(mockFRVault));
        cUSD.investAll(address(usdt));

        // expect the FR vault to have some asset invested
        assertEq(usdt.balanceOf(address(mockFRVault)), investmentAmount, "FR vault should have investment");
        assertEq(usdt.balanceOf(address(cUSD)), USDT_RESERVE_AMOUNT, "Vault should maintain reserve amount");

        // Warp time forward to accumulate interest (1 month)
        _timeTravel(30 days);

        // Mock some yield
        uint256 interest = mockFRVault.__estimateMockErc4626Yield();
        require(interest > 0, "Should have accumulated some interest");
        mockFRVault.__mockYield();

        // Divest all funds
        cUSD.divestAll(address(usdt));

        // Verify all funds returned to vault and interest was sent to fee auction
        assertEq(usdt.balanceOf(address(cUSD)), initialVaultBalance, "Vault should receive original amount");
        assertEq(
            usdt.balanceOf(usdVault.feeAuction),
            interest - 1, /* -1: rounding error */
            "Fee auction should receive interest"
        );

        // Verify FR vault is empty
        assertEq(usdt.balanceOf(address(mockFRVault)), 1, /* rounding error */ "FR vault should be empty after divest");

        vm.stopPrank();
    }

    function test_change_fractional_reserve_vault() public {
        uint256 initialVaultBalance = usdt.balanceOf(address(cUSD));
        uint256 investmentAmount = initialVaultBalance - USDT_RESERVE_AMOUNT;

        vm.startPrank(env.users.vault_config_admin);

        // Set initial FR vault and invest
        cUSD.setFractionalReserveVault(address(usdt), address(oldFRVault));
        cUSD.investAll(address(usdt));

        // expect the old vault to have some asset invested
        assertEq(usdt.balanceOf(address(oldFRVault)), investmentAmount, "Old FR vault should have investment");

        // Change to new FR vault
        cUSD.setFractionalReserveVault(address(usdt), address(newFRVault));

        // Verify funds were moved
        assertEq(usdt.balanceOf(address(oldFRVault)), 0, "Old FR vault should be empty");
        assertEq(cUSD.fractionalReserveVault(address(usdt)), address(newFRVault), "New FR vault should be set");
        assertEq(usdt.balanceOf(address(newFRVault)), 0, "New FR vault should be empty");
        assertEq(usdt.balanceOf(address(cUSD)), initialVaultBalance, "Vault should maintain reserve amount");

        // Invest again to verify new vault works
        cUSD.investAll(address(usdt));
        assertEq(usdt.balanceOf(address(newFRVault)), investmentAmount, "New FR vault should receive investment");

        vm.stopPrank();
    }

    function test_borrow_more_than_reserve() public {
        uint256 initialVaultBalance = usdt.balanceOf(address(cUSD));
        uint256 investmentAmount = initialVaultBalance - USDT_RESERVE_AMOUNT;

        vm.startPrank(env.users.vault_config_admin);

        // Set FR vault and invest
        cUSD.setFractionalReserveVault(address(usdt), address(mockFRVault));
        cUSD.investAll(address(usdt));

        // Verify initial state
        assertEq(usdt.balanceOf(address(mockFRVault)), investmentAmount, "FR vault should have investment");
        assertEq(usdt.balanceOf(address(cUSD)), USDT_RESERVE_AMOUNT, "Vault should maintain reserve amount");

        vm.stopPrank();

        // Try to borrow more than the reserve amount
        uint256 borrowAmount = USDT_RESERVE_AMOUNT + 1000e6; // Reserve amount + 1000 USDT
        vm.startPrank(borrower);
        cUSD.borrow(address(usdt), borrowAmount, borrower);
        vm.stopPrank();

        // Verify that the borrow succeeded and funds were divested from FR vault
        assertEq(usdt.balanceOf(borrower), borrowAmount, "Borrower should receive requested amount");
        assertEq(usdt.balanceOf(address(mockFRVault)), 0, "FR vault should have reduced balance");
        assertEq(usdt.balanceOf(address(cUSD)), initialVaultBalance - borrowAmount, "Vault should have reduced balance");
    }

    function test_realize_interest_are_sent_to_fee_auction() public {
        uint256 initialVaultBalance = usdt.balanceOf(address(cUSD));
        uint256 investmentAmount = initialVaultBalance - USDT_RESERVE_AMOUNT;
        assertGt(investmentAmount, 0, "Should have something to invest");

        vm.startPrank(env.users.vault_config_admin);

        // Set FR vault and invest
        assertEq(usdt.balanceOf(address(mockFRVault)), 0, "Mock investment vault should be empty");
        cUSD.setFractionalReserveVault(address(usdt), address(mockFRVault));
        cUSD.investAll(address(usdt));

        // expect the mock vault to have some asset invested
        assertEq(usdt.balanceOf(address(mockFRVault)), investmentAmount, "Mock investment vault should have investment");

        // Warp time forward to accumulate interest (1 month)
        _timeTravel(30 days);

        // Mock some yield
        uint256 interest = mockFRVault.__estimateMockErc4626Yield();
        require(interest > 0, "Should have accumulated some interest");
        mockFRVault.__mockYield();

        // Realize interest
        cUSD.realizeInterest(address(usdt));

        // Verify interest was sent to fee auction
        assertEq(
            usdt.balanceOf(usdVault.feeAuction),
            interest - 1, /* -1: rounding error */
            "Fee auction should receive interest"
        );

        // Verify no more claimable interest
        assertEq(cUSD.claimableInterest(address(usdt)), 0, "No interest should be claimable after realization");

        vm.stopPrank();
    }
}
