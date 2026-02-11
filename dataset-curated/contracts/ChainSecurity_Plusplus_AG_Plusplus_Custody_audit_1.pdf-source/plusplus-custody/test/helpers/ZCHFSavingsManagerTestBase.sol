// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";

// Import the contract under test. The path assumes that the
// ZCHFSavingsManager.sol file resides in the `src` directory of the
// repository. Adjust the import path if your project uses a different
// layout.
// Use a root-relative import so that Foundry resolves the contract from the
// project's `src` directory. Adjust this if your contract lives elsewhere.
import {ZCHFSavingsManager} from "src/ZCHFSavingsManager.sol";

import {MockERC20} from "../utils/MockERC20.sol";
import {MockSavings} from "../utils/MockSavings.sol";

/// @title ZCHFSavingsManagerTestBase
/// @notice Provides a shared setup for ZCHFSavingsManager tests. It
/// deploys a mock ERC20 token and mock savings module, creates a
/// ZCHFSavingsManager instance and assigns roles. Derived test
/// contracts can call `depositExample()` to quickly create a deposit for
/// use in their assertions.
abstract contract ZCHFSavingsManagerTestBase is Test {
    // Addresses used throughout the tests
    address internal admin;
    address internal operator;
    address internal receiver;
    address internal user;

    // Deployed contracts
    MockERC20 internal token;
    MockSavings internal savings;
    ZCHFSavingsManager internal manager;

    // Role identifiers (cached for convenience)
    bytes32 internal constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 internal constant RECEIVER_ROLE = keccak256("RECEIVER_ROLE");

    /// @notice Common setup executed before each test case. Deploys mocks,
    /// the system under test and assigns roles.
    function setUp() public virtual {
        // Create deterministic addresses for participants
        admin = makeAddr("admin");
        operator = makeAddr("operator");
        receiver = makeAddr("receiver");
        user = makeAddr("user");

        // Deploy mocks
        token = new MockERC20("MockERC20", "MCK", 18);
        savings = new MockSavings();
        token.setUnlimitedAllowanceForSavingsModule(address(savings));

        // Deploy the ZCHFSavingsManager with the admin and mocks
        manager = new ZCHFSavingsManager(admin, address(token), address(savings));

        // Grant roles & limits
        vm.startPrank(admin);
        manager.grantRole(OPERATOR_ROLE, operator);
        manager.grantRole(RECEIVER_ROLE, receiver);
        manager.setDailyLimit(operator, 1_000_000e18);
        vm.stopPrank();

        // Mint tokens to the user and this contract for use as deposit
        token.mint(user, 1e24);
        token.mint(address(this), 1e24);

        // Allow manager to transfer tokens from user and this contract
        // Approve the manager to spend tokens from the user
        vm.prank(user);
        token.approve(address(manager), type(uint256).max);

        // Approve the manager to spend tokens from this contract
        token.approve(address(manager), type(uint256).max);
    }

    /// @notice Helper to create a single deposit. It constructs arrays
    /// containing one identifier and one amount and calls createDeposits
    /// from the operator.
    /// @param id The identifier for the deposit.
    /// @param amount The initial amount to deposit.
    /// @param source The address from which tokens will be transferred.
    function depositExample(bytes32 id, uint192 amount, address source) internal {
        bytes32[] memory ids = new bytes32[](1);
        uint192[] memory amounts = new uint192[](1);
        ids[0] = id;
        amounts[0] = amount;
        vm.prank(operator);
        manager.createDeposits(ids, amounts, source);
    }
}
