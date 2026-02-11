// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { Test } from "forge-std/Test.sol";

import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { Controller, RebalancingManager } from "../../src/controller/Controller.sol";
import { BaseController } from "../../src/controller/BaseController.sol";
import { GenericUnit } from "../../src/unit/GenericUnit.sol";
import { SingleStrategyVault } from "../../src/vault/SingleStrategyVault.sol";
import { IYieldDistributor } from "../../src/interfaces/IYieldDistributor.sol";

import { MockERC20 } from "../helper/MockERC20.sol";
import { MockPriceFeed } from "../helper/MockPriceFeed.sol";
import { MockStrategy } from "../helper/MockStrategy.sol";
import { MockSwapper } from "../helper/MockSwapper.sol";

abstract contract ControllerIntegrationTest is Test {
    Controller controller;
    GenericUnit gusd;
    address rewardsCollector = makeAddr("rewardsCollector");
    address yieldDistributor = makeAddr("yieldDistributor");

    MockPriceFeed priceFeed1 = new MockPriceFeed(1e8, 8);
    MockPriceFeed priceFeed2 = new MockPriceFeed(1e8, 8);

    MockERC20 asset1 = new MockERC20(6);
    MockERC20 asset2 = new MockERC20(8);

    MockStrategy strategy1 = new MockStrategy(asset1);
    MockStrategy strategy2 = new MockStrategy(asset2);

    SingleStrategyVault vault1;
    SingleStrategyVault vault2;

    MockSwapper swapper = new MockSwapper();

    address user = makeAddr("user");

    function setUp() public virtual {
        controller = Controller(address(new TransparentUpgradeableProxy(address(new Controller()), address(this), "")));
        gusd = new GenericUnit(address(controller), "Generic Unit USD", "GU_USD");
        controller.initialize(address(this), gusd, rewardsCollector, swapper, IYieldDistributor(yieldDistributor));

        controller.grantRole(controller.PRICE_FEED_MANAGER_ROLE(), address(this));
        controller.setPriceFeed(address(asset1), priceFeed1, 1 hours);
        controller.setPriceFeed(address(asset2), priceFeed2, 1 hours);

        vault1 = new SingleStrategyVault(asset1, controller, strategy1, address(0));
        vault2 = new SingleStrategyVault(asset2, controller, strategy2, address(0));

        controller.grantRole(controller.VAULT_MANAGER_ROLE(), address(this));
        controller.addVault(address(vault1), BaseController.VaultSettings(1_000_000e18, 0, 10_000), true);
        controller.addVault(address(vault2), BaseController.VaultSettings(1_000_000e18, 0, 10_000), true);

        controller.grantRole(controller.YIELD_MANAGER_ROLE(), address(this));
        controller.grantRole(controller.CONFIG_MANAGER_ROLE(), address(this));
        controller.grantRole(controller.REBALANCING_MANAGER_ROLE(), address(this));
        controller.grantRole(controller.REWARDS_MANAGER_ROLE(), address(this));

        deal(address(asset1), user, 1_000_000e6);
        deal(address(asset2), user, 1_000_000e8);

        vm.startPrank(user);
        asset1.approve(address(vault1), type(uint256).max);
        asset2.approve(address(vault2), type(uint256).max);
        vm.stopPrank();

        vm.label(address(controller), "Controller");
        vm.label(address(gusd), "GU_USD");
        vm.label(address(vault1), "Vault1");
        vm.label(address(vault2), "Vault2");
        vm.label(address(strategy1), "Strategy1");
        vm.label(address(strategy2), "Strategy2");
        vm.label(address(asset1), "Asset1");
        vm.label(address(asset2), "Asset2");
        vm.label(address(priceFeed1), "PriceFeed1");
        vm.label(address(priceFeed2), "PriceFeed2");
    }
}

contract Controller_DepositWithdraw_IntegrationTest is ControllerIntegrationTest {
    function test_depositWithdraw_whenPriceStable() public {
        // Deposit
        vm.startPrank(user);
        uint256 shares1 = vault1.deposit(100e6, user);
        uint256 shares2 = vault2.deposit(200e8, user);
        vm.stopPrank();

        assertEq(shares1, 100e18);
        assertEq(shares2, 200e18);
        assertEq(gusd.balanceOf(user), 300e18);

        assertEq(vault1.totalAssets(), 100e6);
        assertEq(vault2.totalAssets(), 200e8);
        assertEq(strategy1.totalAssets(), 100e6);
        assertEq(strategy2.totalAssets(), 200e8);

        assertEq(asset1.balanceOf(address(vault1)), 0);
        assertEq(asset2.balanceOf(address(vault2)), 0);
        assertEq(asset1.balanceOf(address(strategy1)), 100e6);
        assertEq(asset2.balanceOf(address(strategy2)), 200e8);

        assertEq(controller.shareRedemptionPrice(), 1e18);
        assertEq(controller.assetRedemptionPrice(address(asset1)), 1e18);
        assertEq(controller.assetRedemptionPrice(address(asset2)), 1e18);

        // Withdraw
        vm.prank(user);
        vault1.withdraw(90e6, user, user);

        assertEq(gusd.balanceOf(user), 210e18);

        assertEq(vault1.totalAssets(), 10e6);
        assertEq(strategy1.totalAssets(), 10e6);

        assertEq(asset1.balanceOf(address(vault1)), 0);
        assertEq(asset1.balanceOf(address(strategy1)), 10e6);

        // Withdraw again
        vm.prank(user);
        vault2.withdraw(150e8, user, user);

        assertEq(gusd.balanceOf(user), 60e18);

        assertEq(vault2.totalAssets(), 50e8);
        assertEq(strategy2.totalAssets(), 50e8);

        assertEq(asset2.balanceOf(address(vault2)), 0);
        assertEq(asset2.balanceOf(address(strategy2)), 50e8);
    }

    function test_depositWithdraw_whenPriceVolatile() public {
        priceFeed1.setPrice(1.1e8);
        priceFeed2.setPrice(0.9e8);

        // Deposit
        vm.startPrank(user);
        uint256 shares1 = vault1.deposit(100e6, user);
        uint256 shares2 = vault2.deposit(200e8, user);
        vm.stopPrank();

        assertEq(shares1, 100e18); // 100 * min(1.1, 1) = 100
        assertEq(shares2, 180e18); // 200 * min(0.9, 1) = 180
        assertEq(gusd.balanceOf(user), 280e18); // 100 * min(1.1, 1) + 200 * min(0.9, 1) = 280

        assertEq(vault1.totalAssets(), 100e6);
        assertEq(vault2.totalAssets(), 200e8);
        assertEq(strategy1.totalAssets(), 100e6);
        assertEq(strategy2.totalAssets(), 200e8);

        assertEq(asset1.balanceOf(address(vault1)), 0);
        assertEq(asset2.balanceOf(address(vault2)), 0);
        assertEq(asset1.balanceOf(address(strategy1)), 100e6);
        assertEq(asset2.balanceOf(address(strategy2)), 200e8);

        assertEq(controller.shareRedemptionPrice(), 1e18); // 100 * 1.1 + 200 * 0.9 = 290 > 280 => 1
        assertEq(controller.assetRedemptionPrice(address(asset1)), 1.1e18); // max(1.1, 1)
        assertEq(controller.assetRedemptionPrice(address(asset2)), 1e18); // max(0.9, 1)

        // Price changes
        priceFeed1.setPrice(0.72e8);
        priceFeed2.setPrice(0.9e8);

        assertEq(controller.shareRedemptionPrice(), 0.9e18);
        // 100 * 0.72 + 200 * 0.9 = 252 < 280 => 0.9
        assertEq(controller.assetRedemptionPrice(address(asset1)), 1e18); // max(0.72, 1)
        assertEq(controller.assetRedemptionPrice(address(asset2)), 1e18); // max(0.9, 1)

        // Withdraw
        vm.prank(user);
        shares1 = vault1.withdraw(90e6, user, user);

        assertEq(shares1, 100e18); // 90 * max(0.72, 1) = 90 -> 90 / 0.9 = 100
        assertEq(gusd.balanceOf(user), 180e18); // 280 - 100

        assertEq(vault1.totalAssets(), 10e6);
        assertEq(strategy1.totalAssets(), 10e6);

        assertEq(asset1.balanceOf(address(vault1)), 0);
        assertEq(asset1.balanceOf(address(strategy1)), 10e6);

        // Price 2 change
        priceFeed2.setPrice(1.2e8);

        assertEq(controller.shareRedemptionPrice(), 1e18);
        // 10 * 0.72 + 200 * 1.2 = 247.2 > 180 => 1
        assertEq(controller.assetRedemptionPrice(address(asset2)), 1.2e18); // max(1.2, 1)

        // Withdraw again
        vm.prank(user);
        shares2 = vault2.withdraw(150e8, user, user);

        assertEq(shares2, 180e18); // 150 * max(1.2, 1) / 1 = 180
        assertEq(gusd.balanceOf(user), 0);

        assertEq(vault2.totalAssets(), 50e8);
        assertEq(strategy2.totalAssets(), 50e8);

        assertEq(asset2.balanceOf(address(vault2)), 0);
        assertEq(asset2.balanceOf(address(strategy2)), 50e8);
    }
}

contract Controller_MintRedeem_IntegrationTest is ControllerIntegrationTest {
    function test_mintRedeem_whenPriceStable() public {
        // share:asset ratio is 1:1 when price is stable

        // Mint
        vm.startPrank(user);
        uint256 assets1 = vault1.mint(100e18, user);
        uint256 assets2 = vault2.mint(200e18, user);
        vm.stopPrank();

        assertEq(assets1, 100e6);
        assertEq(assets2, 200e8);
        assertEq(gusd.balanceOf(user), 300e18);

        assertEq(vault1.totalAssets(), 100e6);
        assertEq(vault2.totalAssets(), 200e8);
        assertEq(strategy1.totalAssets(), 100e6);
        assertEq(strategy2.totalAssets(), 200e8);

        assertEq(asset1.balanceOf(address(vault1)), 0);
        assertEq(asset2.balanceOf(address(vault2)), 0);
        assertEq(asset1.balanceOf(address(strategy1)), 100e6);
        assertEq(asset2.balanceOf(address(strategy2)), 200e8);

        assertEq(controller.shareRedemptionPrice(), 1e18);
        assertEq(controller.assetRedemptionPrice(address(asset1)), 1e18);
        assertEq(controller.assetRedemptionPrice(address(asset2)), 1e18);

        // Redeem
        vm.prank(user);
        vault1.redeem(90e18, user, user);

        assertEq(gusd.balanceOf(user), 210e18);

        assertEq(vault1.totalAssets(), 10e6);
        assertEq(strategy1.totalAssets(), 10e6);

        assertEq(asset1.balanceOf(address(vault1)), 0);
        assertEq(asset1.balanceOf(address(strategy1)), 10e6);

        // Redeem again
        vm.prank(user);
        vault2.redeem(150e18, user, user);

        assertEq(gusd.balanceOf(user), 60e18);

        assertEq(vault2.totalAssets(), 50e8);
        assertEq(strategy2.totalAssets(), 50e8);

        assertEq(asset2.balanceOf(address(vault2)), 0);
        assertEq(asset2.balanceOf(address(strategy2)), 50e8);
    }

    function test_mintRedeem_whenPriceVolatile() public {
        priceFeed1.setPrice(1.1e8);
        priceFeed2.setPrice(0.8e8);

        assertEq(controller.assetDepositPrice(address(asset1)), 1e18); // min(1.1, 1)
        assertEq(controller.assetDepositPrice(address(asset2)), 0.8e18); // min(0.8, 1)

        // Mint
        vm.startPrank(user);
        uint256 assets1 = vault1.mint(100e18, user);
        uint256 assets2 = vault2.mint(200e18, user);
        vm.stopPrank();

        assertEq(assets1, 100e6); // 100 / min(1.1, 1) = 100
        assertEq(assets2, 250e8); // 200 / min(0.8, 1) = 250
        assertEq(gusd.balanceOf(user), 300e18);

        assertEq(vault1.totalAssets(), 100e6);
        assertEq(vault2.totalAssets(), 250e8);
        assertEq(strategy1.totalAssets(), 100e6);
        assertEq(strategy2.totalAssets(), 250e8);

        assertEq(asset1.balanceOf(address(vault1)), 0);
        assertEq(asset2.balanceOf(address(vault2)), 0);
        assertEq(asset1.balanceOf(address(strategy1)), 100e6);
        assertEq(asset2.balanceOf(address(strategy2)), 250e8);

        assertEq(controller.shareRedemptionPrice(), 1e18); // 100 * 1.1 + 250 * 0.8 = 310 > 300 => 1
        assertEq(controller.assetRedemptionPrice(address(asset1)), 1.1e18); // max(1.1, 1)
        assertEq(controller.assetRedemptionPrice(address(asset2)), 1e18); // max(0.8, 1)

        // Price changes
        priceFeed1.setPrice(1.2e8);
        priceFeed2.setPrice(0.6e8);

        assertEq(controller.shareRedemptionPrice(), 0.9e18);
        // 100 * 1.2 + 250 * 0.6 = 270 < 300 => 0.9
        assertEq(controller.assetRedemptionPrice(address(asset1)), 1.2e18); // max(1.2, 1)
        assertEq(controller.assetRedemptionPrice(address(asset2)), 1e18); // max(0.6, 1)

        // Redeem
        vm.prank(user);
        assets1 = vault1.redeem(60e18, user, user);

        assertEq(assets1, 45e6); // 60 * 0.9 / max(1.2, 1) = 45
        assertEq(gusd.balanceOf(user), 240e18); // 300 - 60

        assertEq(vault1.totalAssets(), 55e6);
        assertEq(strategy1.totalAssets(), 55e6);

        assertEq(asset1.balanceOf(address(vault1)), 0);
        assertEq(asset1.balanceOf(address(strategy1)), 55e6);

        // Price 2 change
        priceFeed2.setPrice(1.2e8);

        assertEq(controller.shareRedemptionPrice(), 1e18);
        // 55 * 1.2 + 250 * 1.2 = 366 > 240 => 1
        assertEq(controller.assetRedemptionPrice(address(asset1)), 1.2e18); // max(1.2, 1)
        assertEq(controller.assetRedemptionPrice(address(asset2)), 1.2e18); // max(1.2, 1)

        // Redeem again
        vm.prank(user);
        assets2 = vault2.redeem(150e18, user, user);

        assertEq(assets2, 125e8); // 150 * 1 / max(1.2, 1) = 125
        assertEq(gusd.balanceOf(user), 90e18);

        assertEq(vault2.totalAssets(), 125e8);
        assertEq(strategy2.totalAssets(), 125e8);

        assertEq(asset2.balanceOf(address(vault2)), 0);
        assertEq(asset2.balanceOf(address(strategy2)), 125e8);
    }
}

contract Controller_YieldDistribution_IntegrationTest is ControllerIntegrationTest {
    uint256 errDelta = 0.000001e18;

    function test_distributeYield() public {
        // Deposit
        vm.startPrank(user);
        vault1.deposit(100e6, user);
        vault2.deposit(200e8, user);
        vm.stopPrank();

        // Simulate yield
        vm.startPrank(user);
        require(asset1.transfer(address(strategy1), 10e6)); // 10% yield
        require(asset2.transfer(address(strategy2), 10e8)); // 5% yield
        vm.stopPrank();

        assertApproxEqAbs(vault1.totalAssets(), 110e6, 1);
        assertApproxEqAbs(vault2.totalAssets(), 210e8, 1);
        assertApproxEqAbs(strategy1.totalAssets(), 110e6, 1);
        assertApproxEqAbs(strategy2.totalAssets(), 210e8, 1);

        // Distribute yield
        controller.setSafetyBufferYieldDeduction(5e18);
        uint256 yield = controller.distributeYield();

        assertApproxEqRel(yield, 15e18, errDelta);

        // Check yield distributor balance
        assertApproxEqRel(gusd.balanceOf(yieldDistributor), 15e18, errDelta); // distributed yield

        // Check vault assets after yield distribution
        assertApproxEqAbs(vault1.totalAssets(), 110e6, 1);
        assertApproxEqAbs(vault2.totalAssets(), 210e8, 1);
        assertApproxEqAbs(strategy1.totalAssets(), 110e6, 1);
        assertApproxEqAbs(strategy2.totalAssets(), 210e8, 1);

        // Simulate yield
        vm.startPrank(user);
        require(asset1.transfer(address(strategy1), 10e6));
        require(asset2.transfer(address(strategy2), 10e8));
        vm.stopPrank();

        // Distribute yield
        controller.setSafetyBufferYieldDeduction(6e18);
        yield = controller.distributeYield(); // new safety buffer is 6e18

        assertApproxEqRel(yield, 19e18, errDelta);

        // Check yield distributor balance
        assertApproxEqRel(gusd.balanceOf(yieldDistributor), 34e18, errDelta);
    }
}

contract Controller_Rebalance_IntegrationTest is ControllerIntegrationTest {
    function _mockShareTotalSupply(uint256 totalSupply) internal {
        vm.mockCall(address(gusd), abi.encodeWithSignature("totalSupply()"), abi.encode(totalSupply));
    }

    function test_rebalance_whenDiffAssets() public {
        // Deposit
        vm.startPrank(user);
        vault1.deposit(100e6, user);
        vault2.deposit(200e8, user);
        vm.stopPrank();

        deal(address(asset1), address(swapper), 1_000_000e6);
        deal(address(asset2), address(swapper), 1_000_000e8);

        swapper.setAmountOut(50e8);

        _mockShareTotalSupply(295e18);
        controller.rebalance(address(vault1), 50e6, address(vault2), 45e8, "");

        assertEq(vault1.totalAssets(), 50e6);
        assertEq(vault2.totalAssets(), 250e8);
        assertEq(strategy1.totalAssets(), 50e6);
        assertEq(strategy2.totalAssets(), 250e8);

        swapper.setAmountOut(97e6); // slippage - 3, 1%

        // revert if trade slippage too high
        controller.setMaxProtocolRebalanceSlippage(1100); // 1.1%
        _mockShareTotalSupply(295e18);
        vm.expectRevert(RebalancingManager.Rebalance_SlippageTooHigh.selector);
        controller.rebalance(address(vault2), 100e8, address(vault1), 98e6, "");

        // revert if backing value slippage too high
        controller.setMaxProtocolRebalanceSlippage(50); // 0.5%
        _mockShareTotalSupply(295e18);
        vm.expectRevert(RebalancingManager.Rebalance_SlippageTooHigh.selector);
        controller.rebalance(address(vault2), 100e8, address(vault1), 95e6, "");

        // revert if slippage higher than safety buffer
        controller.setMaxProtocolRebalanceSlippage(1100); // 1.1%
        _mockShareTotalSupply(299e18);
        vm.expectRevert(RebalancingManager.Rebalance_SlippageTooHigh.selector);
        controller.rebalance(address(vault2), 100e8, address(vault1), 95e6, "");

        // success if within limits
        controller.setMaxProtocolRebalanceSlippage(1100); // 1.1%
        _mockShareTotalSupply(295e18);
        controller.rebalance(address(vault2), 100e8, address(vault1), 95e6, "");

        assertEq(vault1.totalAssets(), 147e6);
        assertEq(vault2.totalAssets(), 150e8);
        assertEq(strategy1.totalAssets(), 147e6);
        assertEq(strategy2.totalAssets(), 150e8);
    }

    function test_rebalance_whenSameAssets() public {
        SingleStrategyVault vault1Same = new SingleStrategyVault(asset1, controller, strategy1, address(0));
        controller.addVault(address(vault1Same), BaseController.VaultSettings(1_000_000e18, 0, 10_000), false);

        vm.prank(user);
        vault1.deposit(100e6, user);

        swapper.setAmountOut(0); // should not be used

        controller.rebalance(address(vault1), 50e6, address(vault1Same), 0, "");

        assertEq(vault1.totalAssets(), 50e6);
        assertEq(vault1Same.totalAssets(), 50e6);
        assertEq(strategy1.totalAssets(), 100e6);
    }
}

contract Controller_Rewards_IntegrationTest is ControllerIntegrationTest {
    MockERC20 reward = new MockERC20(6);

    function setUp() public override {
        super.setUp();

        controller.setRewardAsset(address(reward), true);
    }

    function test_sellRewards() public {
        vm.prank(user);
        vault1.deposit(100e6, user);

        deal(address(reward), address(vault1), 10e18);

        uint256 swapAmount = 3621e6;
        deal(address(asset1), address(swapper), swapAmount);
        swapper.setAmountOut(swapAmount);

        controller.sellRewards(address(vault1), address(reward), 0, "");

        assertEq(vault1.totalAssets(), 100e6 + swapAmount);
        assertEq(strategy1.totalAssets(), 100e6 + swapAmount);
    }

    function test_claimRewards() public {
        vm.prank(user);
        vault1.deposit(100e6, user);

        deal(address(reward), address(vault1), 10e18);

        controller.claimRewards(address(vault1), address(reward));

        assertEq(reward.balanceOf(rewardsCollector), 10e18);
    }
}
