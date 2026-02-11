// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { FarmingPlugin } from "@1inch/farming/contracts/FarmingPlugin.sol";
import { IERC20Errors } from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import { FixedPointMathLib } from "@solady/utils/FixedPointMathLib.sol";
import { EulerRouter } from "euler-price-oracle/src/EulerRouter.sol";
import { IERC20Plugins } from "token-plugins-upgradeable/contracts/interfaces/IERC20Plugins.sol";

import { BaseTest } from "test/utils/BaseTest.t.sol";
import { ERC20DecimalsMock } from "test/utils/mocks/ERC20DecimalsMock.sol";
import { ERC20Mock } from "test/utils/mocks/ERC20Mock.sol";
import { MockBasketManager } from "test/utils/mocks/MockBasketManager.sol";
import { MockFeeCollector } from "test/utils/mocks/MockFeeCollector.sol";

import { AssetRegistry } from "src/AssetRegistry.sol";
import { BasketManager } from "src/BasketManager.sol";
import { BasketToken } from "src/BasketToken.sol";
import { Errors } from "src/libraries/Errors.sol";
import { WeightStrategy } from "src/strategies/WeightStrategy.sol";

contract BasketTokenTest is BaseTest {
    using FixedPointMathLib for uint256;

    uint256 private constant MAX_USERS = 20;

    BasketToken public basket;
    BasketToken public basketTokenImplementation;
    MockBasketManager public basketManager;
    ERC20Mock public dummyAsset;
    address public assetRegistry;
    address public alice;
    address public owner;
    address public feeCollector;

    address[] public fuzzedUsers;
    uint256[] public depositAmounts;

    function setUp() public override {
        super.setUp();
        alice = createUser("alice");
        owner = createUser("owner");
        // create dummy asset
        dummyAsset = new ERC20Mock();
        feeCollector = address(new MockFeeCollector());
        basketTokenImplementation = new BasketToken();
        basketManager = new MockBasketManager(address(basketTokenImplementation));
        assetRegistry = createUser("assetRegistry");

        vm.prank(address(owner));
        basket = basketManager.createNewBasket(ERC20(dummyAsset), "Test", "TEST", 1, address(1), assetRegistry);
        vm.label(address(basket), "basketToken");

        // mock call to return ENABLED for the dummyAsset
        vm.mockCall(
            address(assetRegistry), abi.encodeCall(AssetRegistry.hasPausedAssets, basket.bitFlag()), abi.encode(false)
        );

        // create users for testing
        fuzzedUsers = new address[](MAX_USERS);
        for (uint256 i = 0; i < MAX_USERS; ++i) {
            fuzzedUsers[i] = createUser(string.concat("user", vm.toString(i)));
        }
    }

    function testFuzz_initialize_revertWhen_InvalidInitialization(
        address asset,
        string memory name,
        string memory symbol,
        uint256 bitFlag,
        address strategy,
        address assetRegistry_
    )
        public
    {
        BasketToken tokenImpl = new BasketToken();
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        tokenImpl.initialize(ERC20(asset), name, symbol, bitFlag, strategy, assetRegistry_);
    }

    function testFuzz_initialize_revertWhen_alreadyInitialized(
        address asset,
        string memory name,
        string memory symbol,
        uint256 bitFlag,
        address strategy,
        address assetRegistry_
    )
        public
    {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        basket.initialize(ERC20(asset), name, symbol, bitFlag, strategy, assetRegistry_);
    }

    function testFuzz_initialize(
        address from,
        uint8 assetDecimals,
        string memory name,
        string memory symbol,
        uint256 bitFlag,
        address strategy,
        address assetRegistry_
    )
        public
    {
        vm.assume(strategy != address(0));
        vm.assume(assetRegistry_ != address(0));
        BasketToken token = BasketToken(Clones.clone(address(basketTokenImplementation)));
        // Added mock due to foundry test issue
        ERC20DecimalsMock mockERC20 = new ERC20DecimalsMock(assetDecimals, "test", "TST");
        // Call initialize
        vm.prank(from);
        token.initialize(ERC20(mockERC20), name, symbol, bitFlag, strategy, assetRegistry_);

        // Check state
        assertEq(token.asset(), address(mockERC20));
        assertEq(token.name(), string.concat("CoveBasket-", name));
        assertEq(token.symbol(), string.concat("covb", symbol));
        assertEq(token.decimals(), assetDecimals);
        assertEq(token.bitFlag(), bitFlag);
        assertEq(token.strategy(), strategy);
        assertEq(token.assetRegistry(), assetRegistry_);
        assertEq(token.basketManager(), from);
        // https://eips.ethereum.org/EIPS/eip-165
        bytes4 erc165 = 0x01ffc9a7;
        // https://eips.ethereum.org/EIPS/eip-7575#erc-165-support
        bytes4 erc7575Vault = 0x2f0a18c5;
        bytes4 erc7575Share = 0xf815c03d;
        // https://eips.ethereum.org/EIPS/eip-7540#erc-165-support
        bytes4 erc7540Operator = 0xe3bc4e65;
        bytes4 erc7540Deposit = 0xce3bbe50;
        bytes4 erc7540Redeem = 0x620ee8e4;
        assertEq(token.supportsInterface(erc165), true);
        assertEq(token.supportsInterface(erc7575Vault), true);
        assertEq(token.supportsInterface(erc7575Share), true);
        assertEq(token.supportsInterface(erc7540Operator), true);
        assertEq(token.supportsInterface(erc7540Deposit), true);
        assertEq(token.supportsInterface(erc7540Redeem), true);
    }

    function testFuzz_initialize_revertsWhen_strategyZero(
        address from,
        address asset,
        uint8 assetDecimals,
        string memory name,
        string memory symbol,
        uint256 bitFlag,
        address assetRegistry_
    )
        public
    {
        vm.assume(asset != address(0));
        vm.assume(assetRegistry_ != address(0));
        BasketToken token = BasketToken(Clones.clone(address(basketTokenImplementation)));
        vm.mockCall(asset, abi.encodeWithSelector(ERC20.decimals.selector), abi.encode(assetDecimals));

        // Call initialize
        vm.prank(from);
        vm.expectRevert(Errors.ZeroAddress.selector);
        token.initialize(ERC20(asset), name, symbol, bitFlag, address(0), assetRegistry_);
    }

    function testFuzz_initialize_revertsWhen_assetRegistryZero(
        address from,
        address asset,
        uint8 assetDecimals,
        string memory name,
        string memory symbol,
        uint256 bitFlag,
        address strategy
    )
        public
    {
        vm.assume(asset != address(0));
        vm.assume(strategy != address(0));
        BasketToken token = BasketToken(Clones.clone(address(basketTokenImplementation)));
        vm.mockCall(asset, abi.encodeWithSelector(ERC20.decimals.selector), abi.encode(assetDecimals));

        // Call initialize
        vm.prank(from);
        vm.expectRevert(Errors.ZeroAddress.selector);
        token.initialize(ERC20(asset), name, symbol, bitFlag, strategy, address(0));
    }

    function testFuzz_requestDeposit(uint256 amount, address from) public returns (uint256 requestId) {
        vm.assume(from != address(basket) && from != address(basketManager) && from != address(0));
        amount = bound(amount, 1, type(uint256).max);
        dummyAsset.mint(from, amount);

        _totalAssetsMockCall();
        uint256 totalAssetsBefore = basket.totalAssets();
        uint256 balanceBefore = basket.balanceOf(from);
        uint256 dummyAssetBalanceBefore = dummyAsset.balanceOf(from);
        uint256 totalPendingDepositBefore = basket.totalPendingDeposits();
        uint256 maxDepositBefore = basket.maxDeposit(from);
        uint256 maxMintBefore = basket.maxMint(from);

        // Approve and request deposit
        vm.startPrank(from);
        dummyAsset.approve(address(basket), amount);
        requestId = basket.requestDeposit(amount, from, from);
        vm.stopPrank();

        // Check state
        assertEq(dummyAsset.balanceOf(from), dummyAssetBalanceBefore - amount);
        assertEq(basket.totalAssets(), totalAssetsBefore);
        assertEq(basket.balanceOf(from), balanceBefore);
        assertEq(basket.maxDeposit(from), maxDepositBefore);
        assertEq(basket.maxMint(from), maxMintBefore);
        assertEq(basket.pendingDepositRequest(requestId, from), amount);
        assertEq(basket.totalPendingDeposits(), totalPendingDepositBefore + amount);
    }

    function testFuzz_requestDeposit_withController(uint256 amount, address from, address controller) public {
        vm.assume(
            from != address(basket) && from != address(basketManager) && from != address(0) && controller != address(0)
                && from != controller
        );
        amount = bound(amount, 1, type(uint256).max);
        dummyAsset.mint(from, amount);

        _totalAssetsMockCall();
        uint256 totalAssetsBefore = basket.totalAssets();
        uint256 balanceBefore = basket.balanceOf(from);
        uint256 dummyAssetBalanceBefore = dummyAsset.balanceOf(from);
        uint256 totalPendingDepositBefore = basket.totalPendingDeposits();
        uint256 maxDepositBefore = basket.maxDeposit(controller);
        uint256 maxMintBefore = basket.maxMint(controller);

        // Approve and request deposit
        vm.startPrank(from);
        basket.setOperator(controller, true);
        dummyAsset.approve(address(basket), amount);
        vm.stopPrank();
        vm.prank(controller);
        uint256 requestId = basket.requestDeposit(amount, controller, from);

        // Check state
        assertEq(dummyAsset.balanceOf(from), dummyAssetBalanceBefore - amount);
        assertEq(basket.totalAssets(), totalAssetsBefore);
        assertEq(basket.balanceOf(controller), balanceBefore);
        assertEq(basket.maxDeposit(controller), maxDepositBefore);
        assertEq(basket.maxMint(controller), maxMintBefore);
        assertEq(basket.pendingDepositRequest(requestId, controller), amount);
        assertEq(basket.totalPendingDeposits(), totalPendingDepositBefore + amount);
    }

    function test_requestDeposit_passWhen_existingDepositRequest() public {
        uint256 amount = 1e22;
        uint256 amount2 = 1e20;
        dummyAsset.mint(alice, amount);
        vm.startPrank(alice);
        dummyAsset.approve(address(basket), amount);

        // Call requestDeposit twice
        uint256 requestId = basket.requestDeposit(amount, alice, alice);
        assertEq(basket.pendingDepositRequest(requestId, alice), amount);
        assertEq(basket.totalPendingDeposits(), amount);
        dummyAsset.mint(alice, amount2);
        dummyAsset.approve(address(basket), amount2);
        uint256 newRequestId = basket.requestDeposit(amount2, alice, alice);
        assertEq(basket.pendingDepositRequest(newRequestId, alice), amount + amount2);
        assertEq(basket.totalPendingDeposits(), amount + amount2);
    }

    function testFuzz_requestDeposit_revertWhen_MustClaimOutstandingDeposit(
        uint256 amount,
        address controller
    )
        public
    {
        // Assume a valid deposit amount greater than 0
        vm.assume(amount > 0 && amount <= type(uint256).max);

        // Mint the deposit amount to alice
        dummyAsset.mint(alice, amount);

        // Alice approves the basket
        vm.startPrank(alice);
        dummyAsset.approve(address(basket), amount);
        basket.requestDeposit(amount, controller, alice);
        vm.stopPrank();

        // prepareForRebalance is called
        vm.prank(address(basketManager));
        basket.prepareForRebalance(0, feeCollector);

        // Attempt to make a second deposit without waiting for the first one to be fulfilled
        vm.prank(alice);
        vm.expectRevert(BasketToken.MustClaimOutstandingDeposit.selector);
        basket.requestDeposit(amount, controller, alice);
    }

    function test_requestDeposit_revertWhen_zeroAmount() public {
        vm.prank(alice);
        dummyAsset.approve(address(basket), 0);
        vm.expectRevert(Errors.ZeroAmount.selector);
        vm.prank(alice);
        basket.requestDeposit(0, alice, alice);
    }

    function test_requestDeposit_revertWhen_claimableDepositOutstanding() public {
        uint256 amount = 1e18;
        uint256 issuedShares = 1e17;
        dummyAsset.mint(alice, amount);
        vm.startPrank(alice);
        dummyAsset.approve(address(basket), amount);
        basket.requestDeposit(amount, alice, alice);
        vm.stopPrank();
        vm.startPrank(address(basketManager));
        basket.prepareForRebalance(0, feeCollector);
        basket.fulfillDeposit(issuedShares);
        vm.stopPrank();

        // Call requestDeposit while there is an outstanding deposit
        vm.expectRevert(BasketToken.MustClaimOutstandingDeposit.selector);
        vm.startPrank(alice);
        basket.requestDeposit(amount, alice, alice);
    }

    function test_requestDeposit_revertWhen_assetPaused() public {
        uint256 amount = 1e18;
        dummyAsset.mint(alice, amount);

        vm.mockCall(
            address(assetRegistry), abi.encodeCall(AssetRegistry.hasPausedAssets, basket.bitFlag()), abi.encode(true)
        );

        vm.startPrank(alice);
        dummyAsset.approve(address(basket), amount);
        vm.expectRevert(BasketToken.AssetPaused.selector);
        basket.requestDeposit(amount, alice, alice);
    }

    function test_requestDeposit_revertWhen_assetDisabled() public {
        uint256 amount = 1e18;
        dummyAsset.mint(alice, amount);

        vm.mockCall(
            address(assetRegistry), abi.encodeCall(AssetRegistry.hasPausedAssets, basket.bitFlag()), abi.encode(true)
        );

        vm.startPrank(alice);
        dummyAsset.approve(address(basket), amount);
        vm.expectRevert(BasketToken.AssetPaused.selector);
        basket.requestDeposit(amount, alice, alice);
    }

    function testFuzz_fulfillDeposit(uint256 totalAmount, uint256 issuedShares) public returns (uint256 requestId) {
        totalAmount = bound(totalAmount, 1, type(uint256).max);
        issuedShares = bound(issuedShares, 1, type(uint256).max);
        depositAmounts = new uint256[](MAX_USERS);
        uint256 remainingAmount = totalAmount;

        // Call requestDeposit from users with random amounts
        for (uint256 i = 0; i < MAX_USERS; ++i) {
            // Ignore the cases where a user ends up with zero deposit amount
            vm.assume(remainingAmount > 1);
            if (i == MAX_USERS - 1) {
                depositAmounts[i] = remainingAmount;
            } else {
                depositAmounts[i] =
                    bound(uint256(keccak256(abi.encodePacked(vm.getBlockTimestamp(), i))), 1, remainingAmount - 1);
            }
            remainingAmount -= depositAmounts[i];
            requestId = testFuzz_requestDeposit(depositAmounts[i], fuzzedUsers[i]);
        }
        assertEq(basket.totalPendingDeposits(), totalAmount);

        uint256 basketManagerBalanceBefore = dummyAsset.balanceOf(address(basketManager));
        uint256 basketBalanceOfBefore = basket.balanceOf(address(basket));

        // Call fulfillDeposit
        vm.startPrank(address(basketManager));
        basket.prepareForRebalance(0, feeCollector);
        basket.fulfillDeposit(issuedShares);
        vm.stopPrank();

        // Check state
        assertEq(dummyAsset.balanceOf(address(basketManager)), basketManagerBalanceBefore + totalAmount);
        assertEq(basket.balanceOf(address(basket)), basketBalanceOfBefore + issuedShares);
        assertEq(dummyAsset.balanceOf(address(basket)), 0);
        assertEq(dummyAsset.balanceOf(address(basketManager)), totalAmount);
        for (uint256 i = 0; i < MAX_USERS; ++i) {
            assertEq(basket.pendingDepositRequest(basket.lastDepositRequestId(fuzzedUsers[i]), fuzzedUsers[i]), 0);
            assertEq(basket.maxDeposit(fuzzedUsers[i]), depositAmounts[i]);
            assertEq(basket.maxMint(fuzzedUsers[i]), depositAmounts[i].fullMulDiv(issuedShares, totalAmount));
        }
        assertEq(basket.totalPendingDeposits(), 0);
    }

    function testFuzz_fulfillDeposit_revertsWhen_CannotFulfillWithZeroShares(
        uint256 totalAmount,
        address from
    )
        public
    {
        testFuzz_requestDeposit(totalAmount, from);
        vm.startPrank(address(basketManager));
        basket.prepareForRebalance(0, feeCollector);
        vm.expectRevert(BasketToken.CannotFulfillWithZeroShares.selector);
        basket.fulfillDeposit(0);
    }

    function testFuzz_fulfillDeposit_revertWhen_NoPendingDeposits(
        uint256 issuedShares,
        uint256 totalDepositAmount,
        uint256 redeemAmount
    )
        public
    {
        // Must do a full rebalnce cycle because requestId is initialized as 1 and fulfillDeposit() will underflow if
        // called
        testFuzz_withdraw(totalDepositAmount, issuedShares, redeemAmount);
        assertEq(basket.totalPendingDeposits(), 0);
        vm.startPrank(address(basketManager));
        basket.prepareForRebalance(0, feeCollector);
        vm.expectRevert(BasketToken.DepositRequestAlreadyFulfilled.selector);
        basket.fulfillDeposit(issuedShares);
    }

    function testFuzz_fulfillDeposit_revertsWhen_ZeroPendingDeposits(uint256 issuedShares) public {
        vm.startPrank(address(basketManager));
        vm.expectRevert(BasketToken.ZeroPendingDeposits.selector);
        basket.fulfillDeposit(issuedShares);
    }

    function testFuzz_fulfillDeposit_revertsWhen_notBasketManager(address from, uint256 issuedShares) public {
        vm.assume(from != basket.basketManager());
        vm.prank(from);
        vm.expectRevert(BasketToken.NotBasketManager.selector);
        basket.fulfillDeposit(issuedShares);
    }

    function testFuzz_fulFillDeposit_revertsWhen_DepositRequestAlreadyFulfilled(
        address from,
        uint256 issuedShares,
        uint256 amount
    )
        public
    {
        vm.assume(issuedShares > 0);
        testFuzz_requestDeposit(amount, from);
        vm.startPrank(address(basketManager));
        basket.prepareForRebalance(0, feeCollector);
        basket.fulfillDeposit(issuedShares);
        vm.expectRevert(BasketToken.DepositRequestAlreadyFulfilled.selector);
        basket.fulfillDeposit(issuedShares);
    }

    function testFuzz_deposit(uint256 amount, uint256 issuedShares) public returns (uint256 requestId) {
        // First, call testFuzz_fulfillDeposit which will requestDeposit and fulfillDeposit for users
        requestId = testFuzz_fulfillDeposit(amount, issuedShares);
        issuedShares = basket.balanceOf(address(basket));
        for (uint256 i = 0; i < MAX_USERS; ++i) {
            // Skip users with zero deposit amount. This is to avoid ZeroAmount error
            // Zero deposit amount happens due to splitting the total deposit amount among users
            uint256 userBalanceBefore = basket.balanceOf(fuzzedUsers[i]);
            uint256 maxDeposit = basket.maxDeposit(fuzzedUsers[i]);
            uint256 maxMint = basket.maxMint(fuzzedUsers[i]);
            assertGt(depositAmounts[i], 0, "users should have non-zero deposit amount before testing");
            assertGt(maxDeposit, 0, "Max deposit should be greater than 0 if user has pending deposit");
            assertGt(
                basket.claimableDepositRequest(requestId, fuzzedUsers[i]),
                0,
                "User should have claimable deposit request"
            );

            // Call deposit
            vm.prank(fuzzedUsers[i]);
            uint256 shares = basket.deposit(maxDeposit, fuzzedUsers[i]);

            // Check state
            assertEq(shares, maxMint);
            assertEq(basket.balanceOf(fuzzedUsers[i]), userBalanceBefore + maxMint);
            assertEq(basket.maxDeposit(fuzzedUsers[i]), 0);
            assertEq(basket.maxMint(fuzzedUsers[i]), 0);
        }

        // Check state
        uint256 lostShares = basket.balanceOf(address(basket));
        // @audit Guidance on how to establish the max loss of shares in edge cases
        assertLe(
            lostShares.fullMulDiv(1e18, issuedShares), 1e18, "Lost shares should be less than 100% of the issued shares"
        );
    }

    function testFuzz_deposit_operator(uint256 amount, uint256 issuedShares, address operator) public {
        vm.assume(operator != address(0));
        // First, call testFuzz_fulfillDeposit which will requestDeposit and fulfillDeposit for users
        uint256 requestId = testFuzz_fulfillDeposit(amount, issuedShares);
        issuedShares = basket.balanceOf(address(basket));
        for (uint256 i = 0; i < MAX_USERS; ++i) {
            // Skip users with zero deposit amount. This is to avoid ZeroAmount error
            // Zero deposit amount happens due to splitting the total deposit amount among users
            uint256 userBalanceBefore = basket.balanceOf(fuzzedUsers[i]);
            uint256 maxDeposit = basket.maxDeposit(fuzzedUsers[i]);
            uint256 maxMint = basket.maxMint(fuzzedUsers[i]);
            assertGt(depositAmounts[i], 0, "users should have non-zero deposit amount before testing");
            assertGt(maxDeposit, 0, "Max deposit should be greater than 0 if user has pending deposit");
            assertGt(
                basket.claimableDepositRequest(requestId, fuzzedUsers[i]),
                0,
                "User should have claimable deposit request"
            );

            // setOperator
            vm.prank(fuzzedUsers[i]);
            basket.setOperator(operator, true);
            // Call deposit from operator
            vm.prank(operator);
            uint256 shares = basket.deposit(maxDeposit, fuzzedUsers[i], fuzzedUsers[i]);

            // Check state
            assertEq(shares, maxMint);
            assertEq(basket.balanceOf(fuzzedUsers[i]), userBalanceBefore + maxMint);
            assertEq(basket.maxDeposit(fuzzedUsers[i]), 0);
            assertEq(basket.maxMint(fuzzedUsers[i]), 0);
        }

        // Check state
        uint256 lostShares = basket.balanceOf(address(basket));
        // @audit Guidance on how to establish the max loss of shares in edge cases
        assertLe(
            lostShares.fullMulDiv(1e18, issuedShares), 1e18, "Lost shares should be less than 100% of the issued shares"
        );
    }

    function testFuzz_deposit_revertWhen_operatorNotSet(
        uint256 amount,
        uint256 issuedShares,
        address operator
    )
        public
    {
        vm.assume(operator != address(0));
        // First, call testFuzz_fulfillDeposit which will requestDeposit and fulfillDeposit for users
        uint256 requestId = testFuzz_fulfillDeposit(amount, issuedShares);
        issuedShares = basket.balanceOf(address(basket));
        for (uint256 i = 0; i < MAX_USERS; ++i) {
            // Skip users with zero deposit amount. This is to avoid ZeroAmount error
            // Zero deposit amount happens due to splitting the total deposit amount among users
            uint256 maxDeposit = basket.maxDeposit(fuzzedUsers[i]);
            assertGt(depositAmounts[i], 0, "users should have non-zero deposit amount before testing");
            assertGt(maxDeposit, 0, "Max deposit should be greater than 0 if user has pending deposit");
            assertGt(
                basket.claimableDepositRequest(requestId, fuzzedUsers[i]),
                0,
                "User should have claimable deposit request"
            );
            vm.assume(operator != fuzzedUsers[i]);
            assert(!basket.isOperator(fuzzedUsers[i], operator));
            // Call deposit from operator
            vm.expectRevert(BasketToken.NotAuthorizedOperator.selector);
            vm.prank(operator);
            basket.deposit(maxDeposit, fuzzedUsers[i], fuzzedUsers[i]);
        }
    }

    function testFuzz_deposit_revertsWhen_zeroAmount(address from) public {
        vm.prank(from);
        vm.expectRevert(Errors.ZeroAmount.selector);
        basket.deposit(0, from);
    }

    function testFuzz_deposit_revertsWhen_notClaimingFullOutstandingDeposit(
        uint256 amount,
        uint256 issuedShares
    )
        public
    {
        testFuzz_fulfillDeposit(amount, issuedShares);
        for (uint256 i = 0; i < MAX_USERS; ++i) {
            address from = fuzzedUsers[i];
            uint256 maxDeposit = basket.maxDeposit(from);
            vm.assume(maxDeposit > 1);
            uint256 claimingAmount = bound(uint256(keccak256(abi.encode(maxDeposit))), 1, maxDeposit - 1);

            // Call deposit with partial amount
            vm.expectRevert(BasketToken.MustClaimFullAmount.selector);
            vm.prank(from);
            basket.deposit(claimingAmount, from);
        }
    }

    function testFuzz_mint(uint256 amount, uint256 issuedShares) public {
        testFuzz_fulfillDeposit(amount, issuedShares);
        for (uint256 i = 0; i < MAX_USERS; ++i) {
            address from = fuzzedUsers[i];
            uint256 userBalanceBefore = basket.balanceOf(from);
            uint256 basketBalanceBefore = basket.balanceOf(address(basket));
            uint256 maxDeposit = basket.maxDeposit(from);
            uint256 maxMint = basket.maxMint(from);

            // Call mint
            vm.prank(from);
            assertEq(basket.mint(maxMint, from), maxDeposit);

            // Check state
            assertEq(basket.balanceOf(from), userBalanceBefore + maxMint);
            assertEq(basket.balanceOf(address(basket)), basketBalanceBefore - maxMint);
            assertEq(basket.maxDeposit(from), 0);
            assertEq(basket.maxMint(from), 0);
        }
    }

    function testFuzz_mint_operator(uint256 amount, uint256 issuedShares, address operator) public {
        vm.assume(operator != address(0));
        testFuzz_fulfillDeposit(amount, issuedShares);
        for (uint256 i = 0; i < MAX_USERS; ++i) {
            address from = fuzzedUsers[i];
            uint256 userBalanceBefore = basket.balanceOf(from);
            uint256 basketBalanceBefore = basket.balanceOf(address(basket));
            uint256 maxDeposit = basket.maxDeposit(from);
            uint256 maxMint = basket.maxMint(from);

            // Set Operator
            vm.prank(from);
            basket.setOperator(operator, true);

            // Call mint
            vm.prank(operator);
            assertEq(basket.mint(maxMint, from, from), maxDeposit);

            // Check state
            assertEq(basket.balanceOf(from), userBalanceBefore + maxMint);
            assertEq(basket.balanceOf(address(basket)), basketBalanceBefore - maxMint);
            assertEq(basket.maxDeposit(from), 0);
            assertEq(basket.maxMint(from), 0);
        }
    }

    function testFuzz_mint_revertWhen_operatorNotSet(uint256 amount, uint256 issuedShares, address operator) public {
        vm.assume(operator != address(0));
        testFuzz_fulfillDeposit(amount, issuedShares);
        for (uint256 i = 0; i < MAX_USERS; ++i) {
            address from = fuzzedUsers[i];
            vm.assume(from != operator);
            uint256 maxMint = basket.maxMint(from);

            // Set Operator
            assert(!basket.isOperator(from, operator));

            // Call mint
            vm.expectRevert(BasketToken.NotAuthorizedOperator.selector);
            vm.prank(operator);
            basket.mint(maxMint, operator, from);
        }
    }

    function testFuzz_mint_revertsWhen_notClaimingFullOutstandingDeposit(
        uint256 amount,
        uint256 issuedShares,
        uint256 claimingShares
    )
        public
    {
        testFuzz_fulfillDeposit(amount, issuedShares);
        for (uint256 i = 0; i < MAX_USERS; ++i) {
            address from = fuzzedUsers[i];
            uint256 maxMint = basket.maxMint(from);
            // Ignore the cases where the user has deposited non zero amount but has zero shares
            vm.assume(maxMint > 1);
            claimingShares = bound(claimingShares, 1, maxMint - 1);

            vm.prank(from);
            vm.expectRevert(BasketToken.MustClaimFullAmount.selector);
            basket.mint(claimingShares, from, from);
        }
    }

    function testFuzz_cancelDepositRequest(uint256 amount, address from) public {
        vm.assume(from != address(basket) && from != address(basketManager) && from != address(0));
        uint256 requestId = testFuzz_requestDeposit(amount, from);
        uint256 requestAmount = basket.pendingDepositRequest(requestId, from);
        uint256 balanceBefore = dummyAsset.balanceOf(from);

        // Call cancelDepositRequest
        vm.prank(from);
        basket.cancelDepositRequest();

        // Check state
        assertEq(basket.pendingDepositRequest(requestId, from), 0);
        assertEq(dummyAsset.balanceOf(from), balanceBefore + requestAmount);
    }

    function testFuzz_cancelDepositRequest_revertsWhen_zeroPendingDeposits(address user) public {
        vm.assume(user != address(0));
        vm.prank(user);
        vm.expectRevert(BasketToken.ZeroPendingDeposits.selector);
        basket.cancelDepositRequest();
    }

    function _testFuzz_requestRedeem(
        address[MAX_USERS] memory callers,
        address[MAX_USERS] memory dests
    )
        internal
        returns (uint256 requestId)
    {
        for (uint256 i = 0; i < MAX_USERS; ++i) {
            address from = fuzzedUsers[i];
            address caller = callers[i];
            address to = dests[i];
            vm.assume(caller != address(0) && to != address(0));

            uint256 userSharesBefore = basket.balanceOf(from);
            // Ignores the cases where the user has deposited non zero amount but has zero shares
            vm.assume(userSharesBefore > 0);
            uint256 basketBalanceOfSelfBefore = basket.balanceOf(address(basket));
            uint256 pendingRedeemRequestBefore = basket.pendingRedeemRequest(basket.lastRedeemRequestId(to), to);
            uint256 totalPendingRedeemsBefore = basket.totalPendingRedemptions();
            uint256 sharesToRedeem = bound(uint256(keccak256(abi.encode(userSharesBefore))), 1, userSharesBefore);

            // Approve tokens to be used by the caller
            vm.prank(from);
            basket.approve(caller, sharesToRedeem);

            // Call requestRedeem
            vm.prank(caller);
            requestId = basket.requestRedeem(sharesToRedeem, to, from);

            // Check state
            assertEq(
                basket.pendingRedeemRequest(requestId, to),
                pendingRedeemRequestBefore + sharesToRedeem,
                "_testFuzz_requestRedeem: pendingRedeemRequest mismatch"
            );
            assertEq(
                basket.totalPendingRedemptions(),
                totalPendingRedeemsBefore + sharesToRedeem,
                "_testFuzz_requestRedeem: totalPendingRedemptions mismatch"
            );
            assertEq(
                basket.balanceOf(from),
                userSharesBefore - sharesToRedeem,
                "_testFuzz_requestRedeem: balanceOf(from) mismatch"
            );
            assertEq(
                basket.balanceOf(address(basket)),
                basketBalanceOfSelfBefore + sharesToRedeem,
                "_testFuzz_requestRedeem: balanceOf(basket) mismatch"
            );
            assertEq(basket.maxRedeem(from), 0, "_testFuzz_requestRedeem: maxRedeem mismatch");
            assertEq(basket.maxWithdraw(from), 0, "_testFuzz_requestRedeem: maxWithdraw mismatch");
        }
    }

    function _testFuzz_requestRedeem_setOperator(
        address[MAX_USERS] memory callers,
        address[MAX_USERS] memory dests
    )
        internal
    {
        for (uint256 i = 0; i < MAX_USERS; ++i) {
            address from = fuzzedUsers[i];
            address caller = callers[i];
            address to = dests[i];
            vm.assume(caller != address(0) && to != address(0));

            uint256 userSharesBefore = basket.balanceOf(from);
            // Ignores the cases where the user has deposited non zero amount but has zero shares
            vm.assume(userSharesBefore > 0);
            uint256 basketBalanceOfSelfBefore = basket.balanceOf(address(basket));
            uint256 totalPendingRedeemsBefore = basket.totalPendingRedemptions();
            uint256 sharesToRedeem = bound(uint256(keccak256(abi.encode(userSharesBefore))), 1, userSharesBefore);

            // Approve set caller as the operator
            vm.prank(from);
            basket.setOperator(caller, true);

            // Call requestRedeem
            vm.prank(caller);
            uint256 requestId = basket.requestRedeem(sharesToRedeem, to, from);

            // Check state
            assertEq(
                basket.pendingRedeemRequest(requestId, to),
                sharesToRedeem,
                "_testFuzz_requestRedeem_setOperator: pendingRedeemRequest mismatch"
            );
            assertEq(
                basket.totalPendingRedemptions(),
                totalPendingRedeemsBefore + sharesToRedeem,
                "_testFuzz_requestRedeem_setOperator: totalPendingRedemptions mismatch"
            );
            assertEq(
                basket.balanceOf(from),
                userSharesBefore - sharesToRedeem,
                "_testFuzz_requestRedeem_setOperator: balanceOf(from) mismatch"
            );
            assertEq(
                basket.balanceOf(address(basket)),
                basketBalanceOfSelfBefore + sharesToRedeem,
                "_testFuzz_requestRedeem_setOperator: balanceOf(basket) mismatch"
            );
            assertEq(basket.maxRedeem(from), 0, "_testFuzz_requestRedeem_setOperator: maxRedeem mismatch");
            assertEq(basket.maxWithdraw(from), 0, "_testFuzz_requestRedeem_setOperator: maxWithdraw mismatch");
        }
    }

    function testFuzz_requestRedeem(
        uint256 amount,
        uint256 issuedShares,
        address[MAX_USERS] memory callers,
        address[MAX_USERS] memory dests
    )
        public
        returns (uint256 requestId)
    {
        requestId = testFuzz_deposit(amount, issuedShares);
        _testFuzz_requestRedeem(callers, dests);
    }

    function testFuzz_requestRedeem(uint256 amount, uint256 issuedShares) public returns (uint256 requestId) {
        testFuzz_deposit(amount, issuedShares);
        address[MAX_USERS] memory users_;
        for (uint256 i = 0; i < MAX_USERS; ++i) {
            users_[i] = fuzzedUsers[i];
        }
        requestId = _testFuzz_requestRedeem(users_, users_);
    }

    function testFuzz_requestRedeem_passWhen_pendingRedeemRequest(uint256 amount, uint256 issuedShares) public {
        testFuzz_requestRedeem(amount, issuedShares);
        for (uint256 i = 0; i < MAX_USERS; ++i) {
            address from = fuzzedUsers[i];
            uint256 userSharesBefore = basket.balanceOf(from);
            // Ignore the cases where the user has deposited non zero amount but has zero shares
            vm.assume(userSharesBefore > 0);
            uint256 userPendingRequest = basket.pendingRedeemRequest(basket.lastRedeemRequestId(from), from);
            uint256 totalPendingRedeems = basket.totalPendingRedemptions();
            uint256 sharesToRequest = bound(uint256(keccak256(abi.encode(userSharesBefore))), 1, userSharesBefore);

            // Call requestRedeem
            vm.prank(from);
            uint256 requestId = basket.requestRedeem(sharesToRequest, from, from);

            // Check state
            assertEq(basket.pendingRedeemRequest(requestId, from), userPendingRequest + sharesToRequest);
            assertEq(basket.totalPendingRedemptions(), totalPendingRedeems + sharesToRequest);
        }
    }

    function test_requestRedeem_revertWhen_zeroAmount() public {
        vm.prank(alice);
        vm.expectRevert(Errors.ZeroAmount.selector);
        basket.requestRedeem(0, alice, alice);
    }

    function test_requestRedeem_revertWhen_assetPaused() public {
        uint256 amount = 1e18;
        dummyAsset.mint(alice, amount);

        vm.mockCall(
            address(assetRegistry), abi.encodeCall(AssetRegistry.hasPausedAssets, basket.bitFlag()), abi.encode(true)
        );

        vm.startPrank(alice);
        dummyAsset.approve(address(basket), amount);
        vm.expectRevert(BasketToken.AssetPaused.selector);
        basket.requestRedeem(amount, alice, alice);
    }

    function test_requestRedeem_revertWhen_assetDisabled() public {
        uint256 amount = 1e18;
        dummyAsset.mint(alice, amount);

        vm.mockCall(
            address(assetRegistry), abi.encodeCall(AssetRegistry.hasPausedAssets, basket.bitFlag()), abi.encode(true)
        );

        vm.startPrank(alice);
        dummyAsset.approve(address(basket), amount);
        vm.expectRevert(BasketToken.AssetPaused.selector);
        basket.requestRedeem(amount, alice, alice);
    }

    function test_requestRedeem_revertWhen_MustClaimOutstandingRedeem_Claimable() public {
        uint256 amount = 1e18;
        uint256 issuedShares = 1e17;
        dummyAsset.mint(alice, amount);
        vm.startPrank(alice);
        dummyAsset.approve(address(basket), amount);
        basket.requestDeposit(amount, alice, alice);
        vm.stopPrank();
        vm.startPrank(address(basketManager));
        basket.prepareForRebalance(0, feeCollector);
        basket.fulfillDeposit(issuedShares);
        vm.stopPrank();
        vm.startPrank(alice);
        basket.deposit(amount, alice);
        basket.requestRedeem(issuedShares / 2, alice, alice);
        vm.stopPrank();
        vm.startPrank(address(basketManager));
        basket.prepareForRebalance(0, feeCollector);
        basket.fulfillRedeem(amount);
        vm.expectRevert(BasketToken.MustClaimOutstandingRedeem.selector);
        vm.stopPrank();
        vm.prank(alice);
        basket.requestRedeem(issuedShares / 2, alice, alice);
    }

    function testFuzz_requestRedeem_revertWhen_MustClaimOutstandingRedeem_Pending(
        uint256 amount,
        uint256 issuedShares
    )
        public
    {
        uint256 requestId = testFuzz_requestRedeem(amount, issuedShares);

        uint256[] memory redeemShares = new uint256[](MAX_USERS);
        for (uint256 i = 0; i < MAX_USERS; ++i) {
            redeemShares[i] = basket.pendingRedeemRequest(requestId, fuzzedUsers[i]);
        }

        uint256 totalPendingRedeemsBefore = basket.totalPendingRedemptions();
        assertGt(totalPendingRedeemsBefore, 0, "Total pending redeems should be greater than 0 for this test");

        // Call prepareForRebalance and fulfillRedeem
        vm.prank(address(basketManager));
        basket.prepareForRebalance(0, feeCollector);

        for (uint256 i = 0; i < MAX_USERS; ++i) {
            address caller = fuzzedUsers[i];
            vm.prank(caller);
            vm.expectRevert(BasketToken.MustClaimOutstandingRedeem.selector);
            basket.requestRedeem(redeemShares[i], caller, caller);
        }
    }

    function testFuzz_fulfillRedeem(
        uint256 amount,
        uint256 issuedShares,
        uint256 fulfillAmount
    )
        public
        returns (uint256 requestId)
    {
        requestId = testFuzz_requestRedeem(amount, issuedShares);

        uint256[] memory redeemShares = new uint256[](MAX_USERS);
        for (uint256 i = 0; i < MAX_USERS; ++i) {
            redeemShares[i] = basket.pendingRedeemRequest(requestId, fuzzedUsers[i]);
        }

        uint256 totalPendingRedeemsBefore = basket.totalPendingRedemptions();
        assertGt(totalPendingRedeemsBefore, 0, "Total pending redeems should be greater than 0 for this test");
        uint256 basketManagerBalanceBefore = dummyAsset.balanceOf(address(basketManager));
        fulfillAmount = bound(fulfillAmount, 1, basketManagerBalanceBefore);
        uint256 basketBalanceBefore = basket.balanceOf(address(basket));

        // Call prepareForRebalance and fulfillRedeem
        vm.startPrank(address(basketManager));
        basket.prepareForRebalance(0, feeCollector);
        basket.fulfillRedeem(fulfillAmount);

        vm.stopPrank();

        // Check state
        assertEq(
            dummyAsset.balanceOf(address(basketManager)),
            basketManagerBalanceBefore - fulfillAmount,
            "testFuzz_fulfillRedeem: Incorrect basketManager balance"
        );
        assertEq(
            basket.balanceOf(address(basket)),
            basketBalanceBefore - totalPendingRedeemsBefore,
            "testFuzz_fulfillRedeem: Incorrect basket balance"
        );
        assertEq(basket.totalPendingRedemptions(), 0, "testFuzz_fulfillRedeem: Incorrect total pending redemptions");
        for (uint256 i = 0; i < MAX_USERS; ++i) {
            // A redeem request will return a pending balance until claimed
            assertEq(
                basket.pendingRedeemRequest(requestId, fuzzedUsers[i]),
                0,
                "testFuzz_fulfillRedeem: Incorrect pending redeem request"
            );
            assertEq(
                basket.claimableRedeemRequest(requestId, fuzzedUsers[i]),
                redeemShares[i],
                "testFuzz_fulfillRedeem: Incorrect claimable redeem request"
            );
            if (redeemShares[i] != 0) {
                assertEq(
                    basket.maxRedeem(fuzzedUsers[i]), redeemShares[i], "testFuzz_fulfillRedeem: Incorrect max redeem"
                );
                assertEq(
                    basket.maxWithdraw(fuzzedUsers[i]),
                    redeemShares[i].fullMulDiv(fulfillAmount, totalPendingRedeemsBefore),
                    "testFuzz_fulfillRedeem: Incorrect max withdraw"
                );
            }
        }
    }

    function testFuzz_fulfillRedeem_revertsWhen_CannotFulfillWithZeroAssets(
        uint256 amount,
        uint256 issuedShares
    )
        public
    {
        testFuzz_requestRedeem(amount, issuedShares);
        // Call prepareForRebalance and fulfillRedeem with zero amount
        vm.startPrank(address(basketManager));
        basket.prepareForRebalance(0, feeCollector);
        vm.expectRevert(BasketToken.CannotFulfillWithZeroAssets.selector);
        basket.fulfillRedeem(0);
    }

    function testFuzz_fulfillRedeem_revertsWhen_ZeroPendingRedeems(uint256 assets) public {
        assertEq(basket.totalPendingRedemptions(), 0);
        vm.startPrank(address(basketManager));
        vm.expectRevert(BasketToken.ZeroPendingRedeems.selector);
        basket.fulfillRedeem(assets);
    }

    function testFuzz_prepareForRebalance(
        uint256 totalAmount,
        uint256 issuedShares
    )
        public
        returns (uint256 requestId)
    {
        requestId = testFuzz_requestRedeem(totalAmount, issuedShares);

        uint256 pendingSharesBefore = basket.totalPendingRedemptions();
        assertGt(pendingSharesBefore, 0, "Total pending redeems should be greater than 0 for this test");

        uint256[] memory pendingShares = new uint256[](MAX_USERS);
        for (uint256 i = 0; i < MAX_USERS; ++i) {
            address from = fuzzedUsers[i];
            pendingShares[i] = basket.pendingRedeemRequest(requestId, from);
            if (basket.maxWithdraw(from) > 0) {
                assertGt(
                    pendingShares[i], 0, "testFuzz_prepareForRebalance: Pending redeem request should be greater than 0"
                );
            }
        }

        // Call prepareForRebalance
        vm.prank(address(basketManager));
        (, uint256 preFulfilledShares) = basket.prepareForRebalance(0, feeCollector);

        // Check state
        assertEq(
            preFulfilledShares,
            pendingSharesBefore,
            "testFuzz_prepareForRebalance: PreFulfilled shares should be equal to total pending redeems"
        );
        assertEq(
            basket.totalPendingRedemptions(),
            0,
            "testFuzz_prepareForRebalance: Total pending redeems should be 0 after prepareForRebalance"
        );
        for (uint256 i = 0; i < MAX_USERS; ++i) {
            assertEq(
                basket.pendingRedeemRequest(requestId, fuzzedUsers[i]),
                pendingShares[i],
                "testFuzz_prepareForRebalance: Pending redeem requests should be >0 after prepareForRebalance"
            );
        }
    }

    function test_prepareForRebalance_returnsZeroWhen_ZeroPendingRedeems() public {
        assertEq(basket.totalPendingRedemptions(), 0);
        vm.prank(address(basketManager));
        (, uint256 pendingShares) = basket.prepareForRebalance(0, feeCollector);
        assertEq(pendingShares, 0);
    }

    function test_prepareForRebalance_doesNotAdvanceRedeemRequestId_whenZero() public {
        assertEq(basket.totalPendingRedemptions(), 0);
        uint256 nextRedeemRequestId = basket.nextRedeemRequestId();
        vm.prank(address(basketManager));
        basket.prepareForRebalance(0, feeCollector);
        assertEq(basket.nextRedeemRequestId(), nextRedeemRequestId);
    }

    function test_prepareForRebalance_doesNotAdvanceDepositRequestId_whenNonZero() public {
        assertEq(basket.totalPendingDeposits(), 0);
        uint256 nextDepositRequestId = basket.nextDepositRequestId();
        vm.prank(address(basketManager));
        basket.prepareForRebalance(0, feeCollector);
        assertEq(basket.nextDepositRequestId(), nextDepositRequestId);
    }

    function testFuzz_prepareForRebalance_revertsWhen_PreviousDepositRequestNotFulfilled(
        uint256 amount,
        address from
    )
        public
    {
        testFuzz_requestDeposit(amount, from);
        vm.startPrank(address(basketManager));
        basket.prepareForRebalance(0, feeCollector);
        vm.expectRevert(BasketToken.PreviousDepositRequestNotFulfilled.selector);
        basket.prepareForRebalance(0, feeCollector);
    }

    function test_prepareForRebalance_revertsWhen_PreviousRedeemRequestNotFulfilled(
        uint256 amount,
        uint256 issuedShares,
        address[MAX_USERS] calldata callers,
        address[MAX_USERS] calldata dests
    )
        public
    {
        testFuzz_requestRedeem(amount, issuedShares, callers, dests);
        vm.startPrank(address(basketManager));
        basket.prepareForRebalance(0, feeCollector);
        vm.expectRevert(BasketToken.PreviousRedeemRequestNotFulfilled.selector);
        basket.prepareForRebalance(0, feeCollector);
    }

    function testFuzz_fulfillRedeem_revertsWhen_RedeemRequestAlreadyFulfilled(
        uint256 amount,
        uint256 issuedShares,
        uint256 redeemAmount,
        uint256 fulfillAmount
    )
        public
    {
        vm.assume(fulfillAmount > 0);
        testFuzz_redeem(amount, issuedShares, redeemAmount);
        vm.startPrank(address(basketManager));
        vm.expectRevert(BasketToken.RedeemRequestAlreadyFulfilled.selector);
        basket.fulfillRedeem(fulfillAmount);
        vm.stopPrank();
    }

    function testFuzz_requestRedeem_passWhen_afterRedeem(
        uint256 totalDepositAmount,
        uint256 issuedShares,
        uint256 redeemAmount
    )
        public
    {
        uint256 requestId = testFuzz_redeem(totalDepositAmount, issuedShares, redeemAmount);
        for (uint256 i = 0; i < MAX_USERS; ++i) {
            address from = fuzzedUsers[i];
            uint256 userPendingRequest = basket.pendingRedeemRequest(requestId, from);
            uint256 totalPendingRedeems = basket.totalPendingRedemptions();
            uint256 userBalanceBefore = basket.balanceOf(from);
            // Ignore the cases where the user has deposited non zero amount but has zero shares
            vm.assume(userBalanceBefore > 0);

            uint256 sharesToRequest = bound(uint256(keccak256(abi.encode(userBalanceBefore))), 1, userBalanceBefore);

            // Call requestRedeem
            vm.prank(from);
            uint256 newRequestId = basket.requestRedeem(sharesToRequest, from, from);

            // Check state
            assertEq(basket.pendingRedeemRequest(newRequestId, from), userPendingRequest + sharesToRequest);
            assertEq(basket.totalPendingRedemptions(), totalPendingRedeems + sharesToRequest);
        }
    }

    function testFuzz_requestRedeem_passWhen_afterWithdraw(
        uint256 totalDepositAmount,
        uint256 issuedShares,
        uint256 redeemAmount
    )
        public
    {
        testFuzz_withdraw(totalDepositAmount, issuedShares, redeemAmount);
        for (uint256 i = 0; i < MAX_USERS; ++i) {
            address from = fuzzedUsers[i];
            uint256 userPendingRequest = basket.pendingRedeemRequest(basket.lastRedeemRequestId(from), from);
            uint256 totalPendingRedeems = basket.totalPendingRedemptions();
            uint256 userBalanceBefore = basket.balanceOf(from);
            // Ignore the cases where the user has deposited non zero amount but has zero shares
            vm.assume(userBalanceBefore > 0);

            uint256 sharesToRequest = bound(uint256(keccak256(abi.encode(userBalanceBefore))), 1, userBalanceBefore);

            // Call requestRedeem
            vm.prank(from);
            basket.requestRedeem(sharesToRequest, from, from);

            // Check state
            assertEq(
                basket.pendingRedeemRequest(basket.lastRedeemRequestId(from), from),
                userPendingRequest + sharesToRequest,
                "testFuzz_requestRedeem_passWhen_afterWithdraw: pendingRedeemRequest mismatch"
            );
            assertEq(
                basket.totalPendingRedemptions(),
                totalPendingRedeems + sharesToRequest,
                "testFuzz_requestRedeem_passWhen_afterWithdraw: totalPendingRedemptions mismatch"
            );
        }
    }

    function testFuzz_fulfillRedeem_revertsWhen_NotBasketManager(address from) public {
        vm.assume(from != basket.basketManager());
        vm.expectRevert(BasketToken.NotBasketManager.selector);
        vm.prank(from);
        basket.fulfillRedeem(1e18);
    }

    function testFuzz_prepareForRebalance_revertsWhen_NotBasketManager(address from) public {
        vm.assume(from != basket.basketManager());
        vm.expectRevert(BasketToken.NotBasketManager.selector);
        vm.prank(from);
        basket.prepareForRebalance(0, feeCollector);
    }

    function testFuzz_redeem(
        uint256 totalDepositAmount,
        uint256 issuedShares,
        uint256 redeemAmount
    )
        public
        returns (uint256 requestId)
    {
        requestId = testFuzz_fulfillRedeem(totalDepositAmount, issuedShares, redeemAmount);
        for (uint256 i = 0; i < MAX_USERS; ++i) {
            address from = fuzzedUsers[i];
            uint256 userBalanceBefore = dummyAsset.balanceOf(from);
            uint256 maxRedeem = basket.maxRedeem(from);
            uint256 maxWithdraw = basket.maxWithdraw(from);
            // Previous tests ensures that the user has non zero shares to redeem
            assertGt(maxRedeem, 0, "Max redeem should be greater than 0 for this test");

            // Call redeem
            vm.prank(from);
            uint256 assets = basket.redeem(maxRedeem, from, from);

            // Check state
            assertEq(assets, maxWithdraw);
            assertEq(dummyAsset.balanceOf(from), userBalanceBefore + maxWithdraw);
            assertEq(basket.maxRedeem(from), 0);
            assertEq(basket.maxWithdraw(from), 0);
        }
    }

    function testFuzz_redeem_operator(
        uint256 totalDepositAmount,
        uint256 issuedShares,
        uint256 redeemAmount,
        address operator
    )
        public
    {
        vm.assume(operator != address(0));
        testFuzz_fulfillRedeem(totalDepositAmount, issuedShares, redeemAmount);
        for (uint256 i = 0; i < MAX_USERS; ++i) {
            address from = fuzzedUsers[i];
            uint256 userBalanceBefore = dummyAsset.balanceOf(from);
            uint256 maxRedeem = basket.maxRedeem(from);
            uint256 maxWithdraw = basket.maxWithdraw(from);
            // Previous tests ensures that the user has non zero shares to redeem
            assertGt(maxRedeem, 0, "Max redeem should be greater than 0 for this test");

            // Set operator
            vm.prank(from);
            basket.setOperator(operator, true);

            // Call redeem
            vm.prank(operator);
            uint256 assets = basket.redeem(maxRedeem, from, from);

            // Check state
            assertEq(assets, maxWithdraw);
            assertEq(dummyAsset.balanceOf(from), userBalanceBefore + maxWithdraw);
            assertEq(basket.maxRedeem(from), 0);
            assertEq(basket.maxWithdraw(from), 0);
        }
    }

    function testFuzz_redeem_revertWhen_operatorNotSet(
        uint256 totalDepositAmount,
        uint256 issuedShares,
        uint256 redeemAmount,
        address operator
    )
        public
    {
        vm.assume(operator != address(0));
        testFuzz_fulfillRedeem(totalDepositAmount, issuedShares, redeemAmount);
        for (uint256 i = 0; i < MAX_USERS; ++i) {
            address from = fuzzedUsers[i];
            uint256 maxRedeem = basket.maxRedeem(from);
            // Previous tests ensures that the user has non zero shares to redeem
            assertGt(maxRedeem, 0, "Max redeem should be greater than 0 for this test");

            // Set operator
            assert(!basket.isOperator(from, operator));

            // Call redeem
            vm.expectRevert(BasketToken.NotAuthorizedOperator.selector);
            vm.prank(operator);
            basket.redeem(maxRedeem, operator, from);
        }
    }

    function test_redeem_revertsWhen_zeroAmount() public {
        vm.expectRevert(Errors.ZeroAmount.selector);
        vm.prank(alice);
        basket.redeem(0, alice, alice);
    }

    function testFuzz_redeem_revertsWhen_notClaimingFullOutstandingRedeem(
        uint256 totalDepositAmount,
        uint256 issuedShares,
        uint256 redeemAmount
    )
        public
    {
        testFuzz_fulfillRedeem(totalDepositAmount, issuedShares, redeemAmount);
        for (uint256 i = 0; i < MAX_USERS; ++i) {
            address from = fuzzedUsers[i];
            uint256 maxRedeem = basket.maxRedeem(from);
            // Ignore the cases where the user has redeemed non zero shares but will receive zero assets
            vm.assume(maxRedeem > 1);
            uint256 sharesToRedeem = bound(uint256(keccak256(abi.encode(maxRedeem))), 1, maxRedeem - 1);

            // Call redeem
            vm.expectRevert(BasketToken.MustClaimFullAmount.selector);
            vm.prank(from);
            basket.redeem(sharesToRedeem, from, from);
        }
    }

    function testFuzz_withdraw(uint256 totalDepositAmount, uint256 issuedShares, uint256 redeemAmount) public {
        testFuzz_fulfillRedeem(totalDepositAmount, issuedShares, redeemAmount);
        for (uint256 i = 0; i < MAX_USERS; ++i) {
            address from = fuzzedUsers[i];
            uint256 userBalanceBefore = dummyAsset.balanceOf(from);
            uint256 maxRedeem = basket.maxRedeem(from);
            uint256 maxWithdraw = basket.maxWithdraw(from);

            // Call redeem
            vm.prank(from);
            uint256 withdrawnAssets = basket.withdraw(maxWithdraw, from, from);
            assertEq(withdrawnAssets, maxRedeem, "testFuzz_withdraw: Incorrect withdrawn assets");

            // Check state
            assertEq(
                dummyAsset.balanceOf(from), userBalanceBefore + maxWithdraw, "testFuzz_withdraw: Incorrect user balance"
            );
            assertEq(basket.maxRedeem(from), 0, "testFuzz_withdraw: Incorrect max redeem");
            assertEq(basket.maxWithdraw(from), 0, "testFuzz_withdraw: Incorrect max withdraw");
        }
    }

    function testFuzz_withdraw_operator(
        uint256 totalDepositAmount,
        uint256 issuedShares,
        uint256 redeemAmount,
        address operator
    )
        public
    {
        vm.assume(operator != address(0));
        testFuzz_fulfillRedeem(totalDepositAmount, issuedShares, redeemAmount);
        for (uint256 i = 0; i < MAX_USERS; ++i) {
            address from = fuzzedUsers[i];
            uint256 userBalanceBefore = dummyAsset.balanceOf(from);
            uint256 maxRedeem = basket.maxRedeem(from);
            uint256 maxWithdraw = basket.maxWithdraw(from);

            // Set operator
            vm.prank(from);
            basket.setOperator(operator, true);

            // Call redeem
            vm.prank(operator);
            assertEq(basket.withdraw(maxWithdraw, from, from), maxRedeem);

            // Check state
            assertEq(dummyAsset.balanceOf(from), userBalanceBefore + maxWithdraw);
            assertEq(basket.maxRedeem(from), 0);
            assertEq(basket.maxWithdraw(from), 0);
        }
    }

    function testFuzz_withdraw_revertWhen_operatorNotSet(
        uint256 totalDepositAmount,
        uint256 issuedShares,
        uint256 redeemAmount,
        address operator
    )
        public
    {
        vm.assume(operator != address(0));
        testFuzz_fulfillRedeem(totalDepositAmount, issuedShares, redeemAmount);
        for (uint256 i = 0; i < MAX_USERS; ++i) {
            address from = fuzzedUsers[i];
            uint256 maxWithdraw = basket.maxWithdraw(from);

            assert(!basket.isOperator(fuzzedUsers[i], operator));

            // Call redeem
            vm.expectRevert(BasketToken.NotAuthorizedOperator.selector);
            vm.prank(operator);
            basket.withdraw(maxWithdraw, operator, from);
        }
    }

    function testFuzz_withdraw_revertsWhen_notClaimingFullOutstandingRedeem(
        uint256 totalDepositAmount,
        uint256 issuedShares,
        uint256 redeemAmount
    )
        public
    {
        testFuzz_fulfillRedeem(totalDepositAmount, issuedShares, redeemAmount);
        for (uint256 i = 0; i < MAX_USERS; ++i) {
            address from = fuzzedUsers[i];
            uint256 maxWithdraw = basket.maxWithdraw(from);
            // Ignore the cases where the user has redeemed non zero shares but will receive zero assets
            vm.assume(maxWithdraw > 1);
            uint256 sharesToWithdraw = bound(uint256(keccak256(abi.encode(maxWithdraw))), 1, maxWithdraw - 1);

            // Call withdraw with partial amount
            vm.expectRevert(BasketToken.MustClaimFullAmount.selector);
            vm.prank(from);
            basket.withdraw(sharesToWithdraw, from, from);
        }
    }

    function testFuzz_cancelRedeemRequest(uint256 totalDepositAmount, uint256 issuedShares) public {
        testFuzz_requestRedeem(totalDepositAmount, issuedShares);
        for (uint256 i = 0; i < MAX_USERS; ++i) {
            address user = fuzzedUsers[i];
            uint256 pendingRedeem = basket.pendingRedeemRequest(basket.lastRedeemRequestId(user), user);
            uint256 balanceBefore = basket.balanceOf(user);
            uint256 totalPendingRedeemsBefore = basket.totalPendingRedemptions();

            // Call cancelRedeemRequest
            vm.prank(user);
            basket.cancelRedeemRequest();

            // Check state
            assertEq(basket.pendingRedeemRequest(basket.lastRedeemRequestId(user), user), 0);
            assertEq(basket.balanceOf(user), balanceBefore + pendingRedeem);
            assertEq(basket.totalPendingRedemptions(), totalPendingRedeemsBefore - pendingRedeem);
        }
    }

    function test_cancelRedeemRequest_revertsWhen_zeroPendingRedeems() public {
        vm.expectRevert(BasketToken.ZeroPendingRedeems.selector);
        vm.prank(alice);
        basket.cancelRedeemRequest();
    }

    function testFuzz_cancelRedeemRequest_revertsWhen_prepareForRebalance_hasBeenCalled(
        uint256 totalDepositAmount,
        uint256 issuedShares
    )
        public
    {
        testFuzz_prepareForRebalance(totalDepositAmount, issuedShares);
        for (uint256 i = 0; i < MAX_USERS; ++i) {
            vm.expectRevert(BasketToken.ZeroPendingRedeems.selector);
            vm.prank(fuzzedUsers[i]);
            basket.cancelRedeemRequest();
        }
    }

    function testFuzz_fallbackRedeemTrigger(uint256 totalDepositAmount, uint256 issuedShares) public {
        uint256 requestId = testFuzz_prepareForRebalance(totalDepositAmount, issuedShares);
        // Call fallbackRedeemTrigger
        vm.prank(address(basketManager));
        basket.fallbackRedeemTrigger();
        assertEq(basket.fallbackTriggered(requestId), true, "Fallback status of requestId should be changed to true");
    }

    function test_fallbackRedeemTrigger_revertsWhen_ZeroPendingRedeems() public {
        vm.expectRevert(BasketToken.ZeroPendingRedeems.selector);
        vm.prank(address(basketManager));
        basket.fallbackRedeemTrigger();
    }

    function testFuzz_fallbackRedeemTrigger_revertsWhen_NotBasketManager(address caller) public {
        vm.assume(caller != basket.basketManager());
        vm.expectRevert(BasketToken.NotBasketManager.selector);
        vm.prank(caller);
        basket.fallbackRedeemTrigger();
    }

    function testFuzz_fallbackRedeemTrigger_revertsWhen_RedeemRequestAlreadyFallbacked(
        uint256 totalDepositAmount,
        uint256 issuedShares
    )
        public
    {
        testFuzz_prepareForRebalance(totalDepositAmount, issuedShares);
        // Call fallbackRedeemTrigger
        vm.startPrank(address(basketManager));
        basket.fallbackRedeemTrigger();
        vm.expectRevert(BasketToken.RedeemRequestAlreadyFallbacked.selector);
        basket.fallbackRedeemTrigger();
    }

    function test_fallbackRedeemTrigger_revertsWhen_RedeemRequestAlreadyFulfilled(
        uint256 amount,
        uint256 issuedShares,
        uint256 fulfillAmount
    )
        public
    {
        testFuzz_fulfillRedeem(amount, issuedShares, fulfillAmount);
        // Call fallbackRedeemTrigger
        vm.startPrank(address(basketManager));
        vm.expectRevert(BasketToken.RedeemRequestAlreadyFulfilled.selector);
        basket.fallbackRedeemTrigger();
    }

    function testFuzz_claimFallbackShares(uint256 totalDepositAmount, uint256 issuedShares) public {
        testFuzz_fallbackRedeemTrigger(totalDepositAmount, issuedShares);

        for (uint256 i = 0; i < MAX_USERS; ++i) {
            address user = fuzzedUsers[i];
            uint256 userBalanceBefore = basket.balanceOf(user);
            uint256 basketBalanceBefore = basket.balanceOf(address(basket));
            uint256 userClaimable = basket.claimableFallbackShares(user);
            assertEq(
                basket.pendingRedeemRequest(basket.lastRedeemRequestId(user), user),
                0,
                "testFuzz_claimFallbackShares: Pending redeem request should be zero"
            );
            assertEq(
                basket.claimableRedeemRequest(basket.lastRedeemRequestId(user), user),
                0,
                "testFuzz_claimFallbackShares: Claimable redeem request should be zero"
            );
            assertGt(
                userClaimable, 0, "testFuzz_claimFallbackShares: Claimable fallback shares should be greater than 0"
            );

            // Claim fallback shares
            vm.prank(user);
            assertEq(
                basket.claimFallbackShares(),
                userClaimable,
                "testFuzz_claimFallbackShares: Claimed shares should be equal to claimable shares"
            );

            // Check state
            assertEq(
                basket.balanceOf(user),
                userBalanceBefore + userClaimable,
                "testFuzz_claimFallbackShares: User balance should increase by claimable shares"
            );
            assertEq(
                basket.balanceOf(address(basket)),
                basketBalanceBefore - userClaimable,
                "testFuzz_claimFallbackShares: Basket balance should decrease by claimable shares"
            );
            assertEq(
                basket.claimableFallbackShares(user),
                0,
                "testFuzz_claimFallbackShares: Claimable fallback shares should be 0 after claim"
            );
            assertEq(
                basket.pendingRedeemRequest(basket.lastRedeemRequestId(user), user),
                0,
                "testFuzz_claimFallbackShares: Pending redeem request should be 0 after claim"
            );
        }
    }

    function testFuzz_claimFallbackShares_revertsWhen_fallbackNotTriggered(
        uint256 totalDepositAmount,
        uint256 issuedShares
    )
        public
    {
        testFuzz_prepareForRebalance(totalDepositAmount, issuedShares);
        // fallbackRedeemTrigger not called
        for (uint256 i = 0; i < MAX_USERS; ++i) {
            address user = fuzzedUsers[i];

            // Try calling claim fallback shares
            vm.expectRevert(abi.encodeWithSelector(BasketToken.ZeroClaimableFallbackShares.selector));
            vm.prank(user);
            basket.claimFallbackShares();
        }
    }

    function test_claimFallbackShares_revertsWhen_fallbackNotTriggered() public {
        uint256 amount = 1e18;
        uint256 issuedShares = 1e17;
        dummyAsset.mint(alice, amount);
        vm.startPrank(alice);
        dummyAsset.approve(address(basket), amount);
        basket.requestDeposit(amount, alice, alice);
        vm.stopPrank();
        vm.startPrank(address(basketManager));
        basket.prepareForRebalance(0, feeCollector);
        basket.fulfillDeposit(issuedShares);
        vm.stopPrank();
        vm.startPrank(alice);
        basket.deposit(amount, alice);
        basket.requestRedeem(issuedShares, alice, alice);
        vm.expectRevert(abi.encodeWithSelector(BasketToken.ZeroClaimableFallbackShares.selector));
        basket.claimFallbackShares();
        vm.stopPrank();
        vm.prank(address(basketManager));
        basket.prepareForRebalance(0, feeCollector);
        vm.expectRevert(abi.encodeWithSelector(BasketToken.ZeroClaimableFallbackShares.selector));
        vm.prank(alice);
        basket.claimFallbackShares();
        vm.prank(address(basketManager));
        basket.fulfillRedeem(amount);
        vm.expectRevert(abi.encodeWithSelector(BasketToken.ZeroClaimableFallbackShares.selector));
        vm.prank(alice);
        basket.claimFallbackShares();
    }

    function testFuzz_cancelRedeemRequest_revertsWhen_fallbackTriggered(
        uint256 totalDepositAmount,
        uint256 issuedShares
    )
        public
    {
        testFuzz_fallbackRedeemTrigger(totalDepositAmount, issuedShares);
        for (uint256 i = 0; i < MAX_USERS; ++i) {
            address user = fuzzedUsers[i];
            vm.expectRevert(abi.encodeWithSelector(BasketToken.ZeroPendingRedeems.selector));
            vm.prank(user);
            basket.cancelRedeemRequest();
        }
    }

    function testFuzz_redeem_revertsWhen_fallbackTriggered(
        uint256 totalDepositAmount,
        uint256 issuedShares,
        uint256 sharesToRedeem
    )
        public
    {
        vm.assume(sharesToRedeem != 0);
        testFuzz_fallbackRedeemTrigger(totalDepositAmount, issuedShares);

        for (uint256 i = 0; i < MAX_USERS; ++i) {
            address user = fuzzedUsers[i];
            if (basket.maxWithdraw(user) == 0) {
                continue;
            }
            // Call redeem
            vm.expectRevert(abi.encodeWithSelector(BasketToken.MustClaimFullAmount.selector));
            vm.prank(user);
            basket.redeem(sharesToRedeem, user, user);
        }
    }

    function testFuzz_previewDeposit_reverts(uint256 n) public {
        vm.expectRevert();
        basket.previewDeposit(n);
    }

    function testFuzz_previewMint_reverts(uint256 n) public {
        vm.expectRevert();
        basket.previewMint(n);
    }

    function testFuzz_previewWithdraw_reverts(uint256 assets) public {
        vm.expectRevert();
        basket.previewWithdraw(assets);
    }

    function testaFuzz_previewRedeem_reverts(uint256 shares) public {
        vm.expectRevert();
        basket.previewRedeem(shares);
    }

    function testFuzz_proRataRedeem(uint256 totalDepositAmount, uint256 issuedShares, address to) public {
        vm.assume(to != address(0));
        testFuzz_deposit(totalDepositAmount, issuedShares);

        for (uint256 i = 0; i < MAX_USERS; ++i) {
            address from = fuzzedUsers[i];
            uint256 userShares = basket.balanceOf(from);
            // Ignore the cases where the user has deposited non zero amount but has zero shares
            vm.assume(userShares > 0);
            uint256 sharesToRedeem = bound(uint256(keccak256(abi.encode(userShares))), 1, userShares);

            // Mock proRataRedeem
            uint256 totalSupply = basket.totalSupply();
            vm.mockCall(
                address(basketManager),
                abi.encodeWithSelector(BasketManager.proRataRedeem.selector, totalSupply, sharesToRedeem, to),
                abi.encode(0)
            );
            vm.mockCall(
                address(basketManager),
                abi.encodeWithSelector(BasketManager.managementFee.selector, address(basket)),
                abi.encode(0)
            );
            vm.mockCall(
                address(basketManager),
                abi.encodeWithSelector(BasketManager.feeCollector.selector),
                abi.encode(feeCollector)
            );

            // Call proRataRedeem
            vm.prank(from);
            vm.expectCall(
                address(basketManager),
                abi.encodeWithSelector(BasketManager.proRataRedeem.selector, totalSupply, sharesToRedeem, to)
            );
            basket.proRataRedeem(sharesToRedeem, to, from);

            // Check state
            assertEq(basket.balanceOf(from), userShares - sharesToRedeem);
            assertEq(basket.totalSupply(), totalSupply - sharesToRedeem);
        }
    }

    function testFuzz_proRataRedeem_passWhen_withApproval(
        uint256 totalDepositAmount,
        uint256 issuedShares,
        address caller,
        address to
    )
        public
    {
        vm.assume(caller != address(0) && to != address(0));
        testFuzz_deposit(totalDepositAmount, issuedShares);
        for (uint256 i = 0; i < MAX_USERS; ++i) {
            address from = fuzzedUsers[i];
            uint256 userShares = basket.balanceOf(from);
            // Ignore the cases where the user has deposited non zero amount but has zero shares
            vm.assume(userShares > 0);
            uint256 sharesToRedeem = bound(uint256(keccak256(abi.encode(userShares))), 1, userShares);

            // Approve token spend
            vm.prank(from);
            basket.approve(caller, sharesToRedeem);

            // Mock proRataRedeem
            uint256 totalSupply = basket.totalSupply();
            vm.mockCall(
                address(basketManager),
                abi.encodeWithSelector(BasketManager.proRataRedeem.selector, totalSupply, sharesToRedeem, to),
                abi.encode(0)
            );
            vm.mockCall(
                address(basketManager),
                abi.encodeWithSelector(BasketManager.managementFee.selector, address(basket)),
                abi.encode(0)
            );
            vm.mockCall(
                address(basketManager),
                abi.encodeWithSelector(BasketManager.feeCollector.selector),
                abi.encode(feeCollector)
            );

            // Call proRataRedeem
            vm.prank(caller);
            vm.expectCall(
                address(basketManager),
                abi.encodeWithSelector(BasketManager.proRataRedeem.selector, totalSupply, sharesToRedeem, to)
            );
            basket.proRataRedeem(sharesToRedeem, to, from);

            // Check state
            assertEq(basket.balanceOf(from), userShares - sharesToRedeem);
            assertEq(basket.totalSupply(), totalSupply - sharesToRedeem);
        }
    }

    function testFuzz_proRataRedeem_revertWhen_ERC20InsufficientAllowance(
        uint256 totalDepositAmount,
        uint256 issuedShares,
        address caller,
        address to
    )
        public
    {
        vm.assume(caller != address(0) && to != address(0));
        testFuzz_deposit(totalDepositAmount, issuedShares);
        for (uint256 i = 0; i < MAX_USERS; ++i) {
            address from = fuzzedUsers[i];
            vm.assume(from != to);
            vm.assume(caller != from);
            uint256 userShares = basket.balanceOf(from);
            // Ignore the cases where the user has deposited non zero amount but has zero shares
            vm.assume(userShares > 0);
            uint256 sharesToRedeem = bound(uint256(keccak256(abi.encode(userShares))), 1, userShares);
            uint256 approveAmount = bound(uint256(keccak256(abi.encode(sharesToRedeem))), 0, sharesToRedeem - 1);

            // Approve token spend
            vm.prank(from);
            basket.approve(caller, approveAmount);

            // Mock proRataRedeem
            vm.mockCall(
                address(basketManager),
                abi.encodeWithSelector(BasketManager.managementFee.selector, address(basket)),
                abi.encode(0)
            );
            vm.mockCall(
                address(basketManager),
                abi.encodeWithSelector(BasketManager.feeCollector.selector),
                abi.encode(feeCollector)
            );

            // Call proRataRedeem
            vm.prank(caller);
            vm.expectRevert(
                abi.encodeWithSelector(
                    IERC20Errors.ERC20InsufficientAllowance.selector, caller, approveAmount, sharesToRedeem
                )
            );
            basket.proRataRedeem(sharesToRedeem, to, from);
        }
    }

    function test_supportsInterface() public {
        assert(basket.supportsInterface(type(IERC165).interfaceId));
        assert(basket.supportsInterface(OPERATOR7540_INTERFACE)); // 0xe3bc4e65
        assert(basket.supportsInterface(ASYNCHRONOUS_DEPOSIT_INTERFACE)); // 0xce3bbe50
        assert(basket.supportsInterface(ASYNCHRONOUS_REDEMPTION_INTERFACE)); // 0x620ee8e4
    }

    function test_share() public {
        assert(basket.share() == address(basket));
    }

    function testFuzz_setOperator(address operator, address controller) public {
        vm.assume(operator != address(0));
        vm.assume(controller != address(0));
        vm.assume(operator != controller);
        vm.startPrank(controller);
        basket.setOperator(operator, true);
        assertEq(basket.isOperator(controller, operator), true);
        basket.setOperator(operator, false);
        assertEq(basket.isOperator(controller, operator), false);
    }

    function testFuzz_getTargetWeights(uint64[] memory expectedRet) public {
        vm.expectCall(basket.strategy(), abi.encodeCall(WeightStrategy.getTargetWeights, (basket.bitFlag())));
        vm.mockCall(
            address(basket.strategy()),
            abi.encodeCall(WeightStrategy.getTargetWeights, (basket.bitFlag())),
            abi.encode(expectedRet)
        );

        uint64[] memory ret = basket.getTargetWeights();
        assertEq(expectedRet, ret);
    }

    function testFuzz_totalAssets(uint256 totalDepositAmount, uint256 issuedShares) public {
        // Deposit assets into the basket
        testFuzz_deposit(totalDepositAmount, issuedShares);

        _totalAssetsMockCall();

        // Check that the actual total assets matches the expected value
        assertEq(basket.totalAssets(), 1e18, "Total assets should match expected");
    }

    function _totalAssetsMockCall() public {
        // Mock the call to assetRegistry to return a list of assets
        address[] memory assets = new address[](1);
        assets[0] = address(0x1);
        vm.mockCall(
            basket.assetRegistry(), abi.encodeCall(AssetRegistry.getAssets, (basket.bitFlag())), abi.encode(assets)
        );

        uint256 assetBalance = 1e18; // Assume each asset has a balance of 1 token
        vm.mockCall(
            basket.basketManager(),
            abi.encodeCall(BasketManager.basketBalanceOf, (address(basket), address(0x1))),
            abi.encode(assetBalance)
        );

        uint256 quote = 2e18; // Assume each asset is worth 2 USD
        vm.mockCall(
            basket.basketManager(),
            abi.encodeCall(BasketManager.eulerRouter, ()),
            abi.encode(address(0x123)) // Mock the eulerRouter address
        );
        vm.mockCall(
            address(0x123), // Use the mocked eulerRouter address
            abi.encodeCall(EulerRouter.getQuote, (assetBalance, address(0x1), USD)),
            abi.encode(quote)
        );

        // Convert the expected total value to the basket's asset
        uint256 expectedTotalAssets = 1e18; // Assume the basket asset is worth 1 USD
        vm.mockCall(
            basket.basketManager(),
            abi.encodeCall(BasketManager.eulerRouter, ()),
            abi.encode(address(0x123)) // Mock the eulerRouter address
        );
        vm.mockCall(
            address(0x123), // Use the mocked eulerRouter address
            abi.encodeCall(EulerRouter.getQuote, (quote, USD, basket.asset())),
            abi.encode(expectedTotalAssets)
        );
    }

    function testFuzz_harvestManagementFee1Year(
        uint256 totalDepositAmount,
        uint256 issuedShares,
        uint16 feeBps
    )
        public
    {
        // Assume shares are available to be harvested
        vm.assume(feeBps > 0 && feeBps <= MAX_MANAGEMENT_FEE);
        vm.assume(issuedShares > 1e4 && issuedShares < type(uint256).max / (feeBps * uint256(365 days)));
        testFuzz_deposit(totalDepositAmount, issuedShares);
        assertEq(basket.balanceOf(feeCollector), 0);
        // First harvest sets the date to start accruing rewards for the feeCollector
        vm.prank(address(basketManager));
        basket.prepareForRebalance(0, feeCollector);
        assertEq(basket.balanceOf(feeCollector), 0);
        vm.warp(vm.getBlockTimestamp() + 365 days);
        vm.prank(address(basketManager));
        basket.prepareForRebalance(feeBps, feeCollector);
        uint256 balance = basket.balanceOf(feeCollector);
        uint256 expected = FixedPointMathLib.fullMulDiv(issuedShares, feeBps, 1e4);
        if (expected > 0) {
            assertEq(balance, expected);
        }
    }

    function testFuzz_prepareForRebalance(
        uint256 totalDepositAmount,
        uint256 issuedShares,
        uint16 feeBps,
        uint256 timesHarvested
    )
        public
    {
        // Assume shares are available to be harvested
        vm.assume(feeBps > 0 && feeBps <= MAX_MANAGEMENT_FEE);
        vm.assume(timesHarvested > 0 && timesHarvested <= 365);
        vm.assume(issuedShares > 1e4 && issuedShares < (type(uint256).max / (feeBps * timesHarvested)) / 1e18);
        vm.assume((feeBps * issuedShares / 1e4) / timesHarvested > 1);

        // First harvest sets the date to start accruing rewards for the feeCollector
        testFuzz_deposit(totalDepositAmount, issuedShares);
        assertEq(basket.balanceOf(feeCollector), 0);

        uint256 timePerHarvest = uint256(365 days) / timesHarvested;
        uint256 startTimestamp = vm.getBlockTimestamp();
        vm.startPrank(address(basketManager));

        // Harvest the fee multiple times
        for (uint256 i = 1; i < timesHarvested; i++) {
            uint256 elapsedTime = i * timePerHarvest;
            vm.warp(startTimestamp + elapsedTime);
            basket.prepareForRebalance(feeBps, feeCollector);
        }

        // Warp to the end of the year
        vm.warp(startTimestamp + 365 days);
        basket.prepareForRebalance(feeBps, feeCollector);

        uint256 balance = basket.balanceOf(feeCollector);
        uint256 expected = FixedPointMathLib.fullMulDiv(issuedShares, feeBps, 1e4);
        // expected dust from rounding
        assertApproxEqAbs(balance, expected, 366);
    }

    function testFuzz_prepareForRebalance_CorrectCalculationWithTreasuryWithdraw(
        uint256 totalDepositAmount,
        uint256 issuedShares,
        uint16 feeBps,
        uint256 withdrawAmount
    )
        public
    {
        // Assume shares are available to be harvested
        vm.assume(feeBps > 0 && feeBps <= MAX_MANAGEMENT_FEE);
        vm.assume(issuedShares > 1e4 && issuedShares < type(uint256).max / (feeBps * uint256(365 days)));
        // vm.assume(withdrawAmount > 0 && withdrawAmount < issuedShares);
        testFuzz_deposit(totalDepositAmount, issuedShares);
        assertEq(basket.balanceOf(feeCollector), 0);

        // a year has passed, trigger the first harvest
        vm.warp(vm.getBlockTimestamp() + 365 days);
        vm.prank(address(basketManager));
        basket.prepareForRebalance(feeBps, feeCollector);

        // Fuzz and bound the withdraw amount
        withdrawAmount = bound(withdrawAmount, 1, basket.balanceOf(feeCollector));

        // Request redeem from feeCollector
        vm.prank(feeCollector);
        basket.requestRedeem(withdrawAmount, feeCollector, feeCollector);
        uint256 feeCollectorPendingRequest =
            basket.pendingRedeemRequest(basket.lastRedeemRequestId(feeCollector), feeCollector);
        assertEq(feeCollectorPendingRequest, withdrawAmount);

        // Prepare for rebalance
        vm.prank(address(basketManager));
        basket.prepareForRebalance(feeBps, feeCollector);

        // Sum the balance of the feeCollector and the pending request
        uint256 balance = basket.balanceOf(feeCollector) + feeCollectorPendingRequest;
        uint256 expected = FixedPointMathLib.fullMulDiv(issuedShares, feeBps, 1e4);
        assertEq(
            balance,
            expected,
            "Fee calculation mismatch: expected sum of current and pending balances to equal calculated fee"
        );
    }

    function testFuzz_prepareForRebalance_revertsWhen_feeBPSMax(uint16 feeBps, address receiver) public {
        vm.assume(feeBps > MAX_MANAGEMENT_FEE);
        vm.prank(address(basketManager));
        vm.expectRevert(abi.encodeWithSelector(BasketToken.InvalidManagementFee.selector));
        basket.prepareForRebalance(feeBps, receiver);
    }

    function test_multicall() public {
        ERC20Mock rewardToken = new ERC20Mock();
        FarmingPlugin farmingPlugin = new FarmingPlugin(basket, rewardToken, owner);

        dummyAsset.mint(alice, 1e18);

        vm.prank(alice);
        dummyAsset.approve(address(basket), 1e18);

        bytes[] memory data = new bytes[](2);
        data[0] = abi.encodeWithSelector(IERC20Plugins.addPlugin.selector, address(farmingPlugin));
        data[1] = abi.encodeWithSelector(BasketToken.requestDeposit.selector, 1e18, alice, alice);

        vm.prank(alice);
        basket.multicall(data);

        assertTrue(basket.hasPlugin(alice, address(farmingPlugin)));
        assertEq(dummyAsset.balanceOf(address(basket)), 1e18);
    }

    function testFuzz_setBitFlag(uint256 bitFlag) public {
        // Set the bitFlag as the basketManager
        uint256 currentBitFlag = basket.bitFlag();
        vm.expectEmit();
        emit BasketToken.BitFlagUpdated(currentBitFlag, bitFlag);
        vm.prank(address(basketManager));
        basket.setBitFlag(bitFlag);
        // Check if the bitFlag was updated correctly
        assertEq(basket.bitFlag(), bitFlag, "BitFlag was not set correctly");
    }

    function testFuzz_setBitFlag_revertWhen_CalledByNonBasketManager(uint256 bitFlag) public {
        // Assume bitFlag is a valid value
        vm.assume(bitFlag > 0);

        // Try to set the bitFlag as a non-basketManager and expect revert
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(BasketToken.NotBasketManager.selector));
        basket.setBitFlag(bitFlag);
    }

    function testFuzz_farmingPlugin(
        uint256 depositAmount,
        uint256 issuedShares,
        uint256 rewardAmount,
        uint256 rewardPeriod
    )
        public
    {
        // Use realistic range of values
        depositAmount = bound(depositAmount, 1, 100_000_000e18);
        issuedShares = bound(issuedShares, 1, 100_000_000e18);
        rewardAmount = bound(rewardAmount, 1e18, 100_000_000e18);
        rewardPeriod = bound(rewardPeriod, 1 weeks, 52 weeks);
        ERC20Mock rewardToken = new ERC20Mock();
        FarmingPlugin farmingPlugin = new FarmingPlugin(basket, rewardToken, owner);

        // Start rewards
        rewardToken.mint(owner, rewardAmount);
        vm.startPrank(owner);
        rewardToken.approve(address(farmingPlugin), rewardAmount);
        farmingPlugin.setDistributor(owner);
        farmingPlugin.startFarming(rewardAmount, rewardPeriod);
        vm.stopPrank();

        // Each user adds the farming plugin
        for (uint256 i = 0; i < MAX_USERS; i++) {
            address user = fuzzedUsers[i];
            vm.prank(user);
            basket.addPlugin(address(farmingPlugin));
        }

        // Each user deposits some tokens
        testFuzz_deposit(depositAmount, issuedShares);

        // Verify plugin balance is updated
        uint256 farmingTotalSupply = farmingPlugin.totalSupply();
        vm.assume(farmingTotalSupply > 0);

        for (uint256 i = 0; i < MAX_USERS; i++) {
            address user = fuzzedUsers[i];
            assertEq(basket.pluginBalanceOf(address(farmingPlugin), user), basket.balanceOf(user));
        }

        // Verify the rewards at half way
        vm.warp(vm.getBlockTimestamp() + rewardPeriod / 2);

        for (uint256 i = 0; i < MAX_USERS; i++) {
            address user = fuzzedUsers[i];
            uint256 userBalance = basket.balanceOf(user);
            uint256 expectedReward = userBalance == 0 ? 0 : userBalance.fullMulDiv(rewardAmount, farmingTotalSupply) / 2;
            uint256 farmed = farmingPlugin.farmed(user);
            assertApproxEqRel(farmed, expectedReward, 0.01e18);
            vm.prank(user);
            farmingPlugin.claim();
            assertApproxEqRel(rewardToken.balanceOf(user), expectedReward, 0.01e18);
        }
    }
}
