// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {Deployers} from "test/utils/Deployers.sol";
import {UniswapSwapRouter02Resolver} from "src/relayers/monad_testnet/uniswap-swap/main.sol";
import {TadleImplementationV1} from "src/relayers/monad_testnet/implementation/ImplementationV1.sol";

/**
 * @title UserCastTest
 * @author Tadle Team
 * @notice Test contract for validating user cast functionality with Uniswap integration
 * @dev This contract tests the cast mechanism for executing Uniswap swaps through sandbox accounts
 * @custom:test-scope Covers Uniswap Router02 integration and token swapping functionality
 * @custom:network Designed for Monad testnet environment with Uniswap V2 compatibility
 */
contract UserCastTest is Test, Deployers {
    /**
     * @notice Sets up the test environment before each test execution
     * @dev Deploys all necessary contracts and initializes the Uniswap Router02 system
     * @custom:setup-phase Prepares the complete testing infrastructure
     * @custom:contracts Deploys core protocol contracts and Uniswap Router02 functionality
     */
    function setUp() public {
        // Deploy all core Tadle sandbox contracts (Auth, Factory, Connectors, etc.)
        deployCoreContracts();

        // Deploy and configure the Uniswap Router02 connector with necessary permissions
        deployAndInitializeUniswapSwapRouter02Connect();
    }

    /**
     * @notice Tests Uniswap Router02 swap functionality through sandbox account
     * @dev Simulates swapping ETH for DAK tokens using Uniswap V2 router
     * @custom:test-command forge test -vvvv --rpc-url https://testnet-rpc.monad.xyz --match-test test_uniswap_swap_router02
     * @custom:test-flow Creates sandbox account → Funds with ETH → Executes swap → Verifies transaction
     * @custom:swap-path WETH → DAK using Uniswap V2 router
     * @custom:network Requires Monad testnet RPC connection for execution
     */
    function testUniswapSwapRouter02() public {
        // Create a sandbox account for the user to test proxy-based swaps
        address sandbox_account = createSandBoxAccount();

        // Provide 2 ETH to the sandbox account for swap testing
        deal(sandbox_account, 2 ether);

        // Start impersonating the user for transaction simulation
        vm.startPrank(user);

        // Prepare transaction data for Uniswap swap through sandbox account
        string[] memory _targetNames = new string[](1);
        _targetNames[0] = "UniswapSwapRouter02-v1.0.0"; // Target the Uniswap Router02 connector
        bytes[] memory _datas = new bytes[](1);

        // Define swap path: WETH → DAK
        address[] memory path = new address[](2);
        path[0] = address(WETH_ADDR); // Input token: Wrapped ETH
        path[1] = address(DAK); // Output token: DAK token

        // Encode path data for Uniswap V2 router
        bytes memory path_data = abi.encode(
            keccak256("UNISWAP_V2_SWAP_ROUTER"), // Router signature identifier
            abi.encode(path) // Encoded swap path
        );

        // Encode the buy function call with swap parameters
        bytes memory _data = abi.encodeWithSelector(
            UniswapSwapRouter02Resolver.buy.selector,
            true, // isEth - indicates ETH input
            1 ether, // amountIn - amount of ETH to swap
            0, // amountOutMin - minimum output amount (0 for testing)
            path_data, // path - encoded swap path data
            0, // getId - storage ID for input amount (0 = use direct value)
            0 // setId - storage ID for output amount (0 = don't store)
        );

        _datas[0] = _data;

        // Execute the swap through the sandbox account's cast function
        TadleImplementationV1(payable(sandbox_account)).cast(
            _targetNames,
            _datas
        );

        // Stop impersonating the user
        vm.stopPrank();
    }
}
