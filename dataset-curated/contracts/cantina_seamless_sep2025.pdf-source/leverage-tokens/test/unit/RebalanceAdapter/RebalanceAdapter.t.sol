// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {UnsafeUpgrades} from "@foundry-upgrades/Upgrades.sol";
import {RebalanceAdapter} from "src/rebalance/RebalanceAdapter.sol";
import {RebalanceAdapterHarness} from "test/unit/harness/RebalaneAdapterHarness.t.sol";
import {ILeverageManager} from "src/interfaces/ILeverageManager.sol";
import {ILeverageToken} from "src/interfaces/ILeverageToken.sol";
import {LeverageTokenState} from "src/types/DataTypes.sol";
import {ILendingAdapter} from "src/interfaces/ILendingAdapter.sol";
import {IRebalanceAdapter} from "src/interfaces/IRebalanceAdapter.sol";
import {LeverageManager} from "src/LeverageManager.sol";

contract RebalanceAdapterTest is Test {
    address public authorizedCreator = makeAddr("authorizedCreator");
    address public owner = makeAddr("owner");
    ILeverageManager public leverageManager;
    ILeverageToken public leverageToken = ILeverageToken(makeAddr("leverageToken"));

    uint256 public minCollateralRatio = 1.5 * 1e18;
    uint256 public targetCollateralRatio = 2 * 1e18;
    uint256 public maxCollateralRatio = 2.5 * 1e18;
    uint256 public auctionDuration = 7 minutes;
    uint256 public initialPriceMultiplier = 1.02 * 1e18;
    uint256 public minPriceMultiplier = 0.99 * 1e18;
    uint256 public collateralRatioThreshold = 1.3e8;
    uint256 public rebalanceReward = 50_00;

    RebalanceAdapterHarness public rebalanceAdapter;

    function setUp() public virtual {
        leverageManager = new LeverageManager();

        RebalanceAdapterHarness implementation = new RebalanceAdapterHarness();

        vm.expectEmit(true, true, true, true);
        emit IRebalanceAdapter.RebalanceAdapterInitialized(authorizedCreator, leverageManager);

        address proxy = UnsafeUpgrades.deployUUPSProxy(
            address(implementation),
            abi.encodeWithSelector(
                RebalanceAdapter.initialize.selector,
                owner,
                authorizedCreator,
                leverageManager,
                minCollateralRatio,
                targetCollateralRatio,
                maxCollateralRatio,
                auctionDuration,
                initialPriceMultiplier,
                minPriceMultiplier,
                collateralRatioThreshold,
                rebalanceReward
            )
        );

        rebalanceAdapter = RebalanceAdapterHarness(proxy);

        vm.prank(address(leverageManager));
        rebalanceAdapter.postLeverageTokenCreation(authorizedCreator, address(leverageToken));
    }

    function test_setUp() public view {
        assertEq(rebalanceAdapter.getAuthorizedCreator(), authorizedCreator);
        assertEq(address(rebalanceAdapter.getLeverageManager()), address(leverageManager));
        assertEq(rebalanceAdapter.getLeverageTokenMinCollateralRatio(), minCollateralRatio);
        assertEq(rebalanceAdapter.getLeverageTokenMaxCollateralRatio(), maxCollateralRatio);
        assertEq(rebalanceAdapter.getLeverageTokenTargetCollateralRatio(), targetCollateralRatio);
        assertEq(rebalanceAdapter.getLeverageTokenInitialCollateralRatio(leverageToken), targetCollateralRatio);
        assertEq(rebalanceAdapter.getAuctionDuration(), auctionDuration);
        assertEq(rebalanceAdapter.getInitialPriceMultiplier(), initialPriceMultiplier);
        assertEq(rebalanceAdapter.getMinPriceMultiplier(), minPriceMultiplier);

        bytes32 expectedSlot = keccak256(
            abi.encode(uint256(keccak256("seamless.contracts.storage.RebalanceAdapter")) - 1)
        ) & ~bytes32(uint256(0xff));
        assertEq(rebalanceAdapter.exposed_getRebalanceAdapterStorageSlot(), expectedSlot);
    }

    function testFuzz_initialize_RevertIf_TargetCollateralRatioIsNotGreaterThanBaseRatio(uint256 ratio) public {
        ratio = bound(ratio, 0, leverageManager.BASE_RATIO());

        RebalanceAdapter _rebalanceAdapter = new RebalanceAdapter();

        vm.expectRevert(abi.encodeWithSelector(IRebalanceAdapter.InvalidTargetCollateralRatio.selector, ratio));
        _rebalanceAdapter.initialize(
            RebalanceAdapter.RebalanceAdapterInitParams({
                owner: address(this),
                authorizedCreator: authorizedCreator,
                leverageManager: leverageManager,
                minCollateralRatio: 1e18,
                targetCollateralRatio: ratio,
                maxCollateralRatio: 3e18,
                auctionDuration: 1 days,
                initialPriceMultiplier: 1.1e18,
                minPriceMultiplier: 0.1e18,
                preLiquidationCollateralRatioThreshold: 1.1e18,
                rebalanceReward: 0.1e18
            })
        );
    }

    function _mockLeverageTokenState(LeverageTokenState memory state) internal {
        vm.mockCall(
            address(leverageManager),
            abi.encodeWithSelector(ILeverageManager.getLeverageTokenState.selector, leverageToken),
            abi.encode(state)
        );

        ILendingAdapter lendingAdapter = ILendingAdapter(makeAddr("lendingAdapter"));
        vm.mockCall(
            address(leverageManager),
            abi.encodeWithSelector(ILeverageManager.getLeverageTokenLendingAdapter.selector, leverageToken),
            abi.encode(lendingAdapter)
        );
    }
}
