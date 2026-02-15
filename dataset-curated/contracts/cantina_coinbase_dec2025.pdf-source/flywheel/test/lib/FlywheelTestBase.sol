// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Test} from "forge-std/Test.sol";

import {Flywheel} from "../../src/Flywheel.sol";

import {FailingERC20} from "./mocks/FailingERC20.sol";
import {MockCampaignHooksWithFees} from "./mocks/MockCampaignHooksWithFees.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {RevertingReceiver} from "./mocks/RevertingReceiver.sol";

/// @title FlywheelTestBase
/// @notice Minimal shared setup for Flywheel unit tests using MockCampaignHooksWithFees as the hook
/// @dev Provides helpers for creating/activating campaigns, funding, and building payout data
abstract contract FlywheelTest is Test {
    // Core contracts
    Flywheel public flywheel;
    MockCampaignHooksWithFees public mockCampaignHooksWithFees;
    MockERC20 public mockToken;
    RevertingReceiver public revertingRecipient;
    FailingERC20 public failingERC20;

    // Default actors
    address public owner; // Campaign owner (authorized withdrawer in MockCampaignHooksWithFees)
    address public manager; // Campaign manager (authorized to call payout functions in MockCampaignHooksWithFees)

    // Default campaign (created automatically in setUpFlywheelBase)
    address public campaign; // Default test campaign using MockCampaignHooksWithFees

    // Default values
    uint256 public constant INITIAL_TOKEN_BALANCE = 1_000_000e18;

    // Maximum amount for fuzzing to stay within MockERC20 balance limits
    // Set to half of initial balance to allow for multiple operations and overhead
    uint256 public constant MAX_FUZZ_AMOUNT = INITIAL_TOKEN_BALANCE / 2;

    /// @notice Sets up Flywheel + MockCampaignHooksWithFees and a default ERC20 for tests
    /// @dev Intended to be called in each test's setUp
    function setUpFlywheelBase() public virtual {
        flywheel = new Flywheel();
        mockCampaignHooksWithFees = new MockCampaignHooksWithFees(address(flywheel));

        // Default actors
        owner = address(0xA11CE);
        manager = address(0xB0B);

        // Deploy mock token with initial holders funded
        address[] memory initialHolders = new address[](3);
        initialHolders[0] = owner;
        initialHolders[1] = manager;
        initialHolders[2] = address(this);
        mockToken = new MockERC20(initialHolders);

        // Ensure balances are present for convenient funding
        // MockERC20 mints to provided holders in its constructor

        // Create default campaign for tests
        campaign = createSimpleCampaign(owner, manager, "Test Campaign", 1);

        // Deploy a contract that will reject native token transfers
        revertingRecipient = new RevertingReceiver();

        // Deploy a contract that will reject ERC20 transfers
        failingERC20 = new FailingERC20();

        // Add labels
        vm.label(address(flywheel), "Flywheel");
        vm.label(address(mockCampaignHooksWithFees), "MockCampaignHooksWithFees");
        vm.label(address(mockToken), "MockToken");
        vm.label(address(revertingRecipient), "RevertingRecipient");
        vm.label(address(failingERC20), "FailingERC20");
        vm.label(address(owner), "Owner");
        vm.label(address(manager), "Manager");
        vm.label(address(campaign), "Campaign");
        vm.label(address(this), "Test");
    }

    /// @notice Creates a MockCampaignHooksWithFees campaign via Flywheel
    /// @param owner_ Campaign owner
    /// @param manager_ Campaign manager (authorized to call payout functions)
    /// @param uri Campaign URI stored by MockCampaignHooksWithFees
    /// @param nonce Deterministic salt for the campaign address
    /// @return campaignAddr The newly created (or already deployed) campaign address
    function createSimpleCampaign(address owner_, address manager_, string memory uri, uint256 nonce)
        public
        returns (address campaignAddr)
    {
        bytes memory hookData = abi.encode(owner_, manager_, uri);
        campaignAddr = flywheel.createCampaign(address(mockCampaignHooksWithFees), nonce, hookData);
    }

    /// @notice Predicts a MockCampaignHooksWithFees campaign address without deploying it
    /// @param owner_ Campaign owner
    /// @param manager_ Campaign manager
    /// @param uri Campaign URI
    /// @param nonce Salt
    /// @return predicted Predicted campaign address
    function predictSimpleCampaign(address owner_, address manager_, string memory uri, uint256 nonce)
        public
        view
        returns (address predicted)
    {
        bytes memory hookData = abi.encode(owner_, manager_, uri);
        predicted = flywheel.predictCampaignAddress(address(mockCampaignHooksWithFees), nonce, hookData);
    }

    /// @notice Activates a campaign using MockCampaignHooksWithFees manager
    /// @param campaignAddr Campaign address
    /// @param manager_ Manager authorized in SimpleRewards
    function activateCampaign(address campaignAddr, address manager_) public {
        vm.prank(manager_);
        flywheel.updateStatus(campaignAddr, Flywheel.CampaignStatus.ACTIVE, "");
    }

    /// @notice Finalizes a campaign (ACTIVE -> FINALIZED)
    /// @param campaignAddr Campaign address
    /// @param manager_ Manager authorized in MockCampaignHooksWithFees
    function finalizeCampaign(address campaignAddr, address manager_) public {
        vm.startPrank(manager_);
        flywheel.updateStatus(campaignAddr, Flywheel.CampaignStatus.FINALIZED, "");
        vm.stopPrank();
    }

    /// @notice Funds a campaign with ERC20 tokens
    /// @param campaignAddr Campaign address
    /// @param amount Amount to transfer
    /// @param funder Address that funds the campaign
    function fundCampaign(address campaignAddr, uint256 amount, address funder) public {
        vm.prank(funder);
        mockToken.transfer(campaignAddr, amount);
    }

    /// @notice Builds a single payout entry array
    /// @param recipient Address to receive payout
    /// @param amount Amount to send
    /// @param extraData Extra data for event payloads
    /// @return payouts An array with one payout entry
    function buildSinglePayout(address recipient, uint256 amount, bytes memory extraData)
        public
        pure
        returns (Flywheel.Payout[] memory payouts)
    {
        payouts = new Flywheel.Payout[](1);
        payouts[0] = Flywheel.Payout({recipient: recipient, amount: amount, extraData: extraData});
    }

    /// @notice Calls Flywheel.send as the MockCampaignHooksWithFees manager
    /// @param campaignAddr Campaign address
    /// @param tokenAddress Token to use
    /// @param payouts Payout array to encode into hookData
    function managerSend(address campaignAddr, address tokenAddress, Flywheel.Payout[] memory payouts) public {
        vm.prank(manager);
        flywheel.send(campaignAddr, tokenAddress, abi.encode(payouts));
    }

    /// @notice Calls Flywheel.allocate as the MockCampaignHooksWithFees manager
    /// @param campaignAddr Campaign address
    /// @param tokenAddress Token to use
    /// @param payouts Payout array (used to derive allocations)
    function managerAllocate(address campaignAddr, address tokenAddress, Flywheel.Payout[] memory payouts) public {
        vm.prank(manager);
        flywheel.allocate(campaignAddr, tokenAddress, abi.encode(payouts));
    }

    /// @notice Calls Flywheel.deallocate as the MockCampaignHooksWithFees manager
    /// @param campaignAddr Campaign address
    /// @param tokenAddress Token to use
    /// @param payouts Payout array (used to derive allocations)
    function managerDeallocate(address campaignAddr, address tokenAddress, Flywheel.Payout[] memory payouts) public {
        vm.prank(manager);
        flywheel.deallocate(campaignAddr, tokenAddress, abi.encode(payouts));
    }

    /// @notice Calls Flywheel.distribute as the MockCampaignHooksWithFees manager
    /// @param campaignAddr Campaign address
    /// @param tokenAddress Token to use
    /// @param payouts Payout array (used to derive distributions)
    function managerDistribute(address campaignAddr, address tokenAddress, Flywheel.Payout[] memory payouts) public {
        vm.prank(manager);
        flywheel.distribute(campaignAddr, tokenAddress, abi.encode(payouts));
    }

    /// @notice Calls Flywheel.withdrawFunds as the MockCampaignHooksWithFees owner
    /// @param campaignAddr Campaign address
    /// @param tokenAddress Token to withdraw
    /// @param recipient Recipient of withdrawn funds
    /// @param amount Amount to withdraw
    function ownerWithdraw(address campaignAddr, address tokenAddress, address recipient, uint256 amount) public {
        vm.prank(owner);
        flywheel.withdrawFunds(
            campaignAddr,
            tokenAddress,
            abi.encode(Flywheel.Payout({recipient: recipient, amount: amount, extraData: ""}))
        );
    }

    // ============ Fuzz Utilities ============

    /// @notice Bounds an amount to be non-zero and within MAX_FUZZ_AMOUNT
    /// @param amount Fuzzed amount input
    /// @return Bounded amount between 1 and MAX_FUZZ_AMOUNT
    function boundToValidAmount(uint256 amount) public pure returns (uint256) {
        return bound(amount, 1, MAX_FUZZ_AMOUNT);
    }

    /// @notice Bounds an amount to be within MAX_FUZZ_AMOUNT (allows zero)
    /// @param amount Fuzzed amount input
    /// @return Bounded amount between 0 and MAX_FUZZ_AMOUNT
    function boundToMaxAmount(uint256 amount) public pure returns (uint256) {
        return bound(amount, 0, MAX_FUZZ_AMOUNT);
    }

    /// @notice Bounds an address to be non-zero
    /// @param addr Fuzzed address input
    /// @return Bounded address that is not address(0)
    function boundToValidPayableAddress(address addr) public returns (address) {
        address bounded = address(uint160(bound(uint160(addr), 1, type(uint160).max)));
        assumePayable(bounded);
        return bounded;
    }

    /// @notice Bounds two amounts for multi-allocation tests where total must not exceed MAX_FUZZ_AMOUNT
    /// @param amount1 First fuzzed amount
    /// @param amount2 Second fuzzed amount
    /// @return amount1Bounded First bounded amount (1 to MAX_FUZZ_AMOUNT/2)
    /// @return amount2Bounded Second bounded amount (1 to remaining capacity)
    function boundToValidMultiAmounts(uint256 amount1, uint256 amount2)
        public
        pure
        returns (uint256 amount1Bounded, uint256 amount2Bounded)
    {
        amount1Bounded = bound(amount1, 1, MAX_FUZZ_AMOUNT / 2);
        uint256 remaining = MAX_FUZZ_AMOUNT - amount1Bounded;
        amount2Bounded = bound(amount2, 1, remaining);
    }

    /// @notice Bounds fee basis points to valid range (0-1000) to prevent overflow
    /// @param feeBp Fuzzed fee basis points
    /// @return Bounded fee basis points between 0 and 1000 (10%)
    function boundToValidFeeBp(uint256 feeBp) public pure returns (uint16) {
        return uint16(bound(feeBp, 0, 1_000)); // Max 10% to prevent overflow with large amounts
    }

    /// @notice Builds a single fee distribution
    /// @param recipient Fee recipient address
    /// @param key Fee key for tracking
    /// @param amount Fee amount
    /// @param extraData Extra data for event payloads
    /// @return fees An array with one fee entry
    function buildSingleFee(address recipient, bytes32 key, uint256 amount, bytes memory extraData)
        public
        pure
        returns (Flywheel.Distribution[] memory fees)
    {
        fees = new Flywheel.Distribution[](1);
        fees[0] = Flywheel.Distribution({recipient: recipient, key: key, amount: amount, extraData: extraData});
    }

    /// @notice Builds hook data for send with payouts and fees
    /// @param payouts Array of payouts
    /// @param fees Array of fee distributions
    /// @param sendFeesNow Whether to send fees immediately
    /// @return Encoded hook data for send function
    function buildSendHookData(Flywheel.Payout[] memory payouts, Flywheel.Distribution[] memory fees, bool sendFeesNow)
        public
        pure
        returns (bytes memory)
    {
        return abi.encode(payouts, fees, sendFeesNow);
    }

    /// @notice Calculates fee amount from payout amount and basis points
    /// @param payoutAmount Base amount to calculate fee from
    /// @param feeBp Fee basis points (0-10000)
    /// @return Fee amount
    function calculateFeeAmount(uint256 payoutAmount, uint16 feeBp) public pure returns (uint256) {
        return (payoutAmount * feeBp) / 10_000;
    }
}
