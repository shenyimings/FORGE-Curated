// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Deployers} from "test/utils/Deployers.sol";
import {AccountManagerResolver} from "src/relayers/monad_testnet/account-manager-v1/main.sol";
import {TadleImplementationV1} from "src/relayers/monad_testnet/implementation/ImplementationV1.sol";

/**
 * @title AccountManagerTest
 * @author Tadle Team
 * @notice Test contract for validating account manager functionality
 * @dev This contract tests deposit and withdrawal operations for both native tokens (MON) and ERC20 tokens (USDC)
 * @custom:test-scope Covers sandbox account creation, deposits, withdrawals, and balance verification
 * @custom:network Designed for Monad testnet environment
 */
contract AccountManagerTest is Test, Deployers {
    /**
     * @notice Sets up the test environment before each test execution
     * @dev Deploys all necessary contracts and initializes the account manager system
     * @custom:setup-phase Prepares the complete testing infrastructure
     * @custom:contracts Deploys core protocol contracts and account manager functionality
     * @custom:balances Provides initial balances: 100 ETH and 100 USDC to test user
     */
    function setUp() public {
        // Deploy all core Tadle sandbox contracts (Auth, Factory, Connectors, etc.)
        deployCoreContracts();

        // Deploy and configure the account manager contract with necessary permissions
        deployAndInitializeAccountManager();

        // Provide initial native token balance (100 ETH) to the test user
        deal(user, 100 ether);
        // Provide initial USDC balance (100 USDC with 6 decimals) to the test user
        deal(USDC, user, 100 * 1e6);
    }

    /**
     * @notice Tests deposit and withdrawal functionality for native MON tokens
     * @dev Simulates depositing MON to a sandbox account and then withdrawing a portion
     * @custom:test-flow Creates sandbox account → Deposits 10 ETH → Withdraws 5 ETH → Verifies balances
     * @custom:assertion Verifies correct balance changes for both user and sandbox account
     * @custom:tokens Tests native token (ETH/MON) handling through the account manager
     */
    function testDepositAndWithdrawMON() public {
        // Create a new sandbox account for the test user
        address sandbox_account = createSandBoxAccount();

        // Start impersonating the test user for transaction simulation
        vm.startPrank(user, user);

        // Deposit 10 ETH to the sandbox account via direct transfer
        (bool success, ) = payable(address(sandbox_account)).call{
            value: 10 ether
        }("");
        require(success, "ETH transfer failed");

        // Verify deposit: user should have 90 ETH, sandbox should have 10 ETH
        assertEq(address(user).balance, 90 ether);
        assertEq(address(sandbox_account).balance, 10 ether);

        // Prepare withdrawal transaction data
        string[] memory _targetNames = new string[](1);
        _targetNames[0] = "AccountManager-v1.0.0"; // Target the account manager connector
        bytes[] memory _datas = new bytes[](1);

        // Encode withdrawal function call: withdraw 5 ETH to user address
        bytes memory _data = abi.encodeWithSelector(
            AccountManagerResolver.withdraw.selector,
            ETH_ADDRESS, // Native token address constant
            5 ether, // Amount to withdraw
            address(user) // Recipient address
        );
        _datas[0] = _data;

        // Execute withdrawal through the sandbox account's cast function
        TadleImplementationV1(payable(sandbox_account)).cast(
            _targetNames,
            _datas
        );

        // Verify withdrawal: user should have 95 ETH, sandbox should have 5 ETH
        assertEq(address(user).balance, 95 ether);
        assertEq(address(sandbox_account).balance, 5 ether);

        // Stop impersonating the user
        vm.stopPrank();
    }

    /**
     * @notice Tests deposit and withdrawal functionality for USDC tokens
     * @dev Simulates transferring USDC to a sandbox account and then withdrawing a portion
     * @custom:test-flow Creates sandbox account → Transfers 10 USDC → Withdraws 5 USDC → Verifies balances
     * @custom:assertion Verifies correct balance changes for both user and sandbox account
     * @custom:tokens Tests ERC20 token (USDC) handling through the account manager
     * @custom:decimals USDC uses 6 decimal places, so amounts are multiplied by 1e6
     */
    function testDepositAndWithdrawUSDC() public {
        // Create a new sandbox account for the test user
        address sandbox_account = createSandBoxAccount();

        // Start impersonating the test user for transaction simulation
        vm.startPrank(user, user);

        // Transfer 10 USDC to the sandbox account (10 * 1e6 due to 6 decimals)
        IERC20(USDC).transfer(address(sandbox_account), 10 * 1e6);

        // Verify transfer: user should have 90 USDC, sandbox should have 10 USDC
        assertEq(IERC20(USDC).balanceOf(address(user)), 90 * 1e6);
        assertEq(IERC20(USDC).balanceOf(address(sandbox_account)), 10 * 1e6);

        // Prepare withdrawal transaction data
        string[] memory _targetNames = new string[](1);
        _targetNames[0] = "AccountManager-v1.0.0"; // Target the account manager connector
        bytes[] memory _datas = new bytes[](1);

        // Encode withdrawal function call: withdraw 5 USDC to user address
        bytes memory _data = abi.encodeWithSelector(
            AccountManagerResolver.withdraw.selector,
            USDC, // USDC token address
            5 * 1e6, // Amount to withdraw (5 USDC with 6 decimals)
            address(user) // Recipient address
        );
        _datas[0] = _data;

        // Execute withdrawal through the sandbox account's cast function
        TadleImplementationV1(payable(sandbox_account)).cast(
            _targetNames,
            _datas
        );

        // Verify withdrawal: user should have 95 USDC, sandbox should have 5 USDC
        assertEq(IERC20(USDC).balanceOf(address(user)), 95 * 1e6);
        assertEq(IERC20(USDC).balanceOf(address(sandbox_account)), 5 * 1e6);

        // Stop impersonating the user
        vm.stopPrank();
    }
}
