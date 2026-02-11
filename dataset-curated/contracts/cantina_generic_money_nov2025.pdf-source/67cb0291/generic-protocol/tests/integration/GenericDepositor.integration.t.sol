// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { Test } from "forge-std/Test.sol";

import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import { GenericDepositor } from "../../src/periphery/GenericDepositor.sol";
import { GenericUnit } from "../../src/unit/GenericUnit.sol";
import { Controller } from "../../src/controller/Controller.sol";
import { BaseController } from "../../src/controller/BaseController.sol";
import { SingleStrategyVault } from "../../src/vault/SingleStrategyVault.sol";
import { IYieldDistributor } from "../../src/interfaces/IYieldDistributor.sol";
import { ISwapper } from "../../src/interfaces/ISwapper.sol";
import { GenericUSD } from "../../src/GenericUSD.sol";

import { MockBridgeCoordinatorL1 } from "../helper/MockBridgeCoordinatorL1.sol";
import { MockERC20 } from "../helper/MockERC20.sol";
import { MockStrategy } from "../helper/MockStrategy.sol";
import { MockPriceFeed } from "../helper/MockPriceFeed.sol";

abstract contract GenericDepositorIntegrationTest is Test {
    GenericDepositor depositor;
    GenericUnit gunit;
    GenericUSD gusd;
    Controller controller;
    SingleStrategyVault vault;

    MockBridgeCoordinatorL1 bridgeCoordinator;
    MockStrategy strategy;
    MockERC20 asset;
    MockPriceFeed priceFeed;

    address feeCollector = makeAddr("feeCollector");
    address rewardsCollector = makeAddr("rewardsCollector");
    address swapper = makeAddr("swapper");
    address yieldDistributor = makeAddr("yieldDistributor");

    address user = makeAddr("user");
    uint16 bridgeType = 1;
    uint256 chainId = 100;
    bytes32 remoteRecipient = bytes32(uint256(uint160(makeAddr("remoteRecipient"))));
    bytes32 destinationWhitelabel = keccak256("destinationWhitelabel");
    bytes bridgeParams = "make it fast!";
    bytes32 messageId = keccak256("magic number");
    bytes32 chainNickname = keccak256("chain of gods");

    function setUp() public virtual {
        asset = new MockERC20(6);
        priceFeed = new MockPriceFeed(0.5e8, 8); // 100 asset -> 50 gunit
        strategy = new MockStrategy(asset);

        controller = Controller(address(new TransparentUpgradeableProxy(address(new Controller()), address(this), "")));
        gunit = new GenericUnit(address(controller), "Generic USD", "GUSD");
        controller.initialize(
            address(this), gunit, rewardsCollector, ISwapper(swapper), IYieldDistributor(yieldDistributor)
        );

        gusd = GenericUSD(
            address(
                new TransparentUpgradeableProxy(
                    address(new GenericUSD()), address(this), abi.encodeCall(GenericUSD.initialize, (gunit))
                )
            )
        );

        controller.grantRole(controller.PRICE_FEED_MANAGER_ROLE(), address(this));
        controller.setPriceFeed(address(asset), priceFeed, 1 hours);

        vault = new SingleStrategyVault(asset, controller, strategy, address(0));

        controller.grantRole(controller.VAULT_MANAGER_ROLE(), address(this));
        controller.addVault(address(vault), BaseController.VaultSettings(type(uint224).max, 0, 10_000), true);

        bridgeCoordinator = new MockBridgeCoordinatorL1(gunit);

        depositor = new GenericDepositor(gunit, bridgeCoordinator);

        bridgeCoordinator.returnMessageId(messageId);

        deal(address(asset), user, 1000e6);
    }
}

contract GenericDepositor_Deposit_IntegrationTest is GenericDepositorIntegrationTest {
    function test_deposit_whenWhitelabelZero() public {
        vm.startPrank(user);
        asset.approve(address(depositor), 100e6);
        uint256 shares = depositor.deposit(asset, address(0), 100e6);
        vm.stopPrank();

        assertEq(shares, 50e18);
        assertEq(gunit.balanceOf(user), shares);
        assertEq(asset.balanceOf(user), 900e6);
        assertEq(asset.balanceOf(address(strategy)), 100e6);
    }

    function test_deposit_whenWhitelabelNotZero() public {
        vm.startPrank(user);
        asset.approve(address(depositor), 100e6);
        uint256 shares = depositor.deposit(asset, address(gusd), 100e6);
        vm.stopPrank();

        assertEq(shares, 50e18);
        assertEq(gunit.balanceOf(address(gusd)), shares);
        assertEq(gusd.balanceOf(user), shares);
        assertEq(asset.balanceOf(user), 900e6);
        assertEq(asset.balanceOf(address(strategy)), 100e6);
    }
}

contract GenericDepositor_Mint_IntegrationTest is GenericDepositorIntegrationTest {
    function test_mint_whenWhitelabelZero() public {
        vm.startPrank(user);
        asset.approve(address(depositor), 100e6);
        uint256 assets = depositor.mint(asset, address(0), 50e18);
        vm.stopPrank();

        assertEq(assets, 100e6);
        assertEq(gunit.balanceOf(user), 50e18);
        assertEq(asset.balanceOf(user), 900e6);
        assertEq(asset.balanceOf(address(strategy)), 100e6);
    }

    function test_mint_whenWhitelabelNotZero() public {
        vm.startPrank(user);
        asset.approve(address(depositor), 100e6);
        uint256 assets = depositor.mint(asset, address(gusd), 50e18);
        vm.stopPrank();

        assertEq(assets, 100e6);
        assertEq(gunit.balanceOf(address(gusd)), 50e18);
        assertEq(gusd.balanceOf(user), 50e18);
        assertEq(asset.balanceOf(user), 900e6);
        assertEq(asset.balanceOf(address(strategy)), 100e6);
    }
}

contract GenericDepositor_DepositAndBridge_IntegrationTest is GenericDepositorIntegrationTest {
    function test_depositAndBridge() public {
        vm.startPrank(user);
        asset.approve(address(depositor), 100e6);
        (uint256 shares, bytes32 msgId) = depositor.depositAndBridge(
            asset, 100e6, bridgeType, chainId, remoteRecipient, destinationWhitelabel, bridgeParams
        );
        vm.stopPrank();

        assertEq(shares, 50e18);
        assertEq(msgId, messageId);
        assertEq(gunit.balanceOf(user), 0);
        assertEq(gunit.balanceOf(address(bridgeCoordinator)), 50e18);
        assertEq(asset.balanceOf(user), 900e6);
        assertEq(asset.balanceOf(address(strategy)), 100e6);
        (
            uint16 bridgeType_,
            uint256 chainId_,
            address onBehalf_,
            bytes32 remoteRecipient_,
            address sourceWhitelabel_,
            bytes32 destinationWhitelabel_,
            uint256 amount_,
            bytes memory bridgeParams_
        ) = bridgeCoordinator.lastBridgeCall();
        assertEq(bridgeType_, bridgeType);
        assertEq(chainId_, chainId);
        assertEq(onBehalf_, user);
        assertEq(remoteRecipient_, remoteRecipient);
        assertEq(sourceWhitelabel_, address(0));
        assertEq(destinationWhitelabel_, destinationWhitelabel);
        assertEq(amount_, 50e18);
        assertEq(bridgeParams_, bridgeParams);
    }
}

contract GenericDepositor_MintAndBridge_IntegrationTest is GenericDepositorIntegrationTest {
    function test_mintAndBridge() public {
        vm.startPrank(user);
        asset.approve(address(depositor), 100e6);
        (uint256 assets, bytes32 msgId) = depositor.mintAndBridge(
            asset, 50e18, bridgeType, chainId, remoteRecipient, destinationWhitelabel, bridgeParams
        );
        vm.stopPrank();

        assertEq(assets, 100e6);
        assertEq(msgId, messageId);
        assertEq(gunit.balanceOf(user), 0);
        assertEq(gunit.balanceOf(address(bridgeCoordinator)), 50e18);
        assertEq(asset.balanceOf(user), 900e6);
        assertEq(asset.balanceOf(address(strategy)), 100e6);
        (
            uint16 bridgeType_,
            uint256 chainId_,
            address onBehalf_,
            bytes32 remoteRecipient_,
            address sourceWhitelabel_,
            bytes32 destinationWhitelabel_,
            uint256 amount_,
            bytes memory bridgeParams_
        ) = bridgeCoordinator.lastBridgeCall();
        assertEq(bridgeType_, bridgeType);
        assertEq(chainId_, chainId);
        assertEq(onBehalf_, user);
        assertEq(remoteRecipient_, remoteRecipient);
        assertEq(sourceWhitelabel_, address(0));
        assertEq(destinationWhitelabel_, destinationWhitelabel);
        assertEq(amount_, 50e18);
        assertEq(bridgeParams_, bridgeParams);
    }
}

contract GenericDepositor_DepositAndPredeposit_IntegrationTest is GenericDepositorIntegrationTest {
    function test_depositAndPredeposit() public {
        vm.startPrank(user);
        asset.approve(address(depositor), 100e6);
        uint256 shares = depositor.depositAndPredeposit(asset, 100e6, chainNickname, remoteRecipient);
        vm.stopPrank();

        assertEq(shares, 50e18);
        assertEq(gunit.balanceOf(user), 0);
        assertEq(gunit.balanceOf(address(bridgeCoordinator)), 50e18);
        assertEq(asset.balanceOf(user), 900e6);
        assertEq(asset.balanceOf(address(strategy)), 100e6);
        (bytes32 chainNickname_, address onBehalf_, bytes32 remoteRecipient_, uint256 amount_) =
            bridgeCoordinator.lastPredepositCall();
        assertEq(chainNickname_, chainNickname);
        assertEq(onBehalf_, user);
        assertEq(remoteRecipient_, remoteRecipient);
        assertEq(amount_, 50e18);
    }
}

contract GenericDepositor_MintAndPredeposit_IntegrationTest is GenericDepositorIntegrationTest {
    function test_mintAndPredeposit() public {
        vm.startPrank(user);
        asset.approve(address(depositor), 100e6);
        uint256 assets = depositor.mintAndPredeposit(asset, 50e18, chainNickname, remoteRecipient);
        vm.stopPrank();

        assertEq(assets, 100e6);
        assertEq(gunit.balanceOf(user), 0);
        assertEq(gunit.balanceOf(address(bridgeCoordinator)), 50e18);
        assertEq(asset.balanceOf(user), 900e6);
        assertEq(asset.balanceOf(address(strategy)), 100e6);
        (bytes32 chainNickname_, address onBehalf_, bytes32 remoteRecipient_, uint256 amount_) =
            bridgeCoordinator.lastPredepositCall();
        assertEq(chainNickname_, chainNickname);
        assertEq(onBehalf_, user);
        assertEq(remoteRecipient_, remoteRecipient);
        assertEq(amount_, 50e18);
    }
}
