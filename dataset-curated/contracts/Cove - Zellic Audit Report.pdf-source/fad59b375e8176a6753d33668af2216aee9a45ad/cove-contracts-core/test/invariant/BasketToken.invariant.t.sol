// SPDX-License-Identifier: BUSL-1.1
// solhint-disable one-contract-per-file
pragma solidity 0.8.28;

import { StdInvariant } from "forge-std/StdInvariant.sol";
import { console } from "forge-std/console.sol";

import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { InvariantHandler } from "test/invariant/InvariantHandler.t.sol";
import { BaseTest } from "test/utils/BaseTest.t.sol";

import { AssetRegistry } from "src/AssetRegistry.sol";
import { BasketToken } from "src/BasketToken.sol";

/// @notice Invariant test suite for the BasketToken contract.
/// @dev This suite checks the contract's invariants by fuzzing its state and call sequences.
/// Invariant tests are set up using the _InvariantTest and Handler contract.
/// The _InvariantTest deploys relevant contracts and the handler for them,
/// targeting the contract with `targetContract`.
/// Invariant test configurations are determined in foundry.toml,
/// allowing for adjustments in call depth and runs to explore contract states effectively.
contract BasketToken_InvariantTest is StdInvariant, BaseTest {
    BasketTokenHandler public basketTokenHandler;

    // Setup function to initialize the test environment.
    // It creates mock ERC20 assets and deploys a BasketTokenHandler to interact with the BasketToken.
    // The target contract is explicitly set to avoid testing all deployed contracts.
    function setUp() public override {
        super.setUp();
        forkNetworkAt("mainnet", 21_238_272);
        IERC20[] memory assets = new IERC20[](3);
        assets[0] = IERC20(ETH_USDT);
        assets[1] = IERC20(ETH_SUSDE);
        assets[2] = IERC20(ETH_WETH);

        basketTokenHandler = new BasketTokenHandler(new BasketToken(), assets);
        vm.label(address(basketTokenHandler), "basketTokenHandler");
        targetContract(address(basketTokenHandler));
    }

    // Invariant: If the BasketToken is initialized, the BasketManager must be the contract creator.
    // This checks the relationship between the BasketToken and its creator.
    function invariant_basketManagerIsImmutableContractCreator() public {
        if (!basketTokenHandler.initialized()) {
            assertEq(address(basketTokenHandler.basketToken()), address(0), "BasketToken should not be initialized");
            return;
        }
        address basketManager = basketTokenHandler.basketToken().basketManager();
        assertEq(basketManager, address(basketTokenHandler), "BasketManager is not the contract creator");
    }

    // Invariant: totalPendingDeposits must equal the total deposits requested but not yet fulfilled.
    // This ensures that the state of pending deposits is accurately tracked.
    function invariant_totalPendingDeposits() public {
        if (!basketTokenHandler.initialized()) {
            return;
        }
        assertEq(
            basketTokenHandler.depositsPendingRebalance(),
            basketTokenHandler.basketToken().totalPendingDeposits(),
            "depositsPendingRebalance should match totalPendingDeposits"
        );
    }

    // Invariant: The total supply of the BasketToken must always equal the sum of all fulfilled deposits shares.
    // This ensures that the total supply accurately reflects the underlying assets held by the BasketToken.
    function invariant_totalSupply() public {
        if (!basketTokenHandler.initialized()) {
            return;
        }
        assertEq(
            basketTokenHandler.totalSupply(),
            basketTokenHandler.basketToken().totalSupply(),
            "totalSupply should match totalSupply"
        );
    }
}

/// @title BasketTokenHandler for Invariant Tests
/// @notice This contract interacts with the BasketToken and tests state changes after each function call.
/// @dev Public/external functions in this contract are called randomly by the invariant test contract.
/// It is responsible for ensuring the BasketToken behaves as expected under various conditions.
/// Handlers are created for all public/external functions to track state changes effectively.
contract BasketTokenHandler is InvariantHandler {
    using SafeERC20 for IERC20;

    BasketToken public basketTokenImpl;
    BasketToken public basketToken;
    bool public initialized = false;

    uint256 public depositsPendingRebalance;
    uint256 private depositsPendingFulfill;
    uint256 public redeemsPendingRebalance;
    uint256 private redeemsPendingFulfill;
    uint256 public totalSupply;

    uint256 private constant ACTOR_COUNT = 5;

    IERC20[] private assets;

    // Constructor to initialize the handler with a BasketToken implementation and a list of assets.
    constructor(BasketToken basketTokenImpl_, IERC20[] memory assets_) InvariantHandler(ACTOR_COUNT) {
        basketTokenImpl = basketTokenImpl_;
        assets = assets_;
    }

    // Function to initialize the BasketToken with the specified parameters.
    // It assumes the contract is not already initialized and that valid addresses are provided.
    function initialize(
        uint256 assetIndex,
        string memory name_,
        string memory symbol_,
        uint256 bitFlag_,
        address strategy_,
        address assetRegistry_
    )
        public
    {
        vm.assume(!initialized);
        vm.assume(address(strategy_) != address(0));
        vm.assume(address(assetRegistry_) != address(0));

        // Ensure the assetIndex is within bounds of the assets array.
        assetIndex = bound(assetIndex, 0, assets.length - 1);
        IERC20 asset = assets[assetIndex];

        initialized = true;
        basketToken = BasketToken(Clones.clone(address(basketTokenImpl)));
        vm.label(address(basketToken), "basketToken");

        basketToken.initialize(asset, name_, symbol_, bitFlag_, strategy_, assetRegistry_);

        // Mock the AssetRegistry to simulate that no assets are paused.
        vm.mockCall(
            address(assetRegistry_),
            abi.encodeWithSelector(AssetRegistry.hasPausedAssets.selector, bitFlag_),
            abi.encode(false)
        );
    }

    // Function to fulfill a deposit request.
    // It assumes the contract is initialized and there are pending deposits to fulfill.
    // This function must not revert to ensure successful transaction executions.
    function fulfillDeposit(uint256 shares) public {
        vm.assume(initialized);
        vm.assume(depositsPendingFulfill > 0);
        vm.assume(shares > 0 && shares < type(uint256).max / 1e18);
        console.log("fulfillDeposit: shares=%d", shares);
        basketToken.fulfillDeposit(shares);
        depositsPendingFulfill = 0;
        totalSupply += shares;
    }

    // Use maxDeposit to claim the maximum deposit amount for a user.
    // This function tracks the state of deposits and ensures correct share allocation.
    function deposit(uint256 userIdx) public useActor(userIdx) {
        console.log("   deposit: userAddr=%s", currentActor);
        vm.assume(initialized);
        uint256 depositAmount = basketToken.maxDeposit(currentActor);
        vm.assume(depositAmount > 0); // Ensure there is a deposit amount to claim.

        uint256 expectedShares = basketToken.maxMint(currentActor);
        uint256 sharesBefore = basketToken.balanceOf(currentActor);
        uint256 returnedShares = basketToken.deposit(depositAmount, currentActor);

        assertEq(
            basketToken.balanceOf(currentActor),
            sharesBefore + expectedShares,
            "balanceOf should increase by depositAmount"
        );
        assertEq(returnedShares, expectedShares, "deposit should return the expected number of shares");
    }

    // Function to test deposit reversion when using less than the max deposit amount.
    // This ensures that the deposit function behaves correctly under boundary conditions.
    function deposit_revertWhen_UsingDifferentThanMaxDeposit(
        uint256 userIdx,
        uint256 amount
    )
        public
        useActor(userIdx)
    {
        console.log("   deposit_revertWhen_UsingLessThanMaxDeposit: userAddr=%s", currentActor);
        vm.assume(initialized);
        uint256 maxDeposit = basketToken.maxDeposit(currentActor);
        vm.assume(amount != maxDeposit);

        // Deposit different amounts and check for reversion.
        try basketToken.deposit(amount, currentActor) returns (uint256 shares) {
            assertTrue(false, "deposit should revert when using less than maxDeposit");
        } catch { }
    }

    // Check the max functions for deposit, mint, redeem, and withdraw never reverts.
    function maxFunctions(uint256 userIdx) public useActor(userIdx) {
        console.log("   maxFunctions: userAddr=%s", currentActor);
        vm.assume(initialized);

        basketToken.maxDeposit(currentActor);
        basketToken.maxMint(currentActor);
        basketToken.maxRedeem(currentActor);
        basketToken.maxWithdraw(currentActor);
    }

    // Function to test preview functions for deposit, mint, redeem, and withdraw always reverting.
    function previewFunctions_revertWhen_Always(uint256 amount) public {
        console.log("   previewFunctions_revertWhen_Always: amount=%d", amount);
        vm.assume(initialized);

        // Call preview functions and check for reversion.
        try basketToken.previewDeposit(amount) returns (uint256) {
            assertTrue(false, "previewDeposit should revert");
        } catch { }

        try basketToken.previewMint(amount) returns (uint256) {
            assertTrue(false, "previewRedeemShares should revert");
        } catch { }

        try basketToken.previewRedeem(amount) returns (uint256) {
            assertTrue(false, "previewRedeem should revert");
        } catch { }

        try basketToken.previewWithdraw(amount) returns (uint256) {
            assertTrue(false, "previewRedeemShares should revert");
        } catch { }
    }

    // Function to request a deposit for a specific user.
    // It assumes the contract is initialized and the user has no pending deposit requests.
    // This function tracks the state of pending deposits accurately.
    function requestDeposit(uint256 userIdx, uint256 depositAmount) public useActor(userIdx) {
        console.log("   requestDeposit: userAddr=%s, depositAmount=%d", currentActor, depositAmount);
        vm.assume(initialized);
        uint256 nextRequestId = basketToken.nextDepositRequestId();
        vm.assume(basketToken.pendingDepositRequest(nextRequestId - 2, currentActor) == 0);
        vm.assume(basketToken.maxDeposit(currentActor) == 0);
        depositAmount = bound(depositAmount, 1, type(uint256).max / 1e18);

        uint256 before = basketToken.totalPendingDeposits();
        uint256 userRequestBefore = basketToken.pendingDepositRequest(nextRequestId, currentActor);

        address asset = address(basketToken.asset());
        deal(asset, currentActor, depositAmount);
        IERC20(asset).forceApprove(address(basketToken), type(uint256).max);

        uint256 requestId = basketToken.requestDeposit(depositAmount, currentActor, currentActor);
        assertEq(requestId, nextRequestId, "requestId should match nextRequestId");

        assertEq(
            basketToken.totalPendingDeposits(),
            before + depositAmount,
            "totalPendingDeposits should increase by depositAmount"
        );
        assertEq(
            basketToken.lastDepositRequestId(currentActor), requestId, "lastDepositRequestId should match requestId"
        );
        assertEq(
            basketToken.pendingDepositRequest(requestId, currentActor),
            userRequestBefore + depositAmount,
            "pendingDepositRequest should increase by depositAmount"
        );

        depositsPendingRebalance += depositAmount;
    }

    // Function to request a redeem for a specific user.
    // It assumes the contract is initialized and the user has no pending redeem requests.
    // This function tracks the state of pending redeems accurately.
    function requestRedeem(uint256 userIdx, uint256 redeemAmount) public useActor(userIdx) {
        console.log("   requestRedeem: userAddr=%s, redeemAmount=%d", currentActor, redeemAmount);
        vm.assume(initialized);
        uint256 nextRequestId = basketToken.nextRedeemRequestId();
        vm.assume(basketToken.pendingRedeemRequest(nextRequestId - 2, currentActor) == 0);
        vm.assume(basketToken.maxRedeem(currentActor) == 0);
        uint256 userBalance = basketToken.balanceOf(currentActor);
        vm.assume(userBalance > 0);
        redeemAmount = bound(redeemAmount, 1, userBalance);

        uint256 before = basketToken.totalPendingRedemptions();
        uint256 userRequestBefore = basketToken.pendingRedeemRequest(nextRequestId, currentActor);

        uint256 requestId = basketToken.requestRedeem(redeemAmount, currentActor, currentActor);
        assertEq(requestId, nextRequestId, "requestId should match nextRequestId");

        assertEq(
            basketToken.totalPendingRedemptions(),
            before + redeemAmount,
            "totalPendingRedemptions should increase by redeemAmount"
        );
        assertEq(basketToken.lastRedeemRequestId(currentActor), requestId, "lastRedeemRequestId should match requestId");
        assertEq(
            basketToken.pendingRedeemRequest(requestId, currentActor),
            userRequestBefore + redeemAmount,
            "pendingRedeemRequest should increase by redeemAmount"
        );

        redeemsPendingRebalance += redeemAmount;
    }

    // Function to prepare the BasketToken for a rebalance.
    // It assumes there are no unfulfilled requests from the previous rebalance.
    // The function resets the pending deposit and redeem counters after the rebalance.
    function prepareForRebalance() public {
        vm.assume(initialized);
        vm.assume(depositsPendingFulfill == 0 && redeemsPendingFulfill == 0);
        console.log("   prepareForRebalance:");
        uint256 nextDepositId = basketToken.nextDepositRequestId();
        uint256 nextRedeemId = basketToken.nextRedeemRequestId();
        uint256 pendingRedemptions = basketToken.totalPendingRedemptions();

        // Call prepareForRebalance and check the return value.
        // This function must not revert to ensure successful transaction executions.
        // TODO: update the logic to test for fee calculation.
        (, uint256 redeems) = basketToken.prepareForRebalance(0, address(0));
        assertEq(redeems, pendingRedemptions, "prepareForRebalance should return totalPendingRedemptions");
        assertEq(
            pendingRedemptions,
            redeemsPendingRebalance,
            "totalPendingRedemptions should match counter redeemsPendingRebalance"
        );

        // Check state changes after rebalance.
        assertEq(basketToken.totalPendingRedemptions(), 0, "totalPendingRedemptions should be 0");
        if (depositsPendingRebalance > 0) {
            assertEq(
                basketToken.nextDepositRequestId(), nextDepositId + 2, "nextDepositRequestId should increment by 2"
            );
        } else {
            assertEq(basketToken.nextDepositRequestId(), nextDepositId, "nextDepositRequestId should not change");
        }
        if (redeemsPendingRebalance > 0) {
            assertEq(basketToken.nextRedeemRequestId(), nextRedeemId + 2, "nextRedeemRequestId should increment by 2");
        } else {
            assertEq(basketToken.nextRedeemRequestId(), nextRedeemId, "nextRedeemRequestId should not change");
        }

        // Reset counters after rebalance.
        depositsPendingFulfill = depositsPendingRebalance;
        redeemsPendingFulfill = redeemsPendingRebalance;
        depositsPendingRebalance = 0;
        redeemsPendingRebalance = 0;
    }
}
