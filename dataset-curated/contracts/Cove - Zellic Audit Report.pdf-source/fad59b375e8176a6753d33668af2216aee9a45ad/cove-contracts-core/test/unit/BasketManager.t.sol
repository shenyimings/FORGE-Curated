// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { EulerRouter } from "euler-price-oracle/src/EulerRouter.sol";
import { FixedPointMathLib } from "solady/utils/FixedPointMathLib.sol";

import { BaseTest } from "test/utils/BaseTest.t.sol";
import { ERC20Mock } from "test/utils/mocks/ERC20Mock.sol";
import { MockPriceOracle } from "test/utils/mocks/MockPriceOracle.sol";

import { AssetRegistry } from "src/AssetRegistry.sol";
import { BasketManager } from "src/BasketManager.sol";
import { BasketToken } from "src/BasketToken.sol";
import { BasketManagerUtils } from "src/libraries/BasketManagerUtils.sol";
import { Errors } from "src/libraries/Errors.sol";
import { StrategyRegistry } from "src/strategies/StrategyRegistry.sol";
import { WeightStrategy } from "src/strategies/WeightStrategy.sol";
import { TokenSwapAdapter } from "src/swap_adapters/TokenSwapAdapter.sol";
import { Status } from "src/types/BasketManagerStorage.sol";
import { BasketTradeOwnership, ExternalTrade, InternalTrade } from "src/types/Trades.sol";

contract BasketManagerTest is BaseTest {
    using FixedPointMathLib for uint256;

    BasketManager public basketManager;
    MockPriceOracle public mockPriceOracle;
    EulerRouter public eulerRouter;
    address public alice;
    address public admin;
    address public feeCollector;
    address public protocolTreasury;
    address public manager;
    address public timelock;
    address public rebalanceProposer;
    address public tokenswapProposer;
    address public tokenswapExecutor;
    address public pauser;
    address public rootAsset;
    address public pairAsset;
    address public basketTokenImplementation;
    address public strategyRegistry;
    address public tokenSwapAdapter;
    address public assetRegistry;

    uint64[][] private _targetWeights;

    address public constant USD_ISO_4217_CODE = address(840);

    struct TradeTestParams {
        uint256 sellWeight;
        uint256 depositAmount;
        uint256 baseAssetWeight;
        address pairAsset;
    }

    function setUp() public override {
        super.setUp();
        vm.warp(1 weeks);
        alice = createUser("alice");
        admin = createUser("admin");
        feeCollector = createUser("feeCollector");
        protocolTreasury = createUser("protocolTreasury");
        vm.mockCall(
            feeCollector, abi.encodeWithSelector(bytes4(keccak256("protocolTreasury()"))), abi.encode(protocolTreasury)
        );
        pauser = createUser("pauser");
        manager = createUser("manager");
        rebalanceProposer = createUser("rebalanceProposer");
        tokenswapProposer = createUser("tokenswapProposer");
        tokenswapExecutor = createUser("tokenswapExecutor");

        tokenSwapAdapter = createUser("tokenSwapAdapter");
        assetRegistry = createUser("assetRegistry");
        rootAsset = address(new ERC20Mock());
        vm.label(rootAsset, "rootAsset");
        pairAsset = address(new ERC20Mock());
        vm.label(pairAsset, "pairAsset");
        basketTokenImplementation = createUser("basketTokenImplementation");
        mockPriceOracle = new MockPriceOracle();
        eulerRouter = new EulerRouter(EVC, admin);
        strategyRegistry = createUser("strategyRegistry");
        basketManager = new BasketManager(
            basketTokenImplementation, address(eulerRouter), strategyRegistry, assetRegistry, admin, feeCollector
        );
        // Admin actions
        vm.startPrank(admin);
        mockPriceOracle.setPrice(rootAsset, USD_ISO_4217_CODE, 1e18); // set price to 1e18
        mockPriceOracle.setPrice(pairAsset, USD_ISO_4217_CODE, 1e18); // set price to 1e18
        mockPriceOracle.setPrice(USD_ISO_4217_CODE, rootAsset, 1e18); // set price to 1e18
        mockPriceOracle.setPrice(USD_ISO_4217_CODE, pairAsset, 1e18); // set price to 1e18
        eulerRouter.govSetConfig(rootAsset, USD_ISO_4217_CODE, address(mockPriceOracle));
        eulerRouter.govSetConfig(pairAsset, USD_ISO_4217_CODE, address(mockPriceOracle));
        basketManager.grantRole(MANAGER_ROLE, manager);
        basketManager.grantRole(REBALANCE_PROPOSER_ROLE, rebalanceProposer);
        basketManager.grantRole(TOKENSWAP_PROPOSER_ROLE, tokenswapProposer);
        basketManager.grantRole(TOKENSWAP_EXECUTOR_ROLE, tokenswapExecutor);
        basketManager.grantRole(PAUSER_ROLE, pauser);
        basketManager.grantRole(TIMELOCK_ROLE, timelock);
        basketManager.grantRole(PAUSER_ROLE, pauser);
        vm.stopPrank();
        vm.label(address(basketManager), "basketManager");
    }

    function testFuzz_constructor(
        address basketTokenImplementation_,
        address eulerRouter_,
        address strategyRegistry_,
        address assetRegistry_,
        address admin_,
        address feeCollector_
    )
        public
    {
        vm.assume(basketTokenImplementation_ != address(0));
        vm.assume(eulerRouter_ != address(0));
        vm.assume(strategyRegistry_ != address(0));
        vm.assume(admin_ != address(0));
        vm.assume(feeCollector_ != address(0));
        vm.assume(assetRegistry_ != address(0));
        BasketManager bm = new BasketManager(
            basketTokenImplementation_, eulerRouter_, strategyRegistry_, assetRegistry_, admin_, feeCollector_
        );
        assertEq(address(bm.eulerRouter()), eulerRouter_);
        assertEq(address(bm.strategyRegistry()), strategyRegistry_);
        assertEq(address(bm.feeCollector()), feeCollector_);
        assertEq(bm.hasRole(DEFAULT_ADMIN_ROLE, admin_), true);
        assertEq(bm.getRoleMemberCount(DEFAULT_ADMIN_ROLE), 1);
    }

    /// forge-config: default.fuzz.runs = 2048
    function testFuzz_constructor_revertWhen_ZeroAddress(
        address basketTokenImplementation_,
        address eulerRouter_,
        address strategyRegistry_,
        address assetRegistry_,
        address admin_,
        address feeCollector_,
        uint256 flag
    )
        public
    {
        // Use flag to determine which address to set to zero
        vm.assume(flag <= 2 ** 6 - 2);
        if (flag & 1 == 0) {
            basketTokenImplementation_ = address(0);
        }
        if (flag & 2 == 0) {
            eulerRouter_ = address(0);
        }
        if (flag & 4 == 0) {
            strategyRegistry_ = address(0);
        }
        if (flag & 8 == 0) {
            admin_ = address(0);
        }
        if (flag & 16 == 0) {
            feeCollector_ = address(0);
        }
        if (flag & 32 == 0) {
            assetRegistry_ = address(0);
        }

        vm.expectRevert(Errors.ZeroAddress.selector);
        new BasketManager(
            basketTokenImplementation_, eulerRouter_, strategyRegistry_, assetRegistry_, admin_, feeCollector_
        );
    }

    function test_unpause() public {
        vm.prank(pauser);
        basketManager.pause();
        assertTrue(basketManager.paused(), "contract not paused");
        vm.prank(admin);
        basketManager.unpause();
        assertFalse(basketManager.paused(), "contract not unpaused");
    }

    function test_pause_revertWhen_notPauser() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(BasketManager.Unauthorized.selector));
        basketManager.pause();
    }

    function test_unpause_revertWhen_notAdmin() public {
        vm.expectRevert(_formatAccessControlError(address(this), DEFAULT_ADMIN_ROLE));
        basketManager.unpause();
    }

    function testFuzz_createNewBasket(uint256 bitFlag, address strategy) public {
        string memory name = "basket";
        string memory symbol = "b";
        vm.mockCall(
            basketTokenImplementation,
            abi.encodeCall(BasketToken.initialize, (IERC20(rootAsset), name, symbol, bitFlag, strategy, assetRegistry)),
            new bytes(0)
        );
        vm.mockCall(
            strategyRegistry, abi.encodeCall(StrategyRegistry.supportsBitFlag, (bitFlag, strategy)), abi.encode(true)
        );
        address[] memory assets = new address[](1);
        assets[0] = rootAsset;
        // Set the default management fee
        vm.prank(timelock);
        basketManager.setManagementFee(address(0), 3000);
        vm.mockCall(assetRegistry, abi.encodeCall(AssetRegistry.hasPausedAssets, (bitFlag)), abi.encode(false));
        vm.mockCall(assetRegistry, abi.encodeCall(AssetRegistry.getAssets, (bitFlag)), abi.encode(assets));

        // Predict the address of the clone using vm.computeAddress
        address predictedBasket = vm.computeCreateAddress(address(basketManager), vm.getNonce(address(basketManager)));
        vm.expectEmit();
        emit BasketManager.BasketCreated(predictedBasket, name, symbol, rootAsset, bitFlag, strategy);

        vm.prank(manager);
        address basket = basketManager.createNewBasket(name, symbol, address(rootAsset), bitFlag, strategy);
        assertEq(basketManager.numOfBasketTokens(), 1);
        address[] memory tokens = basketManager.basketTokens();
        assertEq(tokens[0], basket);
        assertEq(basketManager.basketIdToAddress(keccak256(abi.encodePacked(bitFlag, strategy))), basket);
        assertEq(basketManager.basketTokenToRebalanceAssetToIndex(basket, address(rootAsset)), 0);
        assertEq(basketManager.basketTokenToIndex(basket), 0);
        assertEq(basketManager.basketAssets(basket), assets);
        assertEq(basketManager.managementFee(basket), 3000);
    }

    function testFuzz_createNewBasket_revertWhen_BasketTokenMaxExceeded(uint256 bitFlag, address strategy) public {
        string memory name = "basket";
        string memory symbol = "b";
        bitFlag = bound(bitFlag, 0, type(uint256).max - 257);
        strategy = address(uint160(bound(uint160(strategy), 0, type(uint160).max - 257)));
        vm.mockCall(basketTokenImplementation, abi.encodeWithSelector(BasketToken.initialize.selector), new bytes(0));
        vm.mockCall(
            strategyRegistry, abi.encodeWithSelector(StrategyRegistry.supportsBitFlag.selector), abi.encode(true)
        );
        address[] memory assets = new address[](1);
        assets[0] = rootAsset;
        vm.mockCall(assetRegistry, abi.encodeWithSelector(AssetRegistry.getAssets.selector), abi.encode(assets));
        vm.startPrank(manager);
        for (uint256 i = 0; i < 256; i++) {
            bitFlag += 1;
            strategy = address(uint160(strategy) + 1);
            vm.mockCall(assetRegistry, abi.encodeCall(AssetRegistry.hasPausedAssets, (bitFlag)), abi.encode(false));
            basketManager.createNewBasket(name, symbol, rootAsset, bitFlag, strategy);
            assertEq(basketManager.numOfBasketTokens(), i + 1);
        }
        vm.expectRevert(BasketManagerUtils.BasketTokenMaxExceeded.selector);
        basketManager.createNewBasket(name, symbol, rootAsset, bitFlag, strategy);
    }

    function testFuzz_createNewBasket_revertWhen_BasketTokenAlreadyExists(uint256 bitFlag, address strategy) public {
        string memory name = "basket";
        string memory symbol = "b";
        vm.mockCall(
            basketTokenImplementation,
            abi.encodeCall(BasketToken.initialize, (IERC20(rootAsset), name, symbol, bitFlag, strategy, assetRegistry)),
            new bytes(0)
        );
        vm.mockCall(
            strategyRegistry, abi.encodeCall(StrategyRegistry.supportsBitFlag, (bitFlag, strategy)), abi.encode(true)
        );
        address[] memory assets = new address[](1);
        assets[0] = rootAsset;
        vm.mockCall(assetRegistry, abi.encodeCall(AssetRegistry.hasPausedAssets, (bitFlag)), abi.encode(false));
        vm.mockCall(assetRegistry, abi.encodeCall(AssetRegistry.getAssets, (bitFlag)), abi.encode(assets));
        vm.startPrank(manager);
        basketManager.createNewBasket(name, symbol, rootAsset, bitFlag, strategy);
        vm.expectRevert(BasketManagerUtils.BasketTokenAlreadyExists.selector);
        basketManager.createNewBasket(name, symbol, rootAsset, bitFlag, strategy);
    }

    function testFuzz_createNewBasket_revertWhen_StrategyRegistryDoesNotSupportStrategy(
        uint256 bitFlag,
        address strategy
    )
        public
    {
        string memory name = "basket";
        string memory symbol = "b";
        vm.mockCall(
            basketTokenImplementation,
            abi.encodeCall(BasketToken.initialize, (IERC20(rootAsset), name, symbol, bitFlag, strategy, assetRegistry)),
            new bytes(0)
        );
        vm.mockCall(
            strategyRegistry, abi.encodeCall(StrategyRegistry.supportsBitFlag, (bitFlag, strategy)), abi.encode(false)
        );
        vm.expectRevert(BasketManagerUtils.StrategyRegistryDoesNotSupportStrategy.selector);
        vm.startPrank(manager);
        basketManager.createNewBasket(name, symbol, rootAsset, bitFlag, strategy);
    }

    function testFuzz_createNewBasket_revertWhen_CallerIsNotManager(address caller) public {
        vm.assume(!basketManager.hasRole(MANAGER_ROLE, caller));
        string memory name = "basket";
        string memory symbol = "b";
        uint256 bitFlag = 1;
        address strategy = address(uint160(1));
        vm.prank(caller);
        vm.expectRevert(_formatAccessControlError(caller, MANAGER_ROLE));
        basketManager.createNewBasket(name, symbol, rootAsset, bitFlag, strategy);
    }

    function test_createNewBasket_revertWhen_AssetListEmpty() public {
        string memory name = "basket";
        string memory symbol = "b";
        uint256 bitFlag = 1;
        address strategy = address(uint160(1));
        address[] memory assets = new address[](0);
        vm.mockCall(
            basketTokenImplementation,
            abi.encodeCall(BasketToken.initialize, (IERC20(rootAsset), name, symbol, bitFlag, strategy, assetRegistry)),
            new bytes(0)
        );
        vm.mockCall(
            strategyRegistry, abi.encodeCall(StrategyRegistry.supportsBitFlag, (bitFlag, strategy)), abi.encode(true)
        );
        vm.mockCall(assetRegistry, abi.encodeCall(AssetRegistry.hasPausedAssets, (bitFlag)), abi.encode(false));
        vm.mockCall(assetRegistry, abi.encodeCall(AssetRegistry.getAssets, (bitFlag)), abi.encode(assets));
        vm.expectRevert(BasketManagerUtils.AssetListEmpty.selector);
        vm.prank(manager);
        basketManager.createNewBasket(name, symbol, rootAsset, bitFlag, strategy);
    }

    function test_createNewBasket_revertWhen_HasPausedAssets() public {
        string memory name = "basket";
        string memory symbol = "b";
        uint256 bitFlag = 1;
        address strategy = address(uint160(1));
        address[] memory assets = new address[](1);
        assets[0] = rootAsset;
        vm.mockCall(
            basketTokenImplementation,
            abi.encodeCall(BasketToken.initialize, (IERC20(rootAsset), name, symbol, bitFlag, strategy, assetRegistry)),
            new bytes(0)
        );
        vm.mockCall(
            strategyRegistry, abi.encodeCall(StrategyRegistry.supportsBitFlag, (bitFlag, strategy)), abi.encode(true)
        );
        vm.mockCall(assetRegistry, abi.encodeCall(AssetRegistry.hasPausedAssets, (bitFlag)), abi.encode(true));
        vm.mockCall(assetRegistry, abi.encodeCall(AssetRegistry.getAssets, (bitFlag)), abi.encode(assets));
        vm.expectRevert(BasketManagerUtils.AssetNotEnabled.selector);
        vm.prank(manager);
        basketManager.createNewBasket(name, symbol, rootAsset, bitFlag, strategy);
    }

    function test_createNewBasket_passesWhen_BaseAssetNotFirst() public {
        string memory name = "basket";
        string memory symbol = "b";
        uint256 bitFlag = 1;
        address strategy = address(uint160(1));
        address wrongAsset = address(new ERC20Mock());
        address[] memory assets = new address[](2);
        assets[0] = wrongAsset;
        assets[1] = rootAsset;

        vm.mockCall(
            basketTokenImplementation,
            abi.encodeCall(BasketToken.initialize, (IERC20(rootAsset), name, symbol, bitFlag, strategy, assetRegistry)),
            new bytes(0)
        );
        vm.mockCall(
            strategyRegistry, abi.encodeCall(StrategyRegistry.supportsBitFlag, (bitFlag, strategy)), abi.encode(true)
        );
        vm.mockCall(assetRegistry, abi.encodeCall(AssetRegistry.hasPausedAssets, (bitFlag)), abi.encode(false));
        vm.mockCall(assetRegistry, abi.encodeCall(AssetRegistry.getAssets, (bitFlag)), abi.encode(assets));
        vm.prank(manager);
        basketManager.createNewBasket(name, symbol, rootAsset, bitFlag, strategy);
    }

    function testFuzz_createNewBasket_revertWhen_baseAssetNotIncluded(uint256 bitFlag, address strategy) public {
        string memory name = "basket";
        string memory symbol = "b";
        vm.mockCall(
            basketTokenImplementation,
            abi.encodeCall(BasketToken.initialize, (IERC20(rootAsset), name, symbol, bitFlag, strategy, assetRegistry)),
            new bytes(0)
        );
        vm.mockCall(
            strategyRegistry, abi.encodeCall(StrategyRegistry.supportsBitFlag, (bitFlag, strategy)), abi.encode(true)
        );
        address[] memory assets = new address[](1);
        assets[0] = pairAsset;
        // Set the default management fee
        vm.prank(timelock);
        basketManager.setManagementFee(address(0), 3000);
        vm.mockCall(assetRegistry, abi.encodeCall(AssetRegistry.hasPausedAssets, (bitFlag)), abi.encode(false));
        // Mock the call to getAssets to not include base asset
        vm.mockCall(assetRegistry, abi.encodeCall(AssetRegistry.getAssets, (bitFlag)), abi.encode(assets));
        vm.expectRevert(BasketManagerUtils.BaseAssetMismatch.selector);
        vm.prank(manager);
        basketManager.createNewBasket(name, symbol, address(rootAsset), bitFlag, strategy);
    }

    function test_createNewBasket_revertWhen_BaseAssetIsZeroAddress() public {
        string memory name = "basket";
        string memory symbol = "b";
        uint256 bitFlag = 1;
        address strategy = address(uint160(1));
        address[] memory assets = new address[](1);
        assets[0] = rootAsset;
        vm.prank(manager);
        vm.expectRevert(Errors.ZeroAddress.selector);
        basketManager.createNewBasket(name, symbol, address(0), bitFlag, strategy);
    }

    function test_createNewBasket_revertWhen_paused() public {
        string memory name = "basket";
        string memory symbol = "b";
        uint256 bitFlag = 1;
        address strategy = address(uint160(1));
        address[] memory assets = new address[](1);
        assets[0] = address(0);

        vm.prank(pauser);
        basketManager.pause();
        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(manager);
        basketManager.createNewBasket(name, symbol, address(0), bitFlag, strategy);
    }

    function test_basketTokenToIndex() public {
        string memory name = "basket";
        string memory symbol = "b";
        vm.mockCall(basketTokenImplementation, abi.encodeWithSelector(BasketToken.initialize.selector), new bytes(0));
        vm.mockCall(
            strategyRegistry, abi.encodeWithSelector(StrategyRegistry.supportsBitFlag.selector), abi.encode(true)
        );
        address[] memory assets = new address[](1);
        assets[0] = rootAsset;
        vm.mockCall(assetRegistry, abi.encodeWithSelector(AssetRegistry.hasPausedAssets.selector), abi.encode(false));
        vm.mockCall(assetRegistry, abi.encodeWithSelector(AssetRegistry.getAssets.selector), abi.encode(assets));
        address[] memory baskets = new address[](256);
        vm.startPrank(manager);
        for (uint256 i = 0; i < 256; i++) {
            baskets[i] = basketManager.createNewBasket(name, symbol, rootAsset, i, address(uint160(i)));
            assertEq(basketManager.basketTokenToIndex(baskets[i]), i);
        }

        for (uint256 i = 0; i < 256; i++) {
            assertEq(basketManager.basketTokenToIndex(baskets[i]), i);
        }
    }

    function test_basketTokenToIndex_revertWhen_BasketTokenNotFound() public {
        vm.expectRevert(BasketManagerUtils.BasketTokenNotFound.selector);
        basketManager.basketTokenToIndex(address(0));
    }

    function testFuzz_basketTokenToIndex_revertWhen_BasketTokenNotFound(address basket) public {
        string memory name = "basket";
        string memory symbol = "b";
        vm.mockCall(basketTokenImplementation, abi.encodeWithSelector(BasketToken.initialize.selector), new bytes(0));
        vm.mockCall(
            strategyRegistry, abi.encodeWithSelector(StrategyRegistry.supportsBitFlag.selector), abi.encode(true)
        );
        address[] memory assets = new address[](1);
        assets[0] = rootAsset;
        vm.mockCall(assetRegistry, abi.encodeWithSelector(AssetRegistry.hasPausedAssets.selector), abi.encode(false));
        vm.mockCall(assetRegistry, abi.encodeWithSelector(AssetRegistry.getAssets.selector), abi.encode(assets));
        address[] memory baskets = new address[](256);
        vm.startPrank(manager);
        for (uint256 i = 0; i < 256; i++) {
            baskets[i] = basketManager.createNewBasket(name, symbol, rootAsset, i, address(uint160(i)));
            vm.assume(baskets[i] != basket);
        }

        vm.expectRevert(BasketManagerUtils.BasketTokenNotFound.selector);
        basketManager.basketTokenToIndex(basket);
    }

    function test_proposeRebalance_processesDeposits() public returns (address basket) {
        basket = _setupSingleBasketAndMocks();
        address[] memory targetBaskets = new address[](1);
        targetBaskets[0] = basket;
        vm.prank(rebalanceProposer);
        basketManager.proposeRebalance(targetBaskets);

        assertEq(basketManager.rebalanceStatus().timestamp, vm.getBlockTimestamp());
        assertEq(uint8(basketManager.rebalanceStatus().status), uint8(Status.REBALANCE_PROPOSED));
        assertEq(basketManager.rebalanceStatus().basketMask, 1);
        assertEq(basketManager.rebalanceStatus().basketHash, keccak256(abi.encode(targetBaskets, _targetWeights)));
    }

    function testFuzz_proposeRebalance_processDeposits_passesWhen_targetBalancesMet(uint256 initialDepositAmount)
        public
    {
        initialDepositAmount = bound(initialDepositAmount, 1e4, type(uint256).max / 1e36);
        address[][] memory assetsPerBasket = new address[][](1);
        assetsPerBasket[0] = new address[](2);
        assetsPerBasket[0][0] = rootAsset;
        assetsPerBasket[0][1] = pairAsset;
        uint64[][] memory weightsPerBasket = new uint64[][](1);
        weightsPerBasket[0] = new uint64[](2);
        weightsPerBasket[0][0] = 1e18;
        weightsPerBasket[0][1] = 0;
        uint256[] memory initialDepositAmounts = new uint256[](1);
        initialDepositAmounts[0] = initialDepositAmount;
        address[] memory baskets = _setupBasketsAndMocks(assetsPerBasket, weightsPerBasket, initialDepositAmounts);
        vm.prank(rebalanceProposer);
        basketManager.proposeRebalance(baskets);

        assertEq(basketManager.rebalanceStatus().timestamp, vm.getBlockTimestamp());
        assertEq(uint8(basketManager.rebalanceStatus().status), uint8(Status.REBALANCE_PROPOSED));
        assertEq(basketManager.rebalanceStatus().basketHash, keccak256(abi.encode(baskets, weightsPerBasket)));
    }

    function test_proposeRebalance_revertWhen_noDeposits_RebalanceNotRequired() public {
        address basket = _setupSingleBasketAndMocks(0);
        address[] memory targetBaskets = new address[](1);
        targetBaskets[0] = basket;

        vm.expectRevert(BasketManagerUtils.RebalanceNotRequired.selector);
        vm.prank(rebalanceProposer);
        basketManager.proposeRebalance(targetBaskets);
    }

    function test_proposeRebalance_revertWhen_HasPausedAssets() public {
        address basket = _setupSingleBasketAndMocks();
        address[] memory targetBaskets = new address[](1);
        targetBaskets[0] = basket;
        vm.mockCall(assetRegistry, abi.encodeCall(AssetRegistry.hasPausedAssets, (1)), abi.encode(true));
        vm.expectRevert(BasketManagerUtils.AssetNotEnabled.selector);
        vm.prank(rebalanceProposer);
        basketManager.proposeRebalance(targetBaskets);
    }

    function test_proposeRebalance_revertWhen_MustWaitForRebalanceToComplete() public {
        address basket = _setupSingleBasketAndMocks();
        address[] memory targetBaskets = new address[](1);
        targetBaskets[0] = basket;
        vm.startPrank(rebalanceProposer);
        basketManager.proposeRebalance(targetBaskets);

        vm.expectRevert(BasketManagerUtils.MustWaitForRebalanceToComplete.selector);
        basketManager.proposeRebalance(targetBaskets);
    }

    function testFuzz_proposeRebalance_revertWhen_BasketTokenNotFound(address fakeBasket) public {
        address[] memory targetBaskets = new address[](1);
        targetBaskets[0] = fakeBasket;
        vm.expectRevert(BasketManagerUtils.BasketTokenNotFound.selector);
        vm.prank(rebalanceProposer);
        basketManager.proposeRebalance(targetBaskets);
    }

    function testFuzz_proposeRebalance_revertWhen_CallerIsNotRebalancer(address caller) public {
        vm.assume(!basketManager.hasRole(REBALANCE_PROPOSER_ROLE, caller));
        address[] memory targetBaskets = new address[](1);
        vm.expectRevert(_formatAccessControlError(caller, REBALANCE_PROPOSER_ROLE));
        vm.prank(caller);
        basketManager.proposeRebalance(targetBaskets);
    }

    function test_proposeRebalance_processesDeposits_revertWhen_paused() public {
        address basket = _setupSingleBasketAndMocks();
        address[] memory targetBaskets = new address[](1);
        targetBaskets[0] = basket;
        vm.prank(pauser);
        basketManager.pause();
        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(rebalanceProposer);
        basketManager.proposeRebalance(targetBaskets);
    }

    function test_proposeRebalance_revertsWhen_tooEarlyToProposeRebalance() public {
        address basket = testFuzz_completeRebalance_externalTrade(1e18, 5e18);
        address[] memory targetBaskets = new address[](1);
        targetBaskets[0] = basket;
        vm.expectRevert(BasketManagerUtils.TooEarlyToProposeRebalance.selector);
        vm.prank(rebalanceProposer);
        basketManager.proposeRebalance(targetBaskets);
    }

    function testFuzz_completeRebalance_passWhen_redeemingShares(uint16 fee) public {
        uint256 intialDepositAmount = 10_000;
        uint256 initialSplit = 5e17; // 50 / 50 between both baskets
        address[] memory targetBaskets = testFuzz_proposeTokenSwap_internalTrade(initialSplit, intialDepositAmount, fee);
        address basket = targetBaskets[0];

        // Simulate the passage of time
        vm.warp(vm.getBlockTimestamp() + 15 minutes + 1);
        vm.mockCall(basket, abi.encodeCall(BasketToken.totalPendingDeposits, ()), abi.encode(0));
        vm.mockCall(
            basket, abi.encodeWithSelector(BasketToken.prepareForRebalance.selector), abi.encode(intialDepositAmount, 0)
        );
        vm.mockCall(basket, abi.encodeWithSelector(BasketToken.fulfillRedeem.selector), new bytes(0));
        vm.mockCall(rootAsset, abi.encodeWithSelector(IERC20.approve.selector), abi.encode(true));
        vm.mockCall(basket, abi.encodeCall(IERC20.totalSupply, ()), abi.encode(10_000));
        vm.expectEmit();
        emit BasketManagerUtils.RebalanceCompleted(basketManager.rebalanceStatus().epoch);
        basketManager.completeRebalance(new ExternalTrade[](0), targetBaskets, _targetWeights);

        vm.warp(vm.getBlockTimestamp() + 1 weeks + 1);
        vm.mockCall(basket, abi.encodeCall(BasketToken.totalPendingDeposits, ()), abi.encode(0));
        vm.mockCall(basket, abi.encodeWithSelector(BasketToken.prepareForRebalance.selector), abi.encode(0, 10_000));
        vm.mockCall(basket, abi.encodeWithSelector(BasketToken.fulfillDeposit.selector), new bytes(0));
        vm.mockCall(basket, abi.encodeCall(IERC20.totalSupply, ()), abi.encode(10_000));
        vm.prank(rebalanceProposer);
        basketManager.proposeRebalance(targetBaskets);

        // Simulate the passage of time
        vm.warp(vm.getBlockTimestamp() + 15 minutes + 1);

        vm.mockCall(basket, abi.encodeCall(BasketToken.totalPendingDeposits, ()), abi.encode(0));
        vm.mockCall(basket, abi.encodeWithSelector(BasketToken.prepareForRebalance.selector), abi.encode(0, 10_000));
        vm.mockCall(basket, abi.encodeWithSelector(BasketToken.fulfillRedeem.selector), new bytes(0));
        vm.mockCall(rootAsset, abi.encodeWithSelector(IERC20.approve.selector), abi.encode(true));
        vm.mockCall(basket, abi.encodeCall(IERC20.totalSupply, ()), abi.encode(10_000));
        basketManager.completeRebalance(new ExternalTrade[](0), targetBaskets, _targetWeights);
    }

    function testFuzz_completeRebalance_externalTrade(
        uint256 initialDepositAmount,
        uint256 sellWeight
    )
        public
        returns (address basket)
    {
        _setTokenSwapAdapter();
        initialDepositAmount = bound(initialDepositAmount, 1e4, type(uint256).max / 1e36);
        sellWeight = bound(sellWeight, 0, 1e18);
        (ExternalTrade[] memory trades, address[] memory targetBaskets) =
            testFuzz_proposeTokenSwap_externalTrade(sellWeight, initialDepositAmount);
        basket = targetBaskets[0];

        // Mock calls for executeTokenSwap
        uint256 numTrades = trades.length;
        bytes32[] memory tradeHashes = new bytes32[](numTrades);
        for (uint8 i = 0; i < numTrades; i++) {
            tradeHashes[i] = keccak256(abi.encode(trades[i]));
        }
        vm.mockCall(
            address(tokenSwapAdapter),
            abi.encodeWithSelector(TokenSwapAdapter.executeTokenSwap.selector),
            abi.encode(tradeHashes)
        );
        // Execute
        vm.expectEmit();
        emit BasketManager.TokenSwapExecuted(basketManager.rebalanceStatus().epoch);
        vm.prank(tokenswapExecutor);
        basketManager.executeTokenSwap(trades, "");

        // Assert
        assertEq(basketManager.rebalanceStatus().timestamp, vm.getBlockTimestamp());
        assertEq(uint8(basketManager.rebalanceStatus().status), uint8(Status.TOKEN_SWAP_EXECUTED));

        // Simulate the passage of time
        vm.warp(vm.getBlockTimestamp() + 15 minutes + 1);

        vm.mockCall(basket, abi.encodeCall(BasketToken.totalPendingDeposits, ()), abi.encode(0));
        vm.mockCall(basket, abi.encodeWithSelector(BasketToken.prepareForRebalance.selector), abi.encode(0));
        vm.mockCall(basket, abi.encodeWithSelector(BasketToken.fulfillRedeem.selector), new bytes(0));
        vm.mockCall(rootAsset, abi.encodeWithSelector(IERC20.approve.selector), abi.encode(true));
        vm.mockCall(basket, abi.encodeCall(IERC20.totalSupply, ()), abi.encode(initialDepositAmount));
        // Mock results of external trade
        uint256[2][] memory claimedAmounts = new uint256[2][](numTrades);
        // 0 in the 1 index is the result of a 100% successful trade
        claimedAmounts[0] = [0, initialDepositAmount * sellWeight / 1e18];
        vm.mockCall(
            address(tokenSwapAdapter),
            abi.encodeWithSelector(TokenSwapAdapter.completeTokenSwap.selector),
            abi.encode(claimedAmounts)
        );
        vm.expectEmit();
        emit BasketManagerUtils.RebalanceCompleted(basketManager.rebalanceStatus().epoch);
        basketManager.completeRebalance(trades, targetBaskets, _targetWeights);
        assertEq(uint8(basketManager.rebalanceStatus().status), uint8(Status.NOT_STARTED));
    }

    function testFuzz_completeRebalance_retries_whenExternalTrade_fails(
        uint256 initialDepositAmount,
        uint256 sellWeight
    )
        public
    {
        _setTokenSwapAdapter();
        initialDepositAmount = bound(initialDepositAmount, 1e4, type(uint256).max / 1e36);
        sellWeight = bound(sellWeight, 1e17, 1e18);
        (ExternalTrade[] memory trades, address[] memory targetBaskets) =
            testFuzz_proposeTokenSwap_externalTrade(sellWeight, initialDepositAmount);
        address basket = targetBaskets[0];

        // Mock calls for executeTokenSwap
        uint256 numTrades = trades.length;
        bytes32[] memory tradeHashes = new bytes32[](numTrades);
        for (uint8 i = 0; i < numTrades; i++) {
            tradeHashes[i] = keccak256(abi.encode(trades[i]));
        }
        vm.mockCall(
            address(tokenSwapAdapter),
            abi.encodeWithSelector(TokenSwapAdapter.executeTokenSwap.selector),
            abi.encode(tradeHashes)
        );
        // Execute
        vm.expectEmit();
        emit BasketManager.TokenSwapExecuted(basketManager.rebalanceStatus().epoch);
        vm.prank(tokenswapExecutor);
        basketManager.executeTokenSwap(trades, "");

        // Assert
        assertEq(basketManager.rebalanceStatus().timestamp, vm.getBlockTimestamp());
        assertEq(uint8(basketManager.rebalanceStatus().status), uint8(Status.TOKEN_SWAP_EXECUTED));

        // Simulate the passage of time
        vm.warp(vm.getBlockTimestamp() + 15 minutes + 1);

        vm.mockCall(basket, abi.encodeCall(BasketToken.totalPendingDeposits, ()), abi.encode(0));
        vm.mockCall(basket, abi.encodeWithSelector(BasketToken.prepareForRebalance.selector), abi.encode(0));
        vm.mockCall(basket, abi.encodeWithSelector(BasketToken.fulfillRedeem.selector), new bytes(0));
        vm.mockCall(rootAsset, abi.encodeWithSelector(IERC20.approve.selector), abi.encode(true));
        vm.mockCall(basket, abi.encodeCall(IERC20.totalSupply, ()), abi.encode(initialDepositAmount));
        // Mock results of external trade
        uint256[2][] memory claimedAmounts = new uint256[2][](numTrades);
        // 0 in the 1 index is the result of a 100% un-successful trade
        claimedAmounts[0] = [initialDepositAmount * sellWeight / 1e18, 0];
        vm.mockCall(
            address(tokenSwapAdapter),
            abi.encodeWithSelector(TokenSwapAdapter.completeTokenSwap.selector),
            abi.encode(claimedAmounts)
        );
        assertEq(basketManager.retryCount(), uint256(0));
        basketManager.completeRebalance(trades, targetBaskets, _targetWeights);
        // When target weights are not met the status returns to REBALANCE_PROPOSED to allow additional token swaps to
        // be proposed
        assertEq(uint8(basketManager.rebalanceStatus().status), uint8(Status.REBALANCE_PROPOSED));
        assertEq(basketManager.retryCount(), uint256(1));
    }

    function testFuzz_completeRebalance_passesWhen_retryLimitReached(
        uint256 initialDepositAmount,
        uint256 sellWeight
    )
        public
    {
        _setTokenSwapAdapter();
        // Setup basket and target weights
        TradeTestParams memory params;
        params.depositAmount = bound(initialDepositAmount, 1e4, type(uint256).max / 1e36);
        params.sellWeight = bound(sellWeight, 1e17, 1e18);
        params.baseAssetWeight = 1e18 - params.sellWeight;
        params.pairAsset = pairAsset;

        address[][] memory basketAssets = new address[][](1);
        basketAssets[0] = new address[](2);
        basketAssets[0][0] = rootAsset;
        basketAssets[0][1] = params.pairAsset;
        uint256[] memory initialDepositAmounts = new uint256[](1);
        initialDepositAmounts[0] = params.depositAmount;
        uint64[][] memory targetWeights = new uint64[][](1);
        targetWeights[0] = new uint64[](2);
        targetWeights[0][0] = uint64(params.baseAssetWeight);
        targetWeights[0][1] = uint64(params.sellWeight);
        address[] memory baskets = _setupBasketsAndMocks(basketAssets, targetWeights, initialDepositAmounts);

        // Propose the rebalance
        vm.prank(rebalanceProposer);
        basketManager.proposeRebalance(baskets);

        for (uint8 i = 0; i < MAX_RETRIES; i++) {
            // 0 for the last input will guarantee the trade will be 100% unsuccessful
            _proposeAndCompleteExternalTrades(baskets, targetWeights, params.depositAmount, params.sellWeight, 0);
            assertEq(basketManager.retryCount(), uint256(i + 1));
            assertEq(uint8(basketManager.rebalanceStatus().status), uint8(Status.REBALANCE_PROPOSED));
        }
        assertEq(basketManager.retryCount(), uint256(MAX_RETRIES));

        // We have reached max retries, if the next proposed token swap does not meet target weights the rebalance
        // will successfully complete.
        _proposeAndCompleteExternalTrades(baskets, targetWeights, params.depositAmount, params.sellWeight, 0);
        assertEq(basketManager.retryCount(), uint256(0));
        assertEq(uint8(basketManager.rebalanceStatus().status), uint8(Status.NOT_STARTED));
    }

    function testFuzz_completeRebalance_fulfillsRedeemsWhen_retryLimitReached(
        uint256 initialDepositAmount,
        uint256 sellWeight
    )
        public
    {
        _setTokenSwapAdapter();
        // Setup basket and target weights
        TradeTestParams memory params;
        params.depositAmount = bound(initialDepositAmount, 1e18, type(uint256).max / 1e54);
        params.sellWeight = bound(sellWeight, 5e17, 1e18);
        params.baseAssetWeight = 1e18 - params.sellWeight;
        params.pairAsset = pairAsset;

        address[][] memory basketAssets = new address[][](1);
        basketAssets[0] = new address[](2);
        basketAssets[0][0] = rootAsset;
        basketAssets[0][1] = params.pairAsset;
        uint256[] memory initialDepositAmounts = new uint256[](1);
        initialDepositAmounts[0] = params.depositAmount;
        uint64[][] memory targetWeights = new uint64[][](1);
        targetWeights[0] = new uint64[](2);
        targetWeights[0][0] = uint64(params.baseAssetWeight);
        targetWeights[0][1] = uint64(params.sellWeight);
        address[] memory baskets = _setupBasketsAndMocks(basketAssets, targetWeights, initialDepositAmounts);
        address basket = baskets[0];
        BasketManager bm = basketManager;
        // We mock a pending redemption
        vm.mockCall(
            basket,
            abi.encodeWithSelector(BasketToken.prepareForRebalance.selector),
            abi.encode(params.depositAmount, uint256(params.depositAmount / 10))
        );
        // Propose the rebalance
        vm.prank(rebalanceProposer);
        bm.proposeRebalance(baskets);

        for (uint8 i = 0; i < MAX_RETRIES; i++) {
            // 0 for the last input will guarantee the trade will be 100% unsuccessful
            _proposeAndCompleteExternalTrades(baskets, targetWeights, params.depositAmount, params.sellWeight, 0);
            assertEq(bm.retryCount(), uint256(i + 1));
            assertEq(uint8(bm.rebalanceStatus().status), uint8(Status.REBALANCE_PROPOSED));
        }
        assertEq(bm.retryCount(), uint256(MAX_RETRIES));

        // We have reached max retries, if the next proposed token swap does not meet target weights the rebalance
        // will successfully complete.
        ExternalTrade[] memory externalTrades = new ExternalTrade[](1);
        BasketTradeOwnership[] memory tradeOwnerships = new BasketTradeOwnership[](1);
        tradeOwnerships[0] = BasketTradeOwnership({ basket: baskets[0], tradeOwnership: uint96(1e18) });
        externalTrades[0] = ExternalTrade({
            sellToken: rootAsset,
            buyToken: params.pairAsset,
            sellAmount: params.depositAmount * params.sellWeight / 1e18,
            minAmount: (params.depositAmount * params.sellWeight / 1e18) * 0.995e18 / 1e18,
            basketTradeOwnership: tradeOwnerships
        });
        vm.prank(tokenswapProposer);
        bm.proposeTokenSwap(new InternalTrade[](0), externalTrades, baskets, targetWeights);
        // Mock calls for executeTokenSwap
        uint256 numTrades = externalTrades.length;
        bytes32[] memory tradeHashes = new bytes32[](numTrades);
        for (uint8 i = 0; i < numTrades; i++) {
            tradeHashes[i] = keccak256(abi.encode(externalTrades[i]));
        }
        vm.mockCall(
            address(tokenSwapAdapter),
            abi.encodeWithSelector(TokenSwapAdapter.executeTokenSwap.selector),
            abi.encode(tradeHashes)
        );
        // Execute
        vm.prank(tokenswapExecutor);
        bm.executeTokenSwap(externalTrades, "");
        // Simulate the passage of time
        vm.warp(vm.getBlockTimestamp() + 15 minutes + 1);

        vm.mockCall(basket, abi.encodeCall(BasketToken.totalPendingDeposits, ()), abi.encode(0));
        vm.mockCall(basket, abi.encodeWithSelector(BasketToken.prepareForRebalance.selector), abi.encode(0, 0));
        vm.mockCall(rootAsset, abi.encodeWithSelector(IERC20.approve.selector), abi.encode(true));
        vm.mockCall(basket, abi.encodeCall(IERC20.totalSupply, ()), abi.encode(params.depositAmount));

        uint256[2][] memory claimedAmounts = new uint256[2][](numTrades);
        // tradeSuccess => 1e18 for a 100% successful trade, 0 for 100% unsuccessful trade
        // 0 in the 0th place is the result of a 100% un-successful trade
        // 0 in the 1st place is the result of a 100% successful trade
        // We mock a partially successful trade so that target weights are not met and but enough tokens are available
        // to meet pending redemptions
        uint256 successfulSellAmount = externalTrades[0].sellAmount * 7e17 / 1e18;
        claimedAmounts[0] = [externalTrades[0].sellAmount - successfulSellAmount, successfulSellAmount];
        vm.mockCall(
            address(tokenSwapAdapter),
            abi.encodeWithSelector(TokenSwapAdapter.completeTokenSwap.selector),
            abi.encode(claimedAmounts)
        );
        vm.expectCall(basket, abi.encodeCall(BasketToken.fulfillRedeem, (uint256(initialDepositAmounts[0] / 10))));
        bm.completeRebalance(externalTrades, baskets, targetWeights);
        assertEq(bm.retryCount(), uint256(0));
        assertEq(uint8(bm.rebalanceStatus().status), uint8(Status.NOT_STARTED));
    }

    function testFuzz_completeRebalance_triggers_notifyFailedRebalance_when_retryLimitReached(
        uint256 initialDepositAmount,
        uint256 sellWeight
    )
        public
    {
        _setTokenSwapAdapter();
        // Setup basket and target weights
        TradeTestParams memory params;
        params.depositAmount = bound(initialDepositAmount, 1e18, type(uint256).max / 1e54);
        params.sellWeight = bound(sellWeight, 5e17, 1e18);
        params.baseAssetWeight = 1e18 - params.sellWeight;
        params.pairAsset = pairAsset;
        address[][] memory basketAssets = new address[][](1);
        basketAssets[0] = new address[](2);
        basketAssets[0][0] = rootAsset;
        basketAssets[0][1] = params.pairAsset;
        uint256[] memory initialDepositAmounts = new uint256[](1);
        initialDepositAmounts[0] = params.depositAmount;
        uint64[][] memory targetWeights = new uint64[][](1);
        targetWeights[0] = new uint64[](2);
        targetWeights[0][0] = uint64(params.baseAssetWeight);
        targetWeights[0][1] = uint64(params.sellWeight);
        address[] memory baskets = _setupBasketsAndMocks(basketAssets, targetWeights, initialDepositAmounts);
        address basket = baskets[0];
        // We mock a pending redemption
        vm.mockCall(
            basket,
            abi.encodeWithSelector(BasketToken.prepareForRebalance.selector),
            abi.encode(params.depositAmount, uint256(params.depositAmount - 10))
        );
        // Propose the rebalance
        vm.prank(rebalanceProposer);
        basketManager.proposeRebalance(baskets);

        for (uint8 i = 0; i < MAX_RETRIES; i++) {
            // 0 for the last input will guarantee the trade will be 100% unsuccessful
            _proposeAndCompleteExternalTrades(baskets, targetWeights, params.depositAmount, params.sellWeight, 0);
            assertEq(basketManager.retryCount(), uint256(i + 1));
            assertEq(uint8(basketManager.rebalanceStatus().status), uint8(Status.REBALANCE_PROPOSED));
        }
        assertEq(basketManager.retryCount(), uint256(MAX_RETRIES));

        // We have reached max retries, if the next proposed token swap does not meet target weights the rebalance
        // will successfully complete.
        ExternalTrade[] memory externalTrades = new ExternalTrade[](1);
        InternalTrade[] memory internalTrades = new InternalTrade[](0);
        BasketTradeOwnership[] memory tradeOwnerships = new BasketTradeOwnership[](1);
        tradeOwnerships[0] = BasketTradeOwnership({ basket: baskets[0], tradeOwnership: uint96(1e18) });
        externalTrades[0] = ExternalTrade({
            sellToken: rootAsset,
            buyToken: params.pairAsset,
            sellAmount: params.depositAmount * params.sellWeight / 1e18,
            minAmount: (params.depositAmount * params.sellWeight / 1e18) * 0.995e18 / 1e18,
            basketTradeOwnership: tradeOwnerships
        });
        vm.prank(tokenswapProposer);
        basketManager.proposeTokenSwap(internalTrades, externalTrades, baskets, targetWeights);
        // Mock calls for executeTokenSwap
        uint256 numTrades = externalTrades.length;
        bytes32[] memory tradeHashes = new bytes32[](numTrades);
        for (uint8 i = 0; i < numTrades; i++) {
            tradeHashes[i] = keccak256(abi.encode(externalTrades[i]));
        }
        vm.mockCall(
            address(tokenSwapAdapter),
            abi.encodeWithSelector(TokenSwapAdapter.executeTokenSwap.selector),
            abi.encode(tradeHashes)
        );
        // Execute
        vm.prank(tokenswapExecutor);
        basketManager.executeTokenSwap(externalTrades, "");
        // Simulate the passage of time
        vm.warp(vm.getBlockTimestamp() + 15 minutes + 1);

        vm.mockCall(basket, abi.encodeCall(BasketToken.totalPendingDeposits, ()), abi.encode(0));
        vm.mockCall(basket, abi.encodeWithSelector(BasketToken.prepareForRebalance.selector), abi.encode(0, 0));
        vm.mockCall(rootAsset, abi.encodeWithSelector(IERC20.approve.selector), abi.encode(true));
        vm.mockCall(basket, abi.encodeCall(IERC20.totalSupply, ()), abi.encode(params.depositAmount));

        uint256[2][] memory claimedAmounts = new uint256[2][](numTrades);
        // tradeSuccess => 1e18 for a 100% successful trade, 0 for 100% unsuccessful trade
        // 0 in the 0th place is the result of a 100% un-successful trade
        // 0 in the 1st place is the result of a 100% successful trade
        // We mock a partially successful trade so that target weights are not met and not enough tokens are available
        // to meet pending redemptions
        uint256 tradeSuccess = 7e17;
        uint256 successfulSellAmount = externalTrades[0].sellAmount * tradeSuccess / 1e18;
        claimedAmounts[0] = [externalTrades[0].sellAmount - successfulSellAmount, successfulSellAmount];
        vm.mockCall(
            address(tokenSwapAdapter),
            abi.encodeWithSelector(TokenSwapAdapter.completeTokenSwap.selector),
            abi.encode(claimedAmounts)
        );
        vm.expectCall(basket, abi.encodeWithSelector(BasketToken.fallbackRedeemTrigger.selector));
        basketManager.completeRebalance(externalTrades, baskets, targetWeights);
        assertEq(basketManager.retryCount(), uint256(0));
        assertEq(uint8(basketManager.rebalanceStatus().status), uint8(Status.NOT_STARTED));
    }

    function test_completeRebalance_revertWhen_NoRebalanceInProgress() public {
        vm.expectRevert(BasketManagerUtils.NoRebalanceInProgress.selector);
        basketManager.completeRebalance(new ExternalTrade[](0), new address[](0), new uint64[][](0));
    }

    function test_completeRebalance_revertWhen_BasketsMismatch() public {
        address basket = _setupSingleBasketAndMocks();
        address[] memory targetBaskets = new address[](1);
        targetBaskets[0] = basket;
        uint64[][] memory targetWeights = new uint64[][](1);
        vm.prank(rebalanceProposer);
        basketManager.proposeRebalance(targetBaskets);

        vm.expectRevert(BasketManagerUtils.BasketsMismatch.selector);
        basketManager.completeRebalance(new ExternalTrade[](0), new address[](0), targetWeights);
    }

    function test_completeRebalance_revertWhen_TooEarlyToCompleteRebalance() public {
        address basket = _setupSingleBasketAndMocks();
        address[] memory targetBaskets = new address[](1);
        targetBaskets[0] = basket;
        vm.prank(rebalanceProposer);
        basketManager.proposeRebalance(targetBaskets);

        vm.expectRevert(BasketManagerUtils.TooEarlyToCompleteRebalance.selector);
        basketManager.completeRebalance(new ExternalTrade[](0), targetBaskets, _targetWeights);
    }

    function test_completeRebalance_revertWhen_paused() public {
        address basket = _setupSingleBasketAndMocks();
        address[] memory targetBaskets = new address[](1);
        targetBaskets[0] = basket;
        vm.prank(rebalanceProposer);
        basketManager.proposeRebalance(targetBaskets);

        // Simulate the passage of time
        vm.warp(vm.getBlockTimestamp() + 15 minutes + 1);

        vm.mockCall(basket, abi.encodeCall(BasketToken.totalPendingDeposits, ()), abi.encode(0));
        vm.mockCall(basket, abi.encodeWithSelector(BasketToken.prepareForRebalance.selector), abi.encode(0, 10_000));
        vm.mockCall(basket, abi.encodeCall(IERC20.totalSupply, ()), abi.encode(10_000));
        vm.mockCall(basket, abi.encodeWithSelector(IERC20.approve.selector), abi.encode(true));
        vm.prank(pauser);
        basketManager.pause();
        vm.expectRevert(Pausable.EnforcedPause.selector);
        basketManager.completeRebalance(new ExternalTrade[](0), targetBaskets, _targetWeights);
    }

    function testFuzz_completeRebalance_revertWhen_ExternalTradeMismatch(
        uint256 initialDepositAmount,
        uint256 sellWeight
    )
        public
    {
        _setTokenSwapAdapter();
        initialDepositAmount = bound(initialDepositAmount, 1e4, type(uint256).max / 1e36);
        sellWeight = bound(sellWeight, 0, 1e18);
        (ExternalTrade[] memory trades, address[] memory targetBaskets) =
            testFuzz_proposeTokenSwap_externalTrade(sellWeight, initialDepositAmount);
        address basket = targetBaskets[0];

        // Mock calls for executeTokenSwap
        uint256 numTrades = trades.length;
        bytes32[] memory tradeHashes = new bytes32[](numTrades);
        for (uint8 i = 0; i < numTrades; i++) {
            tradeHashes[i] = keccak256(abi.encode(trades[i]));
        }
        vm.mockCall(
            address(tokenSwapAdapter),
            abi.encodeWithSelector(TokenSwapAdapter.executeTokenSwap.selector),
            abi.encode(tradeHashes)
        );
        // Execute
        vm.prank(tokenswapExecutor);
        basketManager.executeTokenSwap(trades, "");

        // Assert
        assertEq(basketManager.rebalanceStatus().timestamp, vm.getBlockTimestamp());
        assertEq(uint8(basketManager.rebalanceStatus().status), uint8(Status.TOKEN_SWAP_EXECUTED));

        // Simulate the passage of time
        vm.warp(vm.getBlockTimestamp() + 15 minutes + 1);

        vm.mockCall(basket, abi.encodeCall(BasketToken.totalPendingDeposits, ()), abi.encode(0));
        vm.mockCall(basket, abi.encodeWithSelector(BasketToken.prepareForRebalance.selector), abi.encode(0));
        vm.mockCall(basket, abi.encodeWithSelector(BasketToken.fulfillRedeem.selector), new bytes(0));
        vm.mockCall(rootAsset, abi.encodeWithSelector(IERC20.approve.selector), abi.encode(true));
        vm.mockCall(basket, abi.encodeCall(IERC20.totalSupply, ()), abi.encode(initialDepositAmount));
        // Mock results of external trade
        uint256[2][] memory claimedAmounts = new uint256[2][](numTrades);
        // 0 in the 0 index is the result of a 100% successful trade
        claimedAmounts[0] = [0, initialDepositAmount * sellWeight / 1e18];
        vm.mockCall(
            address(tokenSwapAdapter),
            abi.encodeWithSelector(TokenSwapAdapter.completeTokenSwap.selector),
            abi.encode(claimedAmounts)
        );
        vm.expectRevert(BasketManagerUtils.ExternalTradeMismatch.selector);
        basketManager.completeRebalance(new ExternalTrade[](0), targetBaskets, _targetWeights);
    }

    function testFuzz_completeRebalance_retriesWhen_TokenSwapNotExecuted(
        uint256 initialDepositAmount,
        uint256 sellWeight
    )
        public
    {
        _setTokenSwapAdapter();
        initialDepositAmount = bound(initialDepositAmount, 1e4, type(uint256).max / 1e36);
        sellWeight = bound(sellWeight, 1e17, 1e18);
        (ExternalTrade[] memory trades, address[] memory targetBaskets) =
            testFuzz_proposeTokenSwap_externalTrade(sellWeight, initialDepositAmount);
        address basket = targetBaskets[0];

        // Simulate the passage of time
        vm.warp(vm.getBlockTimestamp() + 15 minutes + 1);

        vm.mockCall(basket, abi.encodeCall(BasketToken.totalPendingDeposits, ()), abi.encode(0));
        vm.mockCall(basket, abi.encodeWithSelector(BasketToken.prepareForRebalance.selector), abi.encode(0));
        vm.mockCall(basket, abi.encodeWithSelector(BasketToken.fulfillRedeem.selector), new bytes(0));
        vm.mockCall(rootAsset, abi.encodeWithSelector(IERC20.approve.selector), abi.encode(true));
        vm.mockCall(basket, abi.encodeCall(IERC20.totalSupply, ()), abi.encode(initialDepositAmount));
        basketManager.completeRebalance(trades, targetBaskets, _targetWeights);
        assertEq(basketManager.retryCount(), 1);
        assertEq(uint8(basketManager.rebalanceStatus().status), uint8(Status.REBALANCE_PROPOSED));
    }

    function testFuzz_completeRebalance_passesWhen_TokenSwapNotExecuted_retryLimitReached(
        uint256 initialDepositAmount,
        uint256 sellWeight
    )
        public
    {
        _setTokenSwapAdapter();
        // Setup basket and target weights
        TradeTestParams memory params;
        params.depositAmount = bound(initialDepositAmount, 1e4, type(uint256).max / 1e36);
        params.sellWeight = bound(sellWeight, 1e17, 1e18);
        params.baseAssetWeight = 1e18 - params.sellWeight;
        params.pairAsset = pairAsset;
        address[][] memory basketAssets = new address[][](1);
        basketAssets[0] = new address[](2);
        basketAssets[0][0] = rootAsset;
        basketAssets[0][1] = params.pairAsset;
        uint256[] memory initialDepositAmounts = new uint256[](1);
        initialDepositAmounts[0] = params.depositAmount;
        uint64[][] memory targetWeights = new uint64[][](1);
        targetWeights[0] = new uint64[](2);
        targetWeights[0][0] = uint64(params.baseAssetWeight);
        targetWeights[0][1] = uint64(params.sellWeight);
        address[] memory baskets = _setupBasketsAndMocks(basketAssets, targetWeights, initialDepositAmounts);
        // Propose the rebalance
        vm.prank(rebalanceProposer);
        basketManager.proposeRebalance(baskets);

        for (uint8 i = 0; i < MAX_RETRIES; i++) {
            // 0 for the last input will guarantee the trade will be 100% unsuccessful
            _proposeAndCompleteExternalTrades(baskets, targetWeights, params.depositAmount, params.sellWeight, 0);
            assertEq(basketManager.retryCount(), uint256(i + 1));
            assertEq(uint8(basketManager.rebalanceStatus().status), uint8(Status.REBALANCE_PROPOSED));
        }
        assertEq(basketManager.retryCount(), uint256(MAX_RETRIES));

        // We have reached max retries, if the next proposed token swap does not execute the rebalance
        // will successfully complete.
        ExternalTrade[] memory externalTrades = new ExternalTrade[](1);
        InternalTrade[] memory internalTrades = new InternalTrade[](0);
        BasketTradeOwnership[] memory tradeOwnerships = new BasketTradeOwnership[](1);
        tradeOwnerships[0] = BasketTradeOwnership({ basket: baskets[0], tradeOwnership: uint96(1e18) });
        externalTrades[0] = ExternalTrade({
            sellToken: rootAsset,
            buyToken: params.pairAsset,
            sellAmount: params.depositAmount * params.sellWeight / 1e18,
            minAmount: (params.depositAmount * params.sellWeight / 1e18) * 0.995e18 / 1e18,
            basketTradeOwnership: tradeOwnerships
        });
        vm.prank(tokenswapProposer);
        basketManager.proposeTokenSwap(internalTrades, externalTrades, baskets, targetWeights);
        // Simulate the passage of time
        vm.warp(vm.getBlockTimestamp() + 15 minutes + 1);
        // Token swaps have not been executed
        assertEq(uint8(basketManager.rebalanceStatus().status), uint8(Status.TOKEN_SWAP_PROPOSED));
        basketManager.completeRebalance(externalTrades, baskets, _targetWeights);
        assertEq(basketManager.retryCount(), uint256(0));
        assertEq(uint8(basketManager.rebalanceStatus().status), uint8(Status.NOT_STARTED));
    }

    function testFuzz_completeRebalance_revertWhen_completeTokenSwapFailed(
        uint256 initialDepositAmount,
        uint256 sellWeight
    )
        public
    {
        _setTokenSwapAdapter();
        initialDepositAmount = bound(initialDepositAmount, 1e4, type(uint256).max / 1e36);
        sellWeight = bound(sellWeight, 0, 1e18);
        (ExternalTrade[] memory trades, address[] memory targetBaskets) =
            testFuzz_proposeTokenSwap_externalTrade(sellWeight, initialDepositAmount);
        address basket = targetBaskets[0];

        // Mock calls for executeTokenSwap
        uint256 numTrades = trades.length;
        bytes32[] memory tradeHashes = new bytes32[](numTrades);
        for (uint8 i = 0; i < numTrades; i++) {
            tradeHashes[i] = keccak256(abi.encode(trades[i]));
        }
        vm.mockCall(
            address(tokenSwapAdapter),
            abi.encodeWithSelector(TokenSwapAdapter.executeTokenSwap.selector),
            abi.encode(tradeHashes)
        );
        // Execute
        vm.prank(tokenswapExecutor);
        basketManager.executeTokenSwap(trades, "");

        // Assert
        assertEq(basketManager.rebalanceStatus().timestamp, vm.getBlockTimestamp());
        assertEq(uint8(basketManager.rebalanceStatus().status), uint8(Status.TOKEN_SWAP_EXECUTED));

        // Simulate the passage of time
        vm.warp(vm.getBlockTimestamp() + 15 minutes + 1);

        vm.mockCall(basket, abi.encodeCall(BasketToken.totalPendingDeposits, ()), abi.encode(0));
        vm.mockCall(basket, abi.encodeWithSelector(BasketToken.prepareForRebalance.selector), abi.encode(0));
        vm.mockCall(basket, abi.encodeWithSelector(BasketToken.fulfillRedeem.selector), new bytes(0));
        vm.mockCall(rootAsset, abi.encodeWithSelector(IERC20.approve.selector), abi.encode(true));
        vm.mockCall(basket, abi.encodeCall(IERC20.totalSupply, ()), abi.encode(initialDepositAmount));
        // Mock results of external trade
        uint256[2][] memory claimedAmounts = new uint256[2][](numTrades);
        // 0 in the 1st position is the result of a 100% successful trade
        claimedAmounts[0] = [initialDepositAmount * sellWeight / 1e18, 0];
        vm.mockCallRevert(
            address(tokenSwapAdapter), abi.encodeWithSelector(TokenSwapAdapter.completeTokenSwap.selector), ""
        );
        vm.expectRevert(BasketManagerUtils.CompleteTokenSwapFailed.selector);
        basketManager.completeRebalance(trades, targetBaskets, _targetWeights);
    }

    // TODO: Write a fuzz test that generalizes the number of external trades
    // Currently the test only tests 1 external trades at a time.
    function testFuzz_proposeTokenSwap_externalTrade(
        uint256 sellWeight,
        uint256 depositAmount
    )
        public
        returns (ExternalTrade[] memory, address[] memory)
    {
        // Setup fuzzing bounds
        TradeTestParams memory params;
        params.sellWeight = bound(sellWeight, 0, 1e18);
        // Below bound is due to deposit amount being scaled by price and target weight
        vm.assume(depositAmount < type(uint256).max / 1e36);
        params.depositAmount = depositAmount;
        // With price set at 1e18 this is the threshold for a rebalance to be valid
        vm.assume(params.depositAmount * params.sellWeight / 1e18 > 500);

        // Setup basket and target weights
        params.baseAssetWeight = 1e18 - params.sellWeight;
        params.pairAsset = pairAsset;
        address[][] memory basketAssets = new address[][](1);
        basketAssets[0] = new address[](2);
        basketAssets[0][0] = rootAsset;
        basketAssets[0][1] = params.pairAsset;
        uint256[] memory initialDepositAmounts = new uint256[](1);
        initialDepositAmounts[0] = params.depositAmount;
        uint64[][] memory targetWeights = new uint64[][](1);
        targetWeights[0] = new uint64[](2);
        targetWeights[0][0] = uint64(params.baseAssetWeight);
        targetWeights[0][1] = uint64(params.sellWeight);
        address[] memory baskets = _setupBasketsAndMocks(basketAssets, targetWeights, initialDepositAmounts);

        // Propose the rebalance
        vm.prank(rebalanceProposer);
        basketManager.proposeRebalance(baskets);

        // Setup the trade and propose token swap
        ExternalTrade[] memory externalTrades = new ExternalTrade[](1);
        InternalTrade[] memory internalTrades = new InternalTrade[](0);
        BasketTradeOwnership[] memory tradeOwnerships = new BasketTradeOwnership[](1);
        tradeOwnerships[0] = BasketTradeOwnership({ basket: baskets[0], tradeOwnership: uint96(1e18) });
        externalTrades[0] = ExternalTrade({
            sellToken: rootAsset,
            buyToken: params.pairAsset,
            sellAmount: params.depositAmount * params.sellWeight / 1e18,
            minAmount: (params.depositAmount * params.sellWeight / 1e18) * 0.995e18 / 1e18,
            basketTradeOwnership: tradeOwnerships
        });
        vm.expectEmit();
        emit BasketManager.TokenSwapProposed(basketManager.rebalanceStatus().epoch, internalTrades, externalTrades);
        vm.prank(tokenswapProposer);
        basketManager.proposeTokenSwap(internalTrades, externalTrades, baskets, _targetWeights);

        // Confirm end state
        assertEq(basketManager.rebalanceStatus().timestamp, uint40(vm.getBlockTimestamp()));
        assertEq(uint8(basketManager.rebalanceStatus().status), uint8(Status.TOKEN_SWAP_PROPOSED));
        assertEq(basketManager.externalTradesHash(), keccak256(abi.encode(externalTrades)));
        return (externalTrades, baskets);
    }

    function testFuzz_proposeTokenSwap_revertWhen_externalTrade_ExternalTradeSlippage(
        uint256 sellWeight,
        uint256 depositAmount
    )
        public
    {
        // Setup fuzzing bounds
        TradeTestParams memory params;
        params.sellWeight = bound(sellWeight, 1, 1e18 - 1); // Ensure non-zero sell weight
        params.depositAmount = bound(depositAmount, 1000, type(uint256).max / 1e36); // Ensure non-zero deposit
        vm.assume(params.depositAmount * params.sellWeight / 1e18 > 500);

        // Setup basket and target weights
        params.baseAssetWeight = 1e18 - params.sellWeight;
        params.pairAsset = address(new ERC20Mock());
        _setPrices(params.pairAsset);
        address[][] memory basketAssets = new address[][](1);
        basketAssets[0] = new address[](2);
        basketAssets[0][0] = rootAsset;
        basketAssets[0][1] = params.pairAsset;
        uint256[] memory initialDepositAmounts = new uint256[](1);
        initialDepositAmounts[0] = params.depositAmount;
        uint64[][] memory targetWeights = new uint64[][](1);
        targetWeights[0] = new uint64[](2);
        targetWeights[0][0] = uint64(params.baseAssetWeight);
        targetWeights[0][1] = uint64(params.sellWeight);
        address[] memory baskets = _setupBasketsAndMocks(basketAssets, targetWeights, initialDepositAmounts);

        // Propose the rebalance
        vm.prank(rebalanceProposer);
        basketManager.proposeRebalance(baskets);

        // Setup the trade and propose token swap
        ExternalTrade[] memory externalTrades = new ExternalTrade[](1);
        InternalTrade[] memory internalTrades = new InternalTrade[](0);
        BasketTradeOwnership[] memory tradeOwnerships = new BasketTradeOwnership[](1);
        tradeOwnerships[0] = BasketTradeOwnership({ basket: baskets[0], tradeOwnership: uint96(1e18) });

        uint256 sellAmount = params.depositAmount * params.sellWeight / 1e18;
        uint256 minAmount = sellAmount * 1.06e18 / 1e18; // Set minAmount 6% higher than sellAmount

        externalTrades[0] = ExternalTrade({
            sellToken: rootAsset,
            buyToken: params.pairAsset,
            sellAmount: sellAmount,
            minAmount: minAmount,
            basketTradeOwnership: tradeOwnerships
        });

        vm.prank(tokenswapProposer);
        vm.expectRevert(BasketManagerUtils.ExternalTradeSlippage.selector);
        basketManager.proposeTokenSwap(internalTrades, externalTrades, baskets, _targetWeights);
    }

    // TODO: Write a fuzz test that generalizes the number of internal trades
    function testFuzz_proposeTokenSwap_internalTrade(
        uint256 sellWeight,
        uint256 depositAmount
    )
        public
        returns (address[] memory baskets)
    {
        return testFuzz_proposeTokenSwap_internalTrade(sellWeight, depositAmount, 0);
    }

    function testFuzz_proposeTokenSwap_internalTrade(
        uint256 sellWeight,
        uint256 depositAmount,
        uint16 swapFee
    )
        public
        returns (address[] memory baskets)
    {
        vm.assume(swapFee <= MAX_SWAP_FEE);
        vm.prank(timelock);
        basketManager.setSwapFee(swapFee);
        // Setup fuzzing bounds
        TradeTestParams memory params;
        params.sellWeight = bound(sellWeight, 0, 1e18);
        params.depositAmount = bound(depositAmount, 0, type(uint256).max / 1e36);
        vm.assume(params.depositAmount * params.sellWeight / 1e18 > 500);
        params.baseAssetWeight = 1e18 - params.sellWeight;
        params.pairAsset = pairAsset;
        _setPrices(params.pairAsset);

        // Setup basket and target weights
        {
            address[][] memory basketAssets = new address[][](2);
            basketAssets[0] = new address[](2);
            basketAssets[0][0] = rootAsset;
            basketAssets[0][1] = params.pairAsset;
            basketAssets[1] = new address[](2);
            basketAssets[1][0] = params.pairAsset;
            basketAssets[1][1] = rootAsset;
            uint256[] memory depositAmounts = new uint256[](2);
            depositAmounts[0] = params.depositAmount;
            depositAmounts[1] = params.depositAmount;
            uint64[][] memory initialWeights = new uint64[][](2);
            initialWeights[0] = new uint64[](2);
            initialWeights[0][0] = uint64(params.baseAssetWeight);
            initialWeights[0][1] = uint64(params.sellWeight);
            initialWeights[1] = new uint64[](2);
            initialWeights[1][0] = uint64(params.baseAssetWeight);
            initialWeights[1][1] = uint64(params.sellWeight);
            baskets = _setupBasketsAndMocks(basketAssets, initialWeights, depositAmounts);

            // Propose the rebalance
            vm.prank(rebalanceProposer);
            basketManager.proposeRebalance(baskets);

            // Mimic the intended behavior of processing deposits on proposeRebalance
            ERC20Mock(rootAsset).mint(address(basketManager), params.depositAmount);
            ERC20Mock(params.pairAsset).mint(address(basketManager), params.depositAmount);
        }

        // Setup the trade and propose token swap
        ExternalTrade[] memory externalTrades = new ExternalTrade[](0);
        InternalTrade[] memory internalTrades = new InternalTrade[](1);
        internalTrades[0] = InternalTrade({
            fromBasket: baskets[0],
            sellToken: rootAsset,
            buyToken: params.pairAsset,
            toBasket: baskets[1],
            sellAmount: params.depositAmount * (1e18 - params.baseAssetWeight) / 1e18,
            minAmount: (params.depositAmount * (1e18 - params.baseAssetWeight) / 1e18) * 0.95e18 / 1e18,
            maxAmount: (params.depositAmount * (1e18 - params.baseAssetWeight) / 1e18) * 1.05e18 / 1e18
        });
        uint256 basket0RootAssetBalanceOfBefore = basketManager.basketBalanceOf(baskets[0], rootAsset);
        uint256 basket0PairAssetBalanceOfBefore = basketManager.basketBalanceOf(baskets[0], params.pairAsset);
        uint256 basket1RootAssetBalanceOfBefore = basketManager.basketBalanceOf(baskets[1], rootAsset);
        uint256 basket1PairAssetBalanceOfBefore = basketManager.basketBalanceOf(baskets[1], params.pairAsset);
        vm.expectEmit();
        emit BasketManager.TokenSwapProposed(basketManager.rebalanceStatus().epoch, internalTrades, externalTrades);
        vm.prank(tokenswapProposer);
        basketManager.proposeTokenSwap(internalTrades, externalTrades, baskets, _targetWeights);
        // Confirm end state
        assertEq(basketManager.rebalanceStatus().timestamp, uint40(vm.getBlockTimestamp()));
        assertEq(uint8(basketManager.rebalanceStatus().status), uint8(Status.TOKEN_SWAP_PROPOSED));
        assertEq(basketManager.externalTradesHash(), keccak256(abi.encode(externalTrades)));

        uint256 swapFeeAmount = internalTrades[0].sellAmount.fullMulDiv(swapFee, 2e4);
        uint256 netSellAmount = internalTrades[0].sellAmount - swapFeeAmount;
        uint256 buyAmount = netSellAmount; // Assume 1:1 price
        uint256 netBuyAmount = buyAmount - buyAmount.fullMulDiv(swapFee, 2e4);

        assertEq(
            basketManager.basketBalanceOf(baskets[0], rootAsset),
            basket0RootAssetBalanceOfBefore - internalTrades[0].sellAmount,
            "fromBasket balance of sellToken did not decrease by sellAmount"
        );
        assertEq(
            basketManager.basketBalanceOf(baskets[0], params.pairAsset),
            basket0PairAssetBalanceOfBefore + netBuyAmount,
            "fromBasket balance of buyToken did not increase by netBuyAmount (minus swap fee)"
        );
        assertEq(
            basketManager.basketBalanceOf(baskets[1], rootAsset),
            basket1RootAssetBalanceOfBefore + netSellAmount,
            "toBasket balance of sellToken did not increase by netSellAmount (minus swap fee)"
        );
        assertEq(
            basketManager.basketBalanceOf(baskets[1], params.pairAsset),
            basket1PairAssetBalanceOfBefore - buyAmount,
            "toBasket balance of buyToken did not decrease by buyAmount"
        );
    }

    function testFuzz_proposeTokenSwap_revertWhen_CallerIsNotTokenswapProposer(address caller) public {
        InternalTrade[] memory internalTrades = new InternalTrade[](1);
        ExternalTrade[] memory externalTrades = new ExternalTrade[](1);
        address[] memory targetBaskets = new address[](1);
        uint64[][] memory targetWeights = new uint64[][](1);
        vm.assume(!basketManager.hasRole(TOKENSWAP_PROPOSER_ROLE, caller));
        vm.expectRevert(_formatAccessControlError(caller, TOKENSWAP_PROPOSER_ROLE));
        vm.prank(caller);
        basketManager.proposeTokenSwap(internalTrades, externalTrades, targetBaskets, targetWeights);
    }

    function test_proposeTokenSwap_revertWhen_MustWaitForRebalance() public {
        InternalTrade[] memory internalTrades = new InternalTrade[](1);
        ExternalTrade[] memory externalTrades = new ExternalTrade[](1);
        address[] memory targetBaskets = new address[](1);
        uint64[][] memory targetWeights = new uint64[][](1);
        vm.expectRevert(BasketManagerUtils.MustWaitForRebalanceToComplete.selector);
        vm.prank(tokenswapProposer);
        basketManager.proposeTokenSwap(internalTrades, externalTrades, targetBaskets, targetWeights);
    }

    function test_proposeTokenSwap_revertWhen_BaketMisMatch() public {
        test_proposeRebalance_processesDeposits();
        InternalTrade[] memory internalTrades = new InternalTrade[](1);
        ExternalTrade[] memory externalTrades = new ExternalTrade[](1);
        address[] memory targetBaskets = new address[](1);
        uint64[][] memory targetWeights = new uint64[][](1);
        vm.expectRevert(BasketManagerUtils.BasketsMismatch.selector);
        vm.prank(tokenswapProposer);
        basketManager.proposeTokenSwap(internalTrades, externalTrades, targetBaskets, targetWeights);
    }

    function testFuzz_proposeTokenSwap_revertWhen_internalTradeBasketNotFound(
        uint256 sellWeight,
        uint256 depositAmount,
        address mismatchAssetAddress
    )
        public
    {
        // Setup fuzzing bounds
        TradeTestParams memory params;
        params.sellWeight = bound(sellWeight, 0, 1e18);
        // Below bound is due to deposit amount being scaled by price and target weight
        params.depositAmount = bound(depositAmount, 0, type(uint256).max) / 1e36;
        // With price set at 1e18 this is the threshold for a rebalance to be valid
        vm.assume(params.depositAmount * params.sellWeight / 1e18 > 500);
        vm.assume(mismatchAssetAddress != rootAsset);

        // Setup basket and target weights
        params.baseAssetWeight = 1e18 - params.sellWeight;
        params.pairAsset = address(new ERC20Mock());
        _setPrices(params.pairAsset);
        address[][] memory basketAssets = new address[][](2);
        basketAssets[0] = new address[](2);
        basketAssets[0][0] = rootAsset;
        basketAssets[0][1] = params.pairAsset;
        basketAssets[1] = new address[](2);
        basketAssets[1][0] = params.pairAsset;
        basketAssets[1][1] = rootAsset;
        uint256[] memory initialDepositAmounts = new uint256[](2);
        initialDepositAmounts[0] = params.depositAmount;
        initialDepositAmounts[1] = params.depositAmount;
        uint64[][] memory initialWeights = new uint64[][](2);
        initialWeights[0] = new uint64[](2);
        initialWeights[0][0] = uint64(params.baseAssetWeight);
        initialWeights[0][1] = uint64(params.sellWeight);
        initialWeights[1] = new uint64[](2);
        initialWeights[1][0] = uint64(params.baseAssetWeight);
        initialWeights[1][1] = uint64(params.sellWeight);
        address[] memory baskets = _setupBasketsAndMocks(basketAssets, initialWeights, initialDepositAmounts);
        vm.prank(rebalanceProposer);

        // Propose the rebalance
        basketManager.proposeRebalance(baskets);

        // Setup the trade and propose token swap
        ExternalTrade[] memory externalTrades = new ExternalTrade[](0);
        InternalTrade[] memory internalTrades = new InternalTrade[](1);
        internalTrades[0] = InternalTrade({
            fromBasket: address(1), // add incorrect basket address
            sellToken: rootAsset,
            buyToken: params.pairAsset,
            toBasket: baskets[1],
            sellAmount: params.depositAmount * (1e18 - params.baseAssetWeight) / 1e18,
            minAmount: params.depositAmount * (1e18 - params.baseAssetWeight) / 1e18,
            maxAmount: params.depositAmount * (1e18 - params.baseAssetWeight) / 1e18
        });
        vm.prank(tokenswapProposer);
        vm.expectRevert(BasketManagerUtils.ElementIndexNotFound.selector);
        basketManager.proposeTokenSwap(internalTrades, externalTrades, baskets, _targetWeights);
    }

    function testFuzz_proposeTokenSwap_revertWhen_internalTradeAmmountTooBig(
        uint256 sellWeight,
        uint256 depositAmount,
        uint256 sellAmount
    )
        public
    {
        /// Setup fuzzing bounds
        TradeTestParams memory params;
        params.sellWeight = bound(sellWeight, 0, 1e18);
        params.depositAmount = bound(depositAmount, 0, type(uint256).max / 1e36 - 1);
        sellAmount = bound(sellAmount, 0, type(uint256).max / 1e36 - 1);
        // Minimum deposit amount must be greater than 500 for a rebalance to be valid
        vm.assume(params.depositAmount.fullMulDiv(params.sellWeight, 1e18) > 500);
        params.baseAssetWeight = 1e18 - params.sellWeight;
        params.pairAsset = address(new ERC20Mock());
        _setPrices(params.pairAsset);

        /// Setup basket and target weights
        address[][] memory basketAssets = new address[][](2);
        basketAssets[0] = new address[](2);
        basketAssets[0][0] = rootAsset;
        basketAssets[0][1] = params.pairAsset;
        basketAssets[1] = new address[](2);
        basketAssets[1][0] = params.pairAsset;
        basketAssets[1][1] = rootAsset;
        uint256[] memory depositAmounts = new uint256[](2);
        depositAmounts[0] = params.depositAmount;
        depositAmounts[1] = params.depositAmount - 1;
        uint64[][] memory initialWeights = new uint64[][](2);
        initialWeights[0] = new uint64[](2);
        initialWeights[0][0] = uint64(params.baseAssetWeight);
        initialWeights[0][1] = uint64(params.sellWeight);
        initialWeights[1] = new uint64[](2);
        initialWeights[1][0] = uint64(params.baseAssetWeight);
        initialWeights[1][1] = uint64(params.sellWeight);
        address[] memory baskets = _setupBasketsAndMocks(basketAssets, initialWeights, depositAmounts);

        /// Propose the rebalance
        vm.prank(rebalanceProposer);
        basketManager.proposeRebalance(baskets);

        /// Setup the trade and propose token swap
        ExternalTrade[] memory externalTrades = new ExternalTrade[](0);
        InternalTrade[] memory internalTrades = new InternalTrade[](1);
        // Assume for the case where the sell amount is greater than the balance of the from basket, thus providing
        // invalid input to the function
        vm.assume(sellAmount > basketManager.basketBalanceOf(baskets[0], rootAsset));
        internalTrades[0] = InternalTrade({
            fromBasket: baskets[0],
            sellToken: rootAsset,
            buyToken: params.pairAsset,
            toBasket: baskets[1],
            sellAmount: sellAmount,
            minAmount: 0,
            maxAmount: type(uint256).max
        });
        vm.prank(tokenswapProposer);
        vm.expectRevert(BasketManagerUtils.IncorrectTradeTokenAmount.selector);
        // Assume for the case where the amount bought is greater than the balance of the to basket, thus providing
        // invalid input to the function
        basketManager.proposeTokenSwap(internalTrades, externalTrades, baskets, _targetWeights);
        internalTrades[0] = InternalTrade({
            fromBasket: baskets[0],
            sellToken: rootAsset,
            buyToken: params.pairAsset,
            toBasket: baskets[1],
            sellAmount: basketManager.basketBalanceOf(baskets[0], rootAsset),
            minAmount: 0,
            maxAmount: type(uint256).max
        });
        vm.prank(tokenswapProposer);
        vm.expectRevert(BasketManagerUtils.IncorrectTradeTokenAmount.selector);
        basketManager.proposeTokenSwap(internalTrades, externalTrades, baskets, _targetWeights);
    }

    function testFuzz_proposeTokenSwap_revertWhen_externalTradeBasketNotFound(
        uint256 sellWeight,
        uint256 depositAmount,
        address mismatchAssetAddress
    )
        public
    {
        // Setup fuzzing bounds
        TradeTestParams memory params;
        params.sellWeight = bound(sellWeight, 0, 1e18);
        // Below bound is due to deposit amount being scaled by price and target weight
        params.depositAmount = bound(depositAmount, 0, type(uint256).max) / 1e36;
        // With price set at 1e18 this is the threshold for a rebalance to be valid
        vm.assume(params.depositAmount * params.sellWeight / 1e18 > 500);
        // Setup basket and target weights
        params.baseAssetWeight = 1e18 - params.sellWeight;
        params.pairAsset = address(new ERC20Mock());
        _setPrices(params.pairAsset);
        address[][] memory basketAssets = new address[][](1);
        basketAssets[0] = new address[](2);
        basketAssets[0][0] = rootAsset;
        basketAssets[0][1] = params.pairAsset;
        uint256[] memory initialDepositAmounts = new uint256[](1);
        initialDepositAmounts[0] = params.depositAmount;
        uint64[][] memory targetWeights = new uint64[][](1);
        targetWeights[0] = new uint64[](2);
        targetWeights[0][0] = uint64(params.baseAssetWeight);
        targetWeights[0][1] = uint64(params.sellWeight);
        address[] memory baskets = _setupBasketsAndMocks(basketAssets, targetWeights, initialDepositAmounts);
        vm.assume(mismatchAssetAddress != baskets[0]);

        // Propose the rebalance
        vm.prank(rebalanceProposer);
        basketManager.proposeRebalance(baskets);

        // Setup the trade and propose token swap
        ExternalTrade[] memory externalTrades = new ExternalTrade[](1);
        InternalTrade[] memory internalTrades = new InternalTrade[](0);
        BasketTradeOwnership[] memory tradeOwnerships = new BasketTradeOwnership[](1);
        tradeOwnerships[0] = BasketTradeOwnership({ basket: mismatchAssetAddress, tradeOwnership: uint96(1e18) });
        externalTrades[0] = ExternalTrade({
            sellToken: rootAsset,
            buyToken: params.pairAsset,
            sellAmount: params.depositAmount * params.sellWeight / 1e18,
            minAmount: (params.depositAmount * params.sellWeight / 1e18) * 0.995e18 / 1e18,
            basketTradeOwnership: tradeOwnerships
        });
        vm.prank(tokenswapProposer);
        vm.expectRevert(BasketManagerUtils.ElementIndexNotFound.selector);
        basketManager.proposeTokenSwap(internalTrades, externalTrades, baskets, _targetWeights);
    }

    function testFuzz_proposeTokenSwap_revertWhen_InternalTradeMinMaxAmountNotReached(
        uint256 sellWeight,
        uint256 depositAmount
    )
        public
    {
        // Setup fuzzing bounds
        TradeTestParams memory params;
        params.sellWeight = bound(sellWeight, 0, 1e18);
        // Below bound is due to deposit amount being scaled by price and target weight
        params.depositAmount = bound(depositAmount, 0, type(uint256).max) / 1e36;
        // With price set at 1e18 this is the threshold for a rebalance to be valid
        vm.assume(params.depositAmount * params.sellWeight / 1e18 > 500);

        // Setup basket and target weights
        params.baseAssetWeight = 1e18 - params.sellWeight;
        params.pairAsset = address(new ERC20Mock());
        _setPrices(params.pairAsset);
        address[][] memory basketAssets = new address[][](2);
        basketAssets[0] = new address[](2);
        basketAssets[0][0] = rootAsset;
        basketAssets[0][1] = params.pairAsset;
        basketAssets[1] = new address[](2);
        basketAssets[1][0] = params.pairAsset;
        basketAssets[1][1] = rootAsset;
        uint256[] memory initialDepositAmounts = new uint256[](2);
        initialDepositAmounts[0] = params.depositAmount;
        initialDepositAmounts[1] = params.depositAmount;
        uint64[][] memory initialWeights = new uint64[][](2);
        initialWeights[0] = new uint64[](2);
        initialWeights[0][0] = uint64(params.baseAssetWeight);
        initialWeights[0][1] = uint64(params.sellWeight);
        initialWeights[1] = new uint64[](2);
        initialWeights[1][0] = uint64(params.baseAssetWeight);
        initialWeights[1][1] = uint64(params.sellWeight);
        address[] memory baskets = _setupBasketsAndMocks(basketAssets, initialWeights, initialDepositAmounts);
        vm.prank(rebalanceProposer);

        // Propose the rebalance
        basketManager.proposeRebalance(baskets);

        // Setup the trade and propose token swap
        ExternalTrade[] memory externalTrades = new ExternalTrade[](0);
        InternalTrade[] memory internalTrades = new InternalTrade[](1);
        internalTrades[0] = InternalTrade({
            fromBasket: baskets[0],
            sellToken: rootAsset,
            buyToken: params.pairAsset,
            toBasket: baskets[1],
            sellAmount: params.depositAmount * (1e18 - params.baseAssetWeight) / 1e18,
            minAmount: params.depositAmount * (1e18 - params.baseAssetWeight) / 1e18 + 1,
            maxAmount: params.depositAmount * (1e18 - params.baseAssetWeight) / 1e18
        });
        vm.prank(tokenswapProposer);
        vm.expectRevert(BasketManagerUtils.InternalTradeMinMaxAmountNotReached.selector);
        basketManager.proposeTokenSwap(internalTrades, externalTrades, baskets, _targetWeights);
    }

    function testFuzz_proposeTokenSwap_internalTrade_revertWhen_TargetWeightsNotMet(
        uint256 sellWeight,
        uint256 depositAmount,
        uint256 deviation
    )
        public
    {
        uint256 max_weight_deviation = 0.05e18 + 1;
        /// Setup fuzzing bounds
        TradeTestParams memory params;
        params.sellWeight = bound(sellWeight, 0, 1e18 - max_weight_deviation);
        params.depositAmount = bound(depositAmount, 0, type(uint256).max / 1e36);
        vm.assume(params.depositAmount.fullMulDiv(params.sellWeight, 1e18) > 500);
        params.baseAssetWeight = 1e18 - params.sellWeight;
        deviation = bound(deviation, max_weight_deviation, params.baseAssetWeight);
        vm.assume(params.baseAssetWeight + deviation < 1e18);
        params.pairAsset = address(new ERC20Mock());
        _setPrices(params.pairAsset);

        // Setup basket and target weights
        address[][] memory basketAssets = new address[][](2);
        basketAssets[0] = new address[](2);
        basketAssets[0][0] = rootAsset;
        basketAssets[0][1] = params.pairAsset;
        basketAssets[1] = new address[](2);
        basketAssets[1][0] = params.pairAsset;
        basketAssets[1][1] = rootAsset;
        uint256[] memory depositAmounts = new uint256[](2);
        depositAmounts[0] = params.depositAmount;
        depositAmounts[1] = params.depositAmount;
        uint64[][] memory initialWeights = new uint64[][](2);
        initialWeights[0] = new uint64[](2);
        initialWeights[0][0] = uint64(params.baseAssetWeight);
        initialWeights[0][1] = uint64(params.sellWeight);
        initialWeights[1] = new uint64[](2);
        initialWeights[1][0] = uint64(params.baseAssetWeight);
        initialWeights[1][1] = uint64(params.sellWeight);
        address[] memory baskets = _setupBasketsAndMocks(basketAssets, initialWeights, depositAmounts);

        // Propose the rebalance
        vm.prank(rebalanceProposer);
        basketManager.proposeRebalance(baskets);

        // Setup the trade and propose token swap
        ExternalTrade[] memory externalTrades = new ExternalTrade[](0);
        InternalTrade[] memory internalTrades = new InternalTrade[](1);
        uint256 deviatedTradeAmount = params.depositAmount.fullMulDiv(1e18 - params.baseAssetWeight - deviation, 1e18);
        internalTrades[0] = InternalTrade({
            fromBasket: baskets[0],
            sellToken: rootAsset,
            buyToken: params.pairAsset,
            toBasket: baskets[1],
            sellAmount: deviatedTradeAmount,
            minAmount: deviatedTradeAmount.fullMulDiv(0.995e18, 1e18),
            maxAmount: deviatedTradeAmount.fullMulDiv(1.005e18, 1e18)
        });
        vm.prank(tokenswapProposer);
        vm.expectRevert(BasketManagerUtils.TargetWeightsNotMet.selector);
        basketManager.proposeTokenSwap(internalTrades, externalTrades, baskets, _targetWeights);
    }

    function testFuzz_proposeTokenSwap_revertWhen_assetNotInBasket(uint256 sellWeight, uint256 depositAmount) public {
        // Setup fuzzing bounds
        TradeTestParams memory params;
        params.sellWeight = bound(sellWeight, 0, 1e18);
        // Below bound is due to deposit amount being scaled by price and target weight
        params.depositAmount = bound(depositAmount, 0, type(uint256).max) / 1e36;
        // With price set at 1e18 this is the threshold for a rebalance to be valid
        vm.assume(params.depositAmount * params.sellWeight / 1e18 > 500);

        // Setup basket and target weights
        params.baseAssetWeight = 1e18 - params.sellWeight;
        params.pairAsset = address(new ERC20Mock());
        _setPrices(params.pairAsset);
        address[][] memory basketAssets = new address[][](2);
        basketAssets[0] = new address[](2);
        basketAssets[0][0] = rootAsset;
        basketAssets[0][1] = params.pairAsset;
        basketAssets[1] = new address[](2);
        basketAssets[1][0] = params.pairAsset;
        basketAssets[1][1] = rootAsset;
        uint256[] memory initialDepositAmounts = new uint256[](2);
        initialDepositAmounts[0] = params.depositAmount;
        initialDepositAmounts[1] = params.depositAmount;
        uint64[][] memory initialWeights = new uint64[][](2);
        initialWeights[0] = new uint64[](2);
        initialWeights[0][0] = uint64(params.baseAssetWeight);
        initialWeights[0][1] = uint64(params.sellWeight);
        initialWeights[1] = new uint64[](2);
        initialWeights[1][0] = uint64(params.baseAssetWeight);
        initialWeights[1][1] = uint64(params.sellWeight);
        address[] memory baskets = _setupBasketsAndMocks(basketAssets, initialWeights, initialDepositAmounts);

        // Propose the rebalance
        vm.prank(rebalanceProposer);
        basketManager.proposeRebalance(baskets);

        // Setup the trade and propose token swap
        ExternalTrade[] memory externalTrades = new ExternalTrade[](0);
        InternalTrade[] memory internalTrades = new InternalTrade[](1);
        internalTrades[0] = InternalTrade({
            fromBasket: baskets[0],
            sellToken: address(new ERC20Mock()),
            buyToken: params.pairAsset,
            toBasket: baskets[1],
            sellAmount: params.depositAmount * (1e18 - params.baseAssetWeight) / 1e18,
            minAmount: (params.depositAmount * (1e18 - params.baseAssetWeight) / 1e18) * 0.995e18 / 1e18,
            maxAmount: (params.depositAmount * (1e18 - params.baseAssetWeight) / 1e18) * 1.005e18 / 1e18
        });
        vm.prank(tokenswapProposer);
        vm.expectRevert(BasketManagerUtils.AssetNotFoundInBasket.selector);
        basketManager.proposeTokenSwap(internalTrades, externalTrades, baskets, _targetWeights);
    }

    function test_proposeTokenSwap_revertWhen_Paused() public {
        InternalTrade[] memory internalTrades = new InternalTrade[](1);
        ExternalTrade[] memory externalTrades = new ExternalTrade[](1);
        address[] memory targetBaskets = new address[](1);
        uint64[][] memory targetWeights = new uint64[][](1);
        vm.prank(pauser);
        basketManager.pause();
        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(tokenswapProposer);
        basketManager.proposeTokenSwap(internalTrades, externalTrades, targetBaskets, targetWeights);
    }

    function testFuzz_executeTokenSwap_revertWhen_CallerIsNotTokenswapExecutor(
        address caller,
        ExternalTrade[] calldata trades,
        bytes calldata data
    )
        public
    {
        _setTokenSwapAdapter();
        vm.assume(!basketManager.hasRole(TOKENSWAP_EXECUTOR_ROLE, caller));
        vm.expectRevert(_formatAccessControlError(caller, TOKENSWAP_EXECUTOR_ROLE));
        vm.prank(caller);
        basketManager.executeTokenSwap(trades, data);
    }

    function testFuzz_executeTokenSwap_revertWhen_Paused(ExternalTrade[] calldata trades, bytes calldata data) public {
        _setTokenSwapAdapter();
        vm.prank(pauser);
        basketManager.pause();
        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(tokenswapExecutor);
        basketManager.executeTokenSwap(trades, data);
    }

    function testFuzz_proposeTokenSwap_externalTrade_revertWhen_AmountsIncorrect(
        uint256 sellWeight,
        uint256 depositAmount,
        uint256 sellAmount
    )
        public
    {
        /// Setup fuzzing bounds
        TradeTestParams memory params;
        params.sellWeight = bound(sellWeight, 0, 1e18);
        // Below bound is due to deposit amount being scaled by price and target weight
        params.depositAmount = bound(depositAmount, 0, type(uint256).max) / 1e36;
        // With price set at 1e18 this is the threshold for a rebalance to be valid
        vm.assume(params.depositAmount.fullMulDiv(params.sellWeight, 1e18) > 500);

        /// Setup basket and target weights
        params.baseAssetWeight = 1e18 - params.sellWeight;
        params.pairAsset = address(new ERC20Mock());
        _setPrices(params.pairAsset);
        address[][] memory basketAssets = new address[][](1);
        basketAssets[0] = new address[](2);
        basketAssets[0][0] = rootAsset;
        basketAssets[0][1] = params.pairAsset;
        uint256[] memory initialDepositAmounts = new uint256[](1);
        initialDepositAmounts[0] = params.depositAmount;
        uint64[][] memory targetWeights = new uint64[][](1);
        targetWeights[0] = new uint64[](2);
        targetWeights[0][0] = uint64(params.baseAssetWeight);
        targetWeights[0][1] = uint64(params.sellWeight);
        address[] memory baskets = _setupBasketsAndMocks(basketAssets, targetWeights, initialDepositAmounts);

        /// Propose the rebalance
        vm.prank(rebalanceProposer);
        basketManager.proposeRebalance(baskets);

        /// Setup the trade and propose token swap
        ExternalTrade[] memory externalTrades = new ExternalTrade[](1);
        InternalTrade[] memory internalTrades = new InternalTrade[](0);
        BasketTradeOwnership[] memory tradeOwnerships = new BasketTradeOwnership[](1);
        vm.assume(sellAmount > basketManager.basketBalanceOf(baskets[0], rootAsset));
        tradeOwnerships[0] = BasketTradeOwnership({ basket: baskets[0], tradeOwnership: uint96(1e18) });
        externalTrades[0] = ExternalTrade({
            sellToken: rootAsset,
            buyToken: params.pairAsset,
            sellAmount: sellAmount,
            minAmount: sellAmount.fullMulDiv(0.995e18, 1e18),
            basketTradeOwnership: tradeOwnerships
        });
        vm.prank(tokenswapProposer);
        vm.expectRevert(BasketManagerUtils.IncorrectTradeTokenAmount.selector);
        basketManager.proposeTokenSwap(internalTrades, externalTrades, baskets, _targetWeights);
    }

    function testFuzz_proposeTokenSwap_externalTrade_revertWhen_TargetWeightsNotMet(
        uint256 sellWeight,
        uint256 depositAmount,
        uint256 deviation
    )
        public
    {
        /// Setup fuzzing bounds
        uint256 max_weight_deviation = 0.05e18 + 1;
        TradeTestParams memory params;
        params.sellWeight = bound(sellWeight, 0, 1e18 - max_weight_deviation);
        params.depositAmount = bound(depositAmount, 1e18, type(uint256).max) / 1e36;
        vm.assume(params.depositAmount.fullMulDiv(params.sellWeight, 1e18) > 500);
        params.baseAssetWeight = 1e18 - params.sellWeight;
        deviation = bound(deviation, max_weight_deviation, params.baseAssetWeight);
        vm.assume(params.baseAssetWeight + deviation < 1e18);
        params.pairAsset = address(new ERC20Mock());
        _setPrices(params.pairAsset);

        /// Setup basket and target weights
        address[][] memory basketAssets = new address[][](1);
        basketAssets[0] = new address[](2);
        basketAssets[0][0] = rootAsset;
        basketAssets[0][1] = params.pairAsset;
        uint64[][] memory weightsPerBasket = new uint64[][](1);
        // Deviate from the target weights
        weightsPerBasket[0] = new uint64[](2);
        weightsPerBasket[0][0] = uint64(params.baseAssetWeight);
        weightsPerBasket[0][1] = uint64(params.sellWeight);
        uint256[] memory initialDepositAmounts = new uint256[](1);
        initialDepositAmounts[0] = params.depositAmount;
        address[] memory baskets = _setupBasketsAndMocks(basketAssets, weightsPerBasket, initialDepositAmounts);

        /// Propose the rebalance
        vm.prank(rebalanceProposer);
        basketManager.proposeRebalance(baskets);

        /// Setup the trade and propose token swap
        ExternalTrade[] memory externalTrades = new ExternalTrade[](1);
        InternalTrade[] memory internalTrades = new InternalTrade[](0);
        BasketTradeOwnership[] memory tradeOwnerships = new BasketTradeOwnership[](1);
        tradeOwnerships[0] = BasketTradeOwnership({ basket: baskets[0], tradeOwnership: uint96(1e18) });
        uint256 deviatedTradeAmount = params.depositAmount.fullMulDiv(1e18 - params.baseAssetWeight - deviation, 1e18);
        externalTrades[0] = ExternalTrade({
            sellToken: rootAsset,
            buyToken: params.pairAsset,
            sellAmount: deviatedTradeAmount,
            minAmount: deviatedTradeAmount.fullMulDiv(0.995e18, 1e18),
            basketTradeOwnership: tradeOwnerships
        });
        vm.prank(tokenswapProposer);
        vm.expectRevert(BasketManagerUtils.TargetWeightsNotMet.selector);
        basketManager.proposeTokenSwap(internalTrades, externalTrades, baskets, _targetWeights);
    }

    function testFuzz_completeRebalance_internalTrade(
        uint256 initialSplit,
        uint256 depositAmount,
        uint16 swapFee
    )
        public
    {
        depositAmount = bound(depositAmount, 500e18, type(uint128).max);
        initialSplit = bound(initialSplit, 1, 1e18 - 1);
        address[] memory targetBaskets = testFuzz_proposeTokenSwap_internalTrade(initialSplit, depositAmount, swapFee);
        address basket = targetBaskets[0];

        // Simulate the passage of time
        vm.warp(vm.getBlockTimestamp() + 15 minutes + 1);

        vm.mockCall(basket, abi.encodeCall(BasketToken.totalPendingDeposits, ()), abi.encode(0));
        vm.mockCall(basket, abi.encodeWithSelector(BasketToken.prepareForRebalance.selector), abi.encode(0));
        vm.mockCall(basket, abi.encodeWithSelector(BasketToken.fulfillRedeem.selector), new bytes(0));
        vm.mockCall(rootAsset, abi.encodeWithSelector(IERC20.approve.selector), abi.encode(true));
        vm.mockCall(basket, abi.encodeCall(IERC20.totalSupply, ()), abi.encode(depositAmount));
        basketManager.completeRebalance(new ExternalTrade[](0), targetBaskets, _targetWeights);
    }

    function testFuzz_proRataRedeem(
        uint256 initialSplit,
        uint256 depositAmount,
        uint256 burnedShares,
        uint16 swapFee
    )
        public
    {
        depositAmount = bound(depositAmount, 500e18, type(uint128).max);
        burnedShares = bound(burnedShares, 1, depositAmount);
        initialSplit = bound(initialSplit, 1, 1e18 - 1);
        testFuzz_completeRebalance_internalTrade(initialSplit, depositAmount, swapFee);

        // Redeem some shares from 0th basket
        address basket = basketManager.basketTokens()[0];
        uint256 totalSupplyBefore = depositAmount; // Assume price of share == price of deposit token

        uint256 asset0balance = basketManager.basketBalanceOf(basket, rootAsset);
        uint256 asset1balance = basketManager.basketBalanceOf(basket, pairAsset);
        vm.prank(basket);
        basketManager.proRataRedeem(totalSupplyBefore, burnedShares, address(this));
        assertEq(IERC20(rootAsset).balanceOf(address(this)), asset0balance.fullMulDiv(burnedShares, totalSupplyBefore));
        assertEq(IERC20(pairAsset).balanceOf(address(this)), asset1balance.fullMulDiv(burnedShares, totalSupplyBefore));
    }

    function testFuzz_proRataRedeem_passWhen_otherBasketRebalancing(uint256 initialDepositAmount) public {
        initialDepositAmount = bound(initialDepositAmount, 1e4, type(uint256).max / 1e36);
        // Create two baskets
        address[][] memory assetsPerBasket = new address[][](2);
        assetsPerBasket[0] = new address[](2);
        assetsPerBasket[0][0] = rootAsset;
        assetsPerBasket[0][1] = pairAsset;
        assetsPerBasket[1] = new address[](2);
        assetsPerBasket[1][0] = address(1);
        assetsPerBasket[1][1] = address(2);
        uint64[][] memory weightsPerBasket = new uint64[][](2);
        weightsPerBasket[0] = new uint64[](2);
        weightsPerBasket[0][0] = 1e18;
        weightsPerBasket[0][1] = 0;
        weightsPerBasket[1] = new uint64[](2);
        weightsPerBasket[1][0] = 1e18;
        weightsPerBasket[1][1] = 0;
        uint256[] memory initialDepositAmounts = new uint256[](2);
        initialDepositAmounts[0] = initialDepositAmount;
        initialDepositAmounts[1] = initialDepositAmount;
        // Below deposits into both baskets
        address[] memory baskets = _setupBasketsAndMocks(assetsPerBasket, weightsPerBasket, initialDepositAmounts);
        address rebalancingBasket = baskets[0];
        address nonRebalancingBasket = baskets[1];
        // Rebalance with only one basket
        address[] memory targetBaskets = new address[](1);
        targetBaskets[0] = rebalancingBasket;
        vm.prank(rebalanceProposer);
        basketManager.proposeRebalance(targetBaskets);
        // Redeem some half of the shares from non-rebalancing basket
        uint256 totalSupplyBefore = initialDepositAmount; // Assume price of share == price of deposit token
        uint256 burnedShares = initialDepositAmount / 2;
        uint256 asset0balance = basketManager.basketBalanceOf(nonRebalancingBasket, rootAsset);
        uint256 asset1balance = basketManager.basketBalanceOf(nonRebalancingBasket, pairAsset);
        vm.prank(nonRebalancingBasket);
        basketManager.proRataRedeem(totalSupplyBefore, burnedShares, address(this));
        assertEq(IERC20(rootAsset).balanceOf(address(this)), asset0balance.fullMulDiv(burnedShares, totalSupplyBefore));
        assertEq(IERC20(pairAsset).balanceOf(address(this)), asset1balance.fullMulDiv(burnedShares, totalSupplyBefore));
    }

    function test_proRataRedeem_revertWhen_CannotBurnMoreSharesThanTotalSupply(
        uint256 initialSplit,
        uint256 depositAmount,
        uint16 swapFee
    )
        public
    {
        depositAmount = bound(depositAmount, 500e18, type(uint128).max);
        initialSplit = bound(initialSplit, 1, 1e18 - 1);
        testFuzz_completeRebalance_internalTrade(initialSplit, depositAmount, swapFee);

        // Redeem some shares
        address basket = basketManager.basketTokens()[0];
        vm.expectRevert(BasketManagerUtils.CannotBurnMoreSharesThanTotalSupply.selector);
        vm.prank(basket);
        basketManager.proRataRedeem(depositAmount, depositAmount + 1, address(this));
    }

    function test_proRataRedeem_revertWhen_CallerIsNotBasketToken() public {
        vm.expectRevert(_formatAccessControlError(address(this), BASKET_TOKEN_ROLE));
        basketManager.proRataRedeem(0, 0, address(0));
    }

    function test_proRataRedeem_revertWhen_ZeroTotalSupply() public {
        address basket = _setupSingleBasketAndMocks();
        vm.expectRevert(BasketManagerUtils.ZeroTotalSupply.selector);
        vm.prank(basket);
        basketManager.proRataRedeem(0, 0, address(0));
    }

    function test_proRataRedeem_revertWhen_ZeroBurnedShares() public {
        address basket = _setupSingleBasketAndMocks();
        vm.mockCall(basket, abi.encodeCall(IERC20.totalSupply, ()), abi.encode(10_000));
        vm.expectRevert(BasketManagerUtils.ZeroBurnedShares.selector);
        vm.prank(basket);
        basketManager.proRataRedeem(1, 0, address(this));
    }

    function test_proRataRedeem_revertWhen_ZeroAddress() public {
        address basket = _setupSingleBasketAndMocks();
        vm.mockCall(basket, abi.encodeCall(IERC20.totalSupply, ()), abi.encode(10_000));
        vm.expectRevert(Errors.ZeroAddress.selector);
        vm.prank(basket);
        basketManager.proRataRedeem(1, 1, address(0));
    }

    function test_proRataRedeem_revertWhen_MustWaitForRebalanceToComplete() public {
        address basket = _setupSingleBasketAndMocks();
        address[] memory targetBaskets = new address[](1);
        targetBaskets[0] = basket;
        vm.prank(rebalanceProposer);
        basketManager.proposeRebalance(targetBaskets);

        vm.expectRevert(BasketManagerUtils.MustWaitForRebalanceToComplete.selector);
        vm.prank(basket);
        basketManager.proRataRedeem(1, 1, address(this));
    }

    function test_proRataRedeem_revertWhen_Paused() public {
        address basket = _setupSingleBasketAndMocks();
        address[] memory targetBaskets = new address[](1);
        targetBaskets[0] = basket;
        vm.prank(pauser);
        basketManager.pause();
        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(basket);
        basketManager.proRataRedeem(0, 0, address(0));
    }

    function testFuzz_setTokenSwapAdapter(address newTokenSwapAdapter) public {
        vm.assume(newTokenSwapAdapter != address(0));
        vm.prank(timelock);
        basketManager.setTokenSwapAdapter(newTokenSwapAdapter);
        assertEq(basketManager.tokenSwapAdapter(), newTokenSwapAdapter);
    }

    function test_setTokenSwapAdapter_revertWhen_ZeroAddress() public {
        vm.expectRevert(Errors.ZeroAddress.selector);
        vm.prank(timelock);
        basketManager.setTokenSwapAdapter(address(0));
    }

    function test_setTokenSwapAdapter_revertWhen_CalledByNonTimelock() public {
        vm.expectRevert(_formatAccessControlError(address(this), TIMELOCK_ROLE));
        vm.prank(address(this));
        basketManager.setTokenSwapAdapter(address(0));
    }

    function testFuzz_setTokenSwapAdapter_revertWhen_MustWaitForRebalanceToComplete(address newSwapAdapter) public {
        vm.assume(newSwapAdapter != address(0));
        test_proposeRebalance_processesDeposits();
        vm.expectRevert(BasketManager.MustWaitForRebalanceToComplete.selector);
        vm.prank(timelock);
        basketManager.setTokenSwapAdapter(newSwapAdapter);
    }

    function testFuzz_executeTokenSwap(uint256 sellWeight, uint256 depositAmount) public {
        _setTokenSwapAdapter();
        (ExternalTrade[] memory trades,) = testFuzz_proposeTokenSwap_externalTrade(sellWeight, depositAmount);

        // Mock calls
        uint256 numTrades = trades.length;
        bytes32[] memory tradeHashes = new bytes32[](numTrades);
        for (uint8 i = 0; i < numTrades; i++) {
            tradeHashes[i] = keccak256(abi.encode(trades[i]));
        }
        vm.mockCall(
            address(tokenSwapAdapter),
            abi.encodeWithSelector(TokenSwapAdapter.executeTokenSwap.selector),
            abi.encode(tradeHashes)
        );
        // Execute
        vm.prank(tokenswapExecutor);
        basketManager.executeTokenSwap(trades, "");

        // Assert
        assertEq(basketManager.rebalanceStatus().timestamp, vm.getBlockTimestamp());
        assertEq(uint8(basketManager.rebalanceStatus().status), uint8(Status.TOKEN_SWAP_EXECUTED));
    }

    function testFuzz_executeTokenSwap_revertWhen_ExecuteTokenSwapFailed(
        uint256 sellWeight,
        uint256 depositAmount
    )
        public
    {
        _setTokenSwapAdapter();
        (ExternalTrade[] memory trades,) = testFuzz_proposeTokenSwap_externalTrade(sellWeight, depositAmount);

        // Mock calls
        uint256 numTrades = trades.length;
        bytes32[] memory tradeHashes = new bytes32[](numTrades);
        for (uint8 i = 0; i < numTrades; i++) {
            tradeHashes[i] = keccak256(abi.encode(trades[i]));
        }
        vm.mockCallRevert(
            address(tokenSwapAdapter), abi.encodeWithSelector(TokenSwapAdapter.executeTokenSwap.selector), ""
        );
        // Execute
        vm.prank(tokenswapExecutor);
        vm.expectRevert(BasketManager.ExecuteTokenSwapFailed.selector);
        basketManager.executeTokenSwap(trades, "");
    }

    function testFuzz_executeTokenSwap_revertWhen_ExternalTradesHashMismatch(
        uint256 sellWeight,
        uint256 depositAmount,
        ExternalTrade[] memory badTrades
    )
        public
    {
        _setTokenSwapAdapter();
        (ExternalTrade[] memory trades,) = testFuzz_proposeTokenSwap_externalTrade(sellWeight, depositAmount);
        vm.assume(keccak256(abi.encode(badTrades)) != keccak256(abi.encode(trades)));

        // Execute
        vm.expectRevert(BasketManager.ExternalTradesHashMismatch.selector);
        vm.prank(tokenswapExecutor);
        basketManager.executeTokenSwap(badTrades, "");
    }

    function testFuzz_executeTokenSwap_revertWhen_TokenSwapNotProposed(ExternalTrade[] memory trades) public {
        _setTokenSwapAdapter();
        vm.expectRevert(BasketManager.TokenSwapNotProposed.selector);
        vm.prank(tokenswapExecutor);
        basketManager.executeTokenSwap(trades, "");
    }

    function testFuzz_executeTokenSwap_revertWhen_ZeroAddress(uint256 sellWeight, uint256 depositAmount) public {
        (ExternalTrade[] memory trades,) = testFuzz_proposeTokenSwap_externalTrade(sellWeight, depositAmount);

        // Execute
        vm.expectRevert(Errors.ZeroAddress.selector);
        vm.prank(tokenswapExecutor);
        basketManager.executeTokenSwap(trades, "");
    }

    function testFuzz_setManagementFee(uint16 fee) public {
        vm.assume(fee <= MAX_MANAGEMENT_FEE);
        address basket = _setupSingleBasketAndMocks();
        vm.prank(timelock);
        basketManager.setManagementFee(basket, fee);
        assertEq(basketManager.managementFee(basket), fee);
    }

    function testFuzz_setManagementFee_passesWhen_otherBasketRebalancing(
        uint256 initialDepositAmount,
        uint16 fee
    )
        public
    {
        vm.assume(fee <= MAX_MANAGEMENT_FEE);
        initialDepositAmount = bound(initialDepositAmount, 1e4, type(uint256).max / 1e36);
        // Create two baskets
        address[][] memory assetsPerBasket = new address[][](2);
        assetsPerBasket[0] = new address[](2);
        assetsPerBasket[0][0] = rootAsset;
        assetsPerBasket[0][1] = pairAsset;
        assetsPerBasket[1] = new address[](2);
        assetsPerBasket[1][0] = address(1);
        assetsPerBasket[1][1] = address(2);
        uint64[][] memory weightsPerBasket = new uint64[][](2);
        weightsPerBasket[0] = new uint64[](2);
        weightsPerBasket[0][0] = 1e18;
        weightsPerBasket[0][1] = 0;
        weightsPerBasket[1] = new uint64[](2);
        weightsPerBasket[1][0] = 1e18;
        weightsPerBasket[1][1] = 0;
        uint256[] memory initialDepositAmounts = new uint256[](2);
        initialDepositAmounts[0] = initialDepositAmount;
        initialDepositAmounts[1] = initialDepositAmount;
        // Below deposits into both baskets
        address[] memory baskets = _setupBasketsAndMocks(assetsPerBasket, weightsPerBasket, initialDepositAmounts);
        address rebalancingBasket = baskets[0];
        address nonRebalancingBasket = baskets[1];
        // Rebalance with only one basket
        address[] memory targetBaskets = new address[](1);
        targetBaskets[0] = rebalancingBasket;
        vm.prank(rebalanceProposer);
        basketManager.proposeRebalance(targetBaskets);
        vm.prank(timelock);
        basketManager.setManagementFee(nonRebalancingBasket, fee);
    }

    function testFuzz_setManagementFee_revertsWhen_calledByNonTimelock(address caller) public {
        vm.assume(caller != timelock);
        address basket = _setupSingleBasketAndMocks();
        vm.assume(basket != address(0));
        vm.expectRevert(_formatAccessControlError(caller, TIMELOCK_ROLE));
        vm.prank(caller);
        basketManager.setManagementFee(basket, 10);
    }

    function testFuzz_setManagementFee_revertWhen_invalidManagementFee(address basket, uint16 fee) public {
        vm.assume(fee > MAX_MANAGEMENT_FEE);
        vm.assume(basket != address(0));
        vm.expectRevert(BasketManager.InvalidManagementFee.selector);
        vm.prank(timelock);
        basketManager.setManagementFee(basket, fee);
    }

    function testFuzz_setManagementFee_revertWhen_MustWaitForRebalanceToComplete(uint16 fee) public {
        vm.assume(fee <= MAX_MANAGEMENT_FEE);
        address basket = test_proposeRebalance_processesDeposits();
        vm.expectRevert(BasketManagerUtils.MustWaitForRebalanceToComplete.selector);
        vm.prank(timelock);
        basketManager.setManagementFee(basket, fee);
    }

    function testFuzz_setManagementFee_revertWhen_basketTokenNotFound(address basket) public {
        vm.assume(basket != address(0));
        vm.expectRevert(BasketManagerUtils.BasketTokenNotFound.selector);
        vm.prank(timelock);
        basketManager.setManagementFee(basket, 0);
    }

    function testFuzz_setSwapFee(uint16 fee) public {
        vm.assume(fee <= MAX_SWAP_FEE);
        vm.prank(timelock);
        basketManager.setSwapFee(fee);
        assertEq(basketManager.swapFee(), fee, "swapFee() returned unexpected value");
    }

    function testFuzz_setSwapFee_revertsWhen_calledByNonTimelock(address caller, uint16 fee) public {
        vm.assume(caller != timelock);
        vm.assume(fee <= MAX_SWAP_FEE);
        vm.expectRevert(_formatAccessControlError(caller, TIMELOCK_ROLE));
        vm.prank(caller);
        basketManager.setSwapFee(fee);
    }

    function testFuzz_setSwapFee_revertWhen_invalidSwapFee(uint16 fee) public {
        vm.assume(fee > MAX_SWAP_FEE);
        vm.expectRevert(BasketManager.InvalidSwapFee.selector);
        vm.prank(timelock);
        basketManager.setSwapFee(fee);
    }

    function testFuzz_setSwapFee_revertWhen_MustWaitForRebalanceToComplete(uint16 fee) public {
        vm.assume(fee <= MAX_SWAP_FEE);
        test_proposeRebalance_processesDeposits();
        vm.expectRevert(BasketManagerUtils.MustWaitForRebalanceToComplete.selector);
        vm.prank(timelock);
        basketManager.setSwapFee(fee);
    }

    function testFuzz_collectSwapFee_revertWhen_calledByNonManager(address caller, address asset) public {
        vm.assume(caller != manager);
        vm.expectRevert(_formatAccessControlError(caller, MANAGER_ROLE));
        vm.prank(caller);
        basketManager.collectSwapFee(asset);
    }

    function testFuzz_collectSwapFee_returnsZeroWhen_hasNotCollectedFee(address asset) public {
        vm.prank(manager);
        assertEq(basketManager.collectSwapFee(asset), 0, "collectSwapFee() returned non-zero value");
    }

    function testFuzz_collectSwapFee(uint256 initialSplit, uint256 depositAmount, uint16 fee) public {
        // below test includes a call basketManager.setSwapFee(fee)
        testFuzz_completeRebalance_internalTrade(initialSplit, depositAmount, fee);
        vm.startPrank(manager);
        uint256 rootAssetFee = basketManager.collectSwapFee(rootAsset);
        uint256 pairAssetFee = basketManager.collectSwapFee(pairAsset);
        vm.stopPrank();
        assertEq(rootAssetFee, IERC20(rootAsset).balanceOf(protocolTreasury));
        assertEq(pairAssetFee, IERC20(pairAsset).balanceOf(protocolTreasury));
    }

    function testFuzz_updateBitFlag(uint256 newBitFlag) public {
        address basket = _setupSingleBasketAndMocks();
        uint256 currentBitFlag = BasketToken(basket).bitFlag();
        vm.assume((currentBitFlag & newBitFlag) == currentBitFlag);
        vm.assume(currentBitFlag != newBitFlag);

        address strategy = BasketToken(basket).strategy();
        vm.mockCall(strategy, abi.encodeCall(WeightStrategy.supportsBitFlag, (newBitFlag)), abi.encode(true));
        address[] memory newAssets = new address[](5);
        for (uint256 i = 0; i < 5; i++) {
            newAssets[i] = address(uint160(uint160(rootAsset) + i));
        }
        vm.mockCall(
            address(assetRegistry), abi.encodeCall(AssetRegistry.getAssets, (newBitFlag)), abi.encode(newAssets)
        );
        vm.mockCall(basket, abi.encodeCall(BasketToken.setBitFlag, (newBitFlag)), "");

        bytes32 oldBasketId = keccak256(abi.encodePacked(currentBitFlag, strategy));
        bytes32 newBasketId = keccak256(abi.encodePacked(newBitFlag, strategy));

        // Check the storage before making changes
        assertEq(
            basketManager.basketIdToAddress(oldBasketId), address(basket), "Old basketIdToAddress() should be not empty"
        );
        assertEq(basketManager.basketIdToAddress(newBasketId), address(0), "New basket id should be empty");

        // Update the bit flag
        vm.prank(timelock);
        basketManager.updateBitFlag(basket, newBitFlag);

        // Check storage changes
        assertEq(basketManager.basketIdToAddress(oldBasketId), address(0), "Old basketIdToAddress() not reset");
        assertEq(basketManager.basketIdToAddress(newBasketId), basket, "New basketIdToAddress() not set correctly");

        address[] memory updatedAssets = basketManager.basketAssets(basket);
        for (uint256 i = 0; i < updatedAssets.length; i++) {
            assertEq(updatedAssets[i], address(uint160(uint160(rootAsset) + i)), "basketAssets() not updated correctly");
        }
    }

    function testFuzz_updateBitFlag_revertWhen_BasketTokenNotFound(address invalidBasket, uint256 newBitFlag) public {
        address basket = _setupSingleBasketAndMocks();
        vm.assume(invalidBasket != basket);
        vm.expectRevert(BasketManager.BasketTokenNotFound.selector);
        vm.prank(timelock);
        basketManager.updateBitFlag(invalidBasket, newBitFlag);
    }

    function testFuzz_updateBitFlag_revertWhen_BitFlagMustBeDifferent(uint256 newBitFlag) public {
        address basket = _setupSingleBasketAndMocks();
        uint256 currentBitFlag = BasketToken(basket).bitFlag();
        vm.assume(currentBitFlag == newBitFlag); // Ensure newBitFlag is the same as currentBitFlag
        vm.expectRevert(BasketManager.BitFlagMustBeDifferent.selector);
        vm.prank(timelock);
        basketManager.updateBitFlag(basket, newBitFlag);
    }

    function testFuzz_updateBitFlag_revertWhen_BitFlagMustIncludeCurrent(uint256 newBitFlag) public {
        address basket = _setupSingleBasketAndMocks();
        uint256 currentBitFlag = BasketToken(basket).bitFlag();
        vm.assume((currentBitFlag & newBitFlag) != currentBitFlag); // Ensure newBitFlag doesn't include currentBitFlag
        vm.expectRevert(BasketManager.BitFlagMustIncludeCurrent.selector);
        vm.prank(timelock);
        basketManager.updateBitFlag(basket, newBitFlag);
    }

    function testFuzz_updateBitFlag_revertWhen_BitFlagUnsupportedByStrategy(uint256 newBitFlag) public {
        address basket = _setupSingleBasketAndMocks();
        uint256 currentBitFlag = BasketToken(basket).bitFlag();
        vm.assume((currentBitFlag & newBitFlag) == currentBitFlag); // Ensure newBitFlag includes currentBitFlag
        vm.assume(currentBitFlag != newBitFlag);
        vm.mockCall(
            BasketToken(basket).strategy(),
            abi.encodeCall(WeightStrategy.supportsBitFlag, (newBitFlag)),
            abi.encode(false)
        );
        vm.expectRevert(BasketManager.BitFlagUnsupportedByStrategy.selector);
        vm.prank(timelock);
        basketManager.updateBitFlag(basket, newBitFlag);
    }

    function test_updateBitFlag_revertWhen_BasketIdAlreadyExists() public {
        // Setup basket and target weights
        address[][] memory basketAssets = new address[][](2);
        basketAssets[0] = new address[](2);
        basketAssets[0][0] = rootAsset;
        basketAssets[0][1] = pairAsset;
        basketAssets[1] = new address[](2);
        basketAssets[1][0] = pairAsset;
        basketAssets[1][1] = rootAsset;
        uint256[] memory depositAmounts = new uint256[](2);
        depositAmounts[0] = 1e18;
        depositAmounts[1] = 1e18;
        uint64[][] memory initialWeights = new uint64[][](2);
        initialWeights[0] = new uint64[](2);
        initialWeights[0][0] = 0.5e18;
        initialWeights[0][1] = 0.5e18;
        initialWeights[1] = new uint64[](2);
        initialWeights[1][0] = 0.5e18;
        initialWeights[1][1] = 0.5e18;
        // Use the same strategies with different bitFlags
        address[] memory strategies = new address[](2);
        address strategy = address(uint160(uint256(keccak256("Strategy"))));
        strategies[0] = strategy;
        strategies[1] = strategy;
        uint256[] memory bitFlags = new uint256[](2);
        bitFlags[0] = 1;
        bitFlags[1] = 3;

        address[] memory baskets =
            _setupBasketsAndMocks(basketAssets, initialWeights, depositAmounts, bitFlags, strategies);

        // Use a bitflag of a basket with the same strategy
        uint256 newBitFlag = BasketToken(baskets[1]).bitFlag();
        bytes32 newBasketId = keccak256(abi.encodePacked(newBitFlag, strategy));

        // Assert the new id is already taken
        assertTrue(basketManager.basketIdToAddress(newBasketId) != address(0));

        // Expect revert due to BasketIdAlreadyExists
        vm.expectRevert(BasketManager.BasketIdAlreadyExists.selector);
        vm.prank(timelock);
        basketManager.updateBitFlag(baskets[0], newBitFlag);
    }

    function testFuzz_updateBitFlag_revertWhen_CalledByNonTimelock(
        address caller,
        address basket,
        uint256 newBitFlag
    )
        public
    {
        vm.assume(!basketManager.hasRole(TIMELOCK_ROLE, caller));
        vm.expectRevert(_formatAccessControlError(caller, TIMELOCK_ROLE));
        vm.prank(caller);
        basketManager.updateBitFlag(basket, newBitFlag);
    }

    // Internal functions
    function _setTokenSwapAdapter() internal {
        vm.prank(timelock);
        basketManager.setTokenSwapAdapter(tokenSwapAdapter);
    }

    function _setupBasketsAndMocks(
        address[][] memory assetsPerBasket,
        uint64[][] memory weightsPerBasket,
        uint256[] memory initialDepositAmounts,
        uint256[] memory bitFlags,
        address[] memory strategies
    )
        public
        returns (address[] memory baskets)
    {
        string memory name = "basket";
        string memory symbol = "b";

        uint256 numBaskets = assetsPerBasket.length;
        baskets = new address[](numBaskets);

        assertEq(numBaskets, weightsPerBasket.length, "_setupBasketsAndMocks: Weights array length mismatch");
        assertEq(
            numBaskets,
            initialDepositAmounts.length,
            "_setupBasketsAndMocks: Initial deposit amounts array length mismatch"
        );
        assertEq(numBaskets, bitFlags.length, "_setupBasketsAndMocks: Bit flags array length mismatch");
        assertEq(numBaskets, strategies.length, "_setupBasketsAndMocks: Strategies array length mismatch");

        _targetWeights = weightsPerBasket;

        for (uint256 i = 0; i < numBaskets; i++) {
            address[] memory assets = assetsPerBasket[i];
            uint64[] memory weights = weightsPerBasket[i];
            address baseAsset = assets[0];
            mockPriceOracle.setPrice(assets[i], baseAsset, 1e18);
            mockPriceOracle.setPrice(baseAsset, assets[i], 1e18);
            uint256 bitFlag = bitFlags[i];
            address strategy = strategies[i];
            vm.mockCall(
                basketTokenImplementation,
                abi.encodeCall(
                    BasketToken.initialize, (IERC20(baseAsset), name, symbol, bitFlag, strategy, assetRegistry)
                ),
                new bytes(0)
            );
            vm.mockCall(
                strategyRegistry,
                abi.encodeCall(StrategyRegistry.supportsBitFlag, (bitFlag, strategy)),
                abi.encode(true)
            );
            vm.mockCall(strategy, abi.encodeCall(WeightStrategy.supportsBitFlag, (bitFlag)), abi.encode(true));
            vm.mockCall(assetRegistry, abi.encodeCall(AssetRegistry.hasPausedAssets, (bitFlag)), abi.encode(false));
            vm.mockCall(assetRegistry, abi.encodeCall(AssetRegistry.getAssets, (bitFlag)), abi.encode(assets));
            vm.prank(manager);
            baskets[i] = basketManager.createNewBasket(name, symbol, baseAsset, bitFlag, strategy);

            vm.mockCall(baskets[i], abi.encodeWithSelector(bytes4(keccak256("bitFlag()"))), abi.encode(bitFlag));
            vm.mockCall(
                baskets[i], abi.encodeCall(BasketToken.totalPendingDeposits, ()), abi.encode(initialDepositAmounts[i])
            );
            vm.mockCall(baskets[i], abi.encodeWithSelector(BasketToken.fallbackRedeemTrigger.selector), new bytes(0));
            vm.mockCall(
                baskets[i],
                abi.encodeWithSelector(BasketToken.prepareForRebalance.selector),
                abi.encode(initialDepositAmounts[i], 0)
            );
            vm.mockCall(baskets[i], abi.encodeWithSelector(bytes4(keccak256("strategy()"))), abi.encode(strategy));
            vm.mockCall(baskets[i], abi.encodeWithSelector(BasketToken.fulfillDeposit.selector), new bytes(0));
            vm.mockCall(baskets[i], abi.encodeCall(IERC20.totalSupply, ()), abi.encode(0));
            vm.mockCall(baskets[i], abi.encodeWithSelector(BasketToken.getTargetWeights.selector), abi.encode(weights));
        }
    }

    function _setupBasketsAndMocks(
        address[][] memory assetsPerBasket,
        uint64[][] memory weightsPerBasket,
        uint256[] memory initialDepositAmounts,
        address[] memory strategies
    )
        public
        returns (address[] memory baskets)
    {
        uint256[] memory bitFlags = new uint256[](assetsPerBasket.length);
        for (uint256 i = 0; i < assetsPerBasket.length; i++) {
            bitFlags[i] = i + 1;
        }
        return _setupBasketsAndMocks(assetsPerBasket, weightsPerBasket, initialDepositAmounts, bitFlags, strategies);
    }

    function _setupBasketsAndMocks(
        address[][] memory assetsPerBasket,
        uint64[][] memory weightsPerBasket,
        uint256[] memory initialDepositAmounts
    )
        internal
        returns (address[] memory baskets)
    {
        address[] memory strategies = new address[](assetsPerBasket.length);
        for (uint256 i = 0; i < assetsPerBasket.length; i++) {
            strategies[i] = address(uint160(uint256(keccak256("Strategy")) + i));
        }
        return _setupBasketsAndMocks(assetsPerBasket, weightsPerBasket, initialDepositAmounts, strategies);
    }

    function _setupSingleBasketAndMocks(
        address[] memory assets,
        uint64[] memory targetWeights,
        uint256 initialDepositAmount
    )
        internal
        returns (address basket)
    {
        address[][] memory assetsPerBasket = new address[][](1);
        assetsPerBasket[0] = assets;
        uint64[][] memory weightsPerBasket = new uint64[][](1);
        weightsPerBasket[0] = targetWeights;
        uint256[] memory initialDepositAmounts = new uint256[](1);
        initialDepositAmounts[0] = initialDepositAmount;
        address[] memory baskets = _setupBasketsAndMocks(assetsPerBasket, weightsPerBasket, initialDepositAmounts);
        return baskets[0];
    }

    function _setupSingleBasketAndMocks() internal returns (address basket) {
        uint256 initialDepositAmount = 10_000;
        return _setupSingleBasketAndMocks(initialDepositAmount);
    }

    function _setupSingleBasketAndMocks(uint256 depositAmount) internal returns (address basket) {
        address[] memory assets = new address[](2);
        assets[0] = rootAsset;
        assets[1] = pairAsset;
        uint64[] memory targetWeights = new uint64[](2);
        targetWeights[0] = 0.05e18;
        targetWeights[1] = 0.05e18;
        return _setupSingleBasketAndMocks(assets, targetWeights, depositAmount);
    }

    function _setPrices(address asset) internal {
        mockPriceOracle.setPrice(asset, USD_ISO_4217_CODE, 1e18);
        mockPriceOracle.setPrice(USD_ISO_4217_CODE, asset, 1e18);
        vm.startPrank(admin);
        eulerRouter.govSetConfig(asset, USD_ISO_4217_CODE, address(mockPriceOracle));
        eulerRouter.govSetConfig(rootAsset, asset, address(mockPriceOracle));
        vm.stopPrank();
    }

    function _proposeAndCompleteExternalTrades(
        address[] memory baskets,
        uint64[][] memory basketsTargetWeights,
        uint256 depositAmount,
        uint256 sellWeight,
        uint256 tradeSuccess
    )
        internal
    {
        address basket = baskets[0];
        // Setup the trade and propose token swap
        TradeTestParams memory params;
        params.pairAsset = pairAsset;
        params.sellWeight = sellWeight;
        params.depositAmount = depositAmount;
        params.baseAssetWeight = 1e18 - params.sellWeight;
        ExternalTrade[] memory externalTrades = new ExternalTrade[](1);
        InternalTrade[] memory internalTrades = new InternalTrade[](0);
        BasketTradeOwnership[] memory tradeOwnerships = new BasketTradeOwnership[](1);
        tradeOwnerships[0] = BasketTradeOwnership({ basket: baskets[0], tradeOwnership: uint96(1e18) });
        externalTrades[0] = ExternalTrade({
            sellToken: rootAsset,
            buyToken: params.pairAsset,
            sellAmount: params.depositAmount * params.sellWeight / 1e18,
            minAmount: (params.depositAmount * params.sellWeight / 1e18) * 0.995e18 / 1e18,
            basketTradeOwnership: tradeOwnerships
        });
        vm.prank(tokenswapProposer);
        basketManager.proposeTokenSwap(internalTrades, externalTrades, baskets, basketsTargetWeights);

        // Mock calls for executeTokenSwap
        uint256 numTrades = externalTrades.length;
        bytes32[] memory tradeHashes = new bytes32[](numTrades);
        for (uint8 i = 0; i < numTrades; i++) {
            tradeHashes[i] = keccak256(abi.encode(externalTrades[i]));
        }
        vm.mockCall(
            address(tokenSwapAdapter),
            abi.encodeWithSelector(TokenSwapAdapter.executeTokenSwap.selector),
            abi.encode(tradeHashes)
        );
        // Execute
        vm.prank(tokenswapExecutor);
        basketManager.executeTokenSwap(externalTrades, "");

        // Assert
        assertEq(basketManager.rebalanceStatus().timestamp, vm.getBlockTimestamp());
        assertEq(uint8(basketManager.rebalanceStatus().status), uint8(Status.TOKEN_SWAP_EXECUTED));

        // Simulate the passage of time
        vm.warp(vm.getBlockTimestamp() + 15 minutes + 1);

        vm.mockCall(basket, abi.encodeCall(BasketToken.totalPendingDeposits, ()), abi.encode(0));
        vm.mockCall(basket, abi.encodeWithSelector(BasketToken.prepareForRebalance.selector), abi.encode(0));
        vm.mockCall(basket, abi.encodeWithSelector(BasketToken.fulfillRedeem.selector), new bytes(0));
        vm.mockCall(rootAsset, abi.encodeWithSelector(IERC20.approve.selector), abi.encode(true));
        vm.mockCall(basket, abi.encodeCall(IERC20.totalSupply, ()), abi.encode(params.depositAmount));
        // Mock results of external trade
        uint256[2][] memory claimedAmounts = new uint256[2][](numTrades);
        // tradeSuccess => 1e18 for a 100% successful trade, 0 for 100% unsuccessful trade
        // 0 in the 1 index is the result of a 100% unsuccessful trade
        // 0 in the 0 index is the result of a 100% successful trade
        uint256 successfulSellAmount = externalTrades[0].sellAmount * tradeSuccess / 1e18;
        claimedAmounts[0] = [externalTrades[0].sellAmount - successfulSellAmount, successfulSellAmount];
        vm.mockCall(
            address(tokenSwapAdapter),
            abi.encodeWithSelector(TokenSwapAdapter.completeTokenSwap.selector),
            abi.encode(claimedAmounts)
        );
        basketManager.completeRebalance(externalTrades, baskets, basketsTargetWeights);
    }
}
