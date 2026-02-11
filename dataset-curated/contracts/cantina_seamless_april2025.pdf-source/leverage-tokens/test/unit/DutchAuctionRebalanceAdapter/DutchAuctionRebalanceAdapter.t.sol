// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Forge imports
import {Test} from "forge-std/Test.sol";

// Dependency imports
import {UnsafeUpgrades} from "@foundry-upgrades/Upgrades.sol";

// Internal imports
import {MockRebalanceAdapter} from "test/unit/mock/MockRebalanceAdapter.sol";
import {DutchAuctionRebalanceAdapter} from "src/rebalance/DutchAuctionRebalanceAdapter.sol";
import {DutchAuctionRebalanceAdapterHarness} from "test/unit/harness/DutchAuctionRebalanceAdapterHarness.t.sol";
import {ILeverageToken} from "src/interfaces/ILeverageToken.sol";
import {ILeverageManager} from "src/interfaces/ILeverageManager.sol";
import {ILendingAdapter} from "src/interfaces/ILendingAdapter.sol";
import {MockERC20} from "test/unit/mock/MockERC20.sol";
import {MockLendingAdapter} from "test/unit/mock/MockLendingAdapter.sol";
import {MockLeverageManager} from "test/unit/mock/MockLeverageManager.sol";
import {LeverageTokenState} from "src/types/DataTypes.sol";

contract DutchAuctionRebalanceAdapterTest is Test {
    // Common constants used across tests
    uint256 public constant BPS_DENOMINATOR = 1e18;
    uint256 public constant BASE_RATIO = 1e18; // 1.0 with 18 decimals precision
    uint256 public constant MIN_RATIO = 1e18; // 1x
    uint256 public constant MAX_RATIO = 3e18; // 3x
    uint256 public constant TARGET_RATIO = 2e18; // 2x
    uint256 public constant AUCTION_START_TIME = 1000;
    uint256 public constant DEFAULT_DURATION = 1 days;
    uint256 public constant DEFAULT_INITIAL_PRICE_MULTIPLIER = 1.1 * 1e18;
    uint256 public constant DEFAULT_MIN_PRICE_MULTIPLIER = 0.1 * 1e18;

    MockERC20 public collateralToken;
    MockERC20 public debtToken;
    ILeverageToken public leverageToken;

    MockLendingAdapter public lendingAdapter;
    MockLeverageManager public leverageManager;
    DutchAuctionRebalanceAdapterHarness public auctionRebalancer;

    address public owner = makeAddr("owner");

    function setUp() public virtual {
        // Setup mock tokens
        collateralToken = new MockERC20();
        debtToken = new MockERC20();
        leverageToken = ILeverageToken(address(new MockERC20()));

        // Setup mock adapters and managers
        lendingAdapter = new MockLendingAdapter(address(collateralToken), address(debtToken), address(this));
        leverageManager = new MockLeverageManager();

        // Setup leverage token data in leverage manager
        leverageManager.setLeverageTokenData(
            leverageToken,
            MockLeverageManager.LeverageTokenData({
                leverageToken: leverageToken,
                lendingAdapter: ILendingAdapter(address(lendingAdapter)),
                collateralAsset: collateralToken,
                debtAsset: debtToken
            })
        );

        address dutchAuctionRebalancerImplementation = address(new DutchAuctionRebalanceAdapterHarness());
        address dutchAuctionRebalancerProxy = UnsafeUpgrades.deployUUPSProxy(
            dutchAuctionRebalancerImplementation,
            abi.encodeWithSelector(
                DutchAuctionRebalanceAdapterHarness.initialize.selector,
                DEFAULT_DURATION,
                DEFAULT_INITIAL_PRICE_MULTIPLIER,
                DEFAULT_MIN_PRICE_MULTIPLIER
            )
        );

        // Setup owner and deploy auction rebalancer harness
        auctionRebalancer = DutchAuctionRebalanceAdapterHarness(dutchAuctionRebalancerProxy);
        auctionRebalancer.mock_setLeverageManager(ILeverageManager(address(leverageManager)));
        auctionRebalancer.mock_isEligible(true);
        auctionRebalancer.exposed_setLeverageToken(leverageToken);
        leverageManager.setLeverageTokenRebalanceAdapter(leverageToken, address(auctionRebalancer));

        _mockLeverageTokenTargetCollateralRatio(TARGET_RATIO);
    }

    function test_setUp() public view {
        assertEq(address(auctionRebalancer.getLeverageManager()), address(leverageManager));
        assertEq(address(auctionRebalancer.getLeverageToken()), address(leverageToken));
        assertEq(auctionRebalancer.getAuctionDuration(), DEFAULT_DURATION);
        assertEq(auctionRebalancer.getInitialPriceMultiplier(), DEFAULT_INITIAL_PRICE_MULTIPLIER);
        assertEq(auctionRebalancer.getMinPriceMultiplier(), DEFAULT_MIN_PRICE_MULTIPLIER);

        bytes32 expectedSlot = keccak256(
            abi.encode(uint256(keccak256("seamless.contracts.storage.DutchAuctionRebalanceAdapter")) - 1)
        ) & ~bytes32(uint256(0xff));
        assertEq(auctionRebalancer.exposed_getDutchAuctionRebalanceAdapterStorageSlot(), expectedSlot);
    }

    function _setAuctionParameters(uint256 initialPriceMultiplier, uint256 minPriceMultiplier) internal {
        vm.startPrank(owner);
        auctionRebalancer.exposed_setAuctionDuration(DEFAULT_DURATION);
        auctionRebalancer.exposed_setInitialPriceMultiplier(initialPriceMultiplier);
        auctionRebalancer.exposed_setMinPriceMultiplier(minPriceMultiplier);
        vm.stopPrank();
    }

    function _mockLeverageTokenTargetCollateralRatio(uint256 targetRatio) internal {
        auctionRebalancer.mock_setTargetCollateralRatio(targetRatio);
    }

    function _setLeverageTokenCollateralRatio(uint256 collateralRatio) internal {
        // Note: collateralInDebtAsset, debt and equity are not used in isAuctionValid checks
        LeverageTokenState memory state =
            LeverageTokenState({collateralInDebtAsset: 0, debt: 0, collateralRatio: collateralRatio, equity: 0});
        leverageManager.setLeverageTokenState(leverageToken, state);
    }

    function _createAuction() internal {
        vm.warp(AUCTION_START_TIME);
        vm.prank(owner);
        auctionRebalancer.createAuction();
    }
}
