// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Deployers} from "test/utils/Deployers.sol";
import {MonUSDProxy} from "src/tokens/MonUSDProxy.sol";
import {MonUSD} from "src/tokens/MonUSD.sol";

/**
 * @title MonUSDTest
 * @author Tadle Team
 * @notice Test contract for MonUSD stablecoin functionality
 * @dev Tests the deposit and withdrawal mechanisms of the MonUSD token system
 * @custom:test-scope Covers MonUSD proxy deployment, initialization, and core operations
 * @custom:network Designed for Monad testnet environment
 */
contract MonUSDTest is Test, Deployers {
    /// @notice The MonUSD token contract instance for testing
    MonUSD public monUSD;

    /**
     * @notice Sets up the test environment with MonUSD proxy and initial configuration
     * @dev Deploys MonUSD implementation, creates proxy, initializes token, and funds test user
     * @custom:setup-phase Configures MonUSD token system for testing
     * @custom:permissions Uses deployer for contract deployment and manager for initialization
     */
    function setUp() public {
        // Deploy MonUSD implementation contract as deployer
        vm.startPrank(deployer);
        MonUSD monUSDImpl = new MonUSD();
        // Create proxy pointing to implementation with manager as admin
        monUSD = MonUSD(address(new MonUSDProxy(address(monUSDImpl), manager)));
        vm.stopPrank();

        // Initialize the MonUSD system as manager
        vm.startPrank(manager);
        // Initialize the proxy contract with token name and symbol
        monUSD.initialize("Monad USD", "monUSD");
        // Add USDC as an accepted stablecoin for deposits
        monUSD.addStablecoin(USDC);
        vm.stopPrank();

        // Provide test user with 2000 USDC for testing
        deal(address(USDC), user, 2000 * 10 ** 6);
    }

    /**
     * @notice Tests USDC deposit and withdrawal functionality
     * @dev Verifies that users can deposit USDC and receive equivalent monUSD tokens, then withdraw
     * @custom:test-flow Deposit 500 USDC → Verify 500 monUSD minted → Withdraw all monUSD
     * @custom:assertions Checks monUSD balance after deposit and successful withdrawal
     */
    function testDepositUSDC() public {
        // Start test as user
        vm.startPrank(user);
        uint256 amount = 500 * 10 ** 6; // 500 USDC (6 decimals)
        // Approve MonUSD contract to spend user's USDC
        IERC20(USDC).approve(address(monUSD), amount);
        // Deposit USDC to mint monUSD tokens
        monUSD.deposit(USDC, amount);
        vm.stopPrank();

        // Verify user received 500 monUSD tokens (18 decimals)
        assertEq(monUSD.balanceOf(user), 500 * 10 ** 18);

        // Test withdrawal functionality
        vm.startPrank(user);
        // Withdraw all monUSD tokens to get back USDC
        monUSD.withdraw(USDC, 500 * 10 ** 18);
        vm.stopPrank();
    }
}
