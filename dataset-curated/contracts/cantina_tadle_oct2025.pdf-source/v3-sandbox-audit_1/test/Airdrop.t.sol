// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Deployers} from "test/utils/Deployers.sol";
import {AirdropResolver} from "src/relayers/monad_testnet/airdrop/main.sol";
import {TadleImplementationV1} from "src/relayers/monad_testnet/implementation/ImplementationV1.sol";

/**
 * @title AirdropTest
 * @author Tadle Team
 * @notice Test contract for validating airdrop functionality
 * @dev This contract tests the airdrop mechanism for USDC tokens on Monad testnet
 * @custom:test-scope Covers airdrop claim functionality and balance verification
 * @custom:network Designed for Monad testnet environment
 */
contract AirdropTest is Test, Deployers {
    /**
     * @notice Sets up the test environment before each test execution
     * @dev Deploys all necessary contracts and initializes the airdrop system
     * @custom:setup-phase Prepares the complete testing infrastructure
     * @custom:contracts Deploys core protocol contracts and airdrop functionality
     */
    function setUp() public {
        // Deploy all core Tadle sandbox contracts (Auth, Factory, Connectors, etc.)
        deployCoreContracts();

        // Deploy and configure the airdrop contract with token settings
        deployAndInitializeAirdrop();

        deal(address(USDC), address(airdrop), 100 * 1e6);
    }

    /**
     * @notice Tests the airdrop functionality for USDC tokens
     * @dev Simulates a user claiming USDC tokens through the airdrop mechanism
     * @custom:test-command forge test -vvvv --rpc-url https://testnet-rpc.monad.xyz --match-test testAirdrop
     * @custom:assertion Verifies that user receives exactly 10 USDC (10 * 1e6 wei)
     * @custom:network Requires Monad testnet RPC connection for execution
     */
    function testAirdrop() public {
        // Start impersonating the test user for transaction simulation
        vm.startPrank(user);

        // Execute airdrop claim for USDC tokens
        // This should mint/transfer 10 USDC to the user's address
        airdrop.airdrop(USDC);

        // Stop impersonating the user
        vm.stopPrank();

        // Verify that the user received exactly 10 USDC tokens
        // USDC has 6 decimal places, so 10 * 1e6 = 10,000,000 wei = 10 USDC
        assertEq(IERC20(USDC).balanceOf(user), 10 * 1e6);
    }

    /**
     * @notice Tests the airdrop functionality using a sandbox account with signature verification
     * @dev Simulates claiming USDC tokens through a sandbox account using cryptographic signatures
     * @custom:test-flow Creates sandbox account → Prepares signed claim → Executes claim → Verifies balance
     * @custom:signature Uses pre-computed signature for claim verification (deadline: 20000000000, level: 1)
     * @custom:assertion Verifies that sandbox account receives exactly 10 USDC tokens
     * @custom:security Tests signature-based authorization for airdrop claims
     */
    function testAirdropWithSandBoxAccount() public {
        // Create a sandbox account for the user to test proxy-based airdrop claims
        address sandbox_account = createSandBoxAccount();

        // Start impersonating the user for transaction simulation
        vm.startPrank(user);

        // Prepare transaction data for airdrop claim through sandbox account
        string[] memory _targetNames = new string[](1);
        _targetNames[0] = "Airdrop-Gas-v1.0.0"; // Target the airdrop connector
        bytes[] memory _datas = new bytes[](1);

        /**
         * @dev Signature generation reference (JavaScript/Web3.js):
         * const message = keccak256(web3.utils.encodePacked(
         *     sandbox_account,  // Claiming account address
         *     USDC,            // Token address
         *     user,            // Beneficiary address
         *     "1",             // Airdrop level
         *     20000000000      // Deadline timestamp
         * ));
         * const signature = web3.eth.accounts.sign(message, MANAGER_PRIVATE_KEY);
         *
         * @custom:signature Pre-computed signature for testing purposes
         * @custom:security In production, signatures should be generated dynamically
         */

        // Encode the claim function call with all required parameters
        bytes memory _data = abi.encodeWithSelector(
            AirdropResolver.claim.selector,
            20000000000, // deadline - timestamp until which the claim is valid
            1, // level - airdrop tier/level for the user
            address(USDC), // token - USDC token address to be claimed
            address(user), // to - recipient address for the airdrop
            bytes(
                // Pre-computed signature for claim authorization
                hex"459de52211c3c41f2034649b107b3c04ead471b1622da1f96446301312a7195d46a6b5c9e84a6e664fbb8a16d731c28ffd370f30fd95ebf0aaa3c332417dd2e81b"
            )
        );

        _datas[0] = _data;

        // Execute the airdrop claim through the sandbox account's cast function
        TadleImplementationV1(payable(sandbox_account)).cast(
            _targetNames,
            _datas
        );

        // Stop impersonating the user
        vm.stopPrank();

        // Verify that the sandbox account received exactly 10 USDC tokens
        // USDC has 6 decimal places, so 10 * 1e6 = 10,000,000 wei = 10 USDC
        assertEq(IERC20(USDC).balanceOf(sandbox_account), 10 * 1e6);
    }

    /**
     * @notice Tests the check-in functionality for airdrop eligibility
     * @dev Simulates a user performing a check-in action to maintain airdrop eligibility
     * @custom:test-flow User performs check-in → Verifies successful execution
     * @custom:purpose Check-in may be required to maintain active status for airdrops
     * @custom:frequency Typically performed daily or periodically as per protocol rules
     */
    function testCheckIn() public {
        // Start impersonating the user for transaction simulation
        vm.startPrank(user);

        // Perform check-in action to maintain airdrop eligibility
        // This function may update user's last activity timestamp or status
        airdrop.checkIn();

        // Stop impersonating the user
        vm.stopPrank();
    }
}
