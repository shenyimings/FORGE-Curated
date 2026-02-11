// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { Test, console } from "forge-std/Test.sol";
import { Upgrades } from "openzeppelin-foundry-upgrades/Upgrades.sol";
import { Buyback } from "../src/Buyback.sol";
import { MockERC20 } from "../src/mock/MockERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../src/interfaces/IBuyback.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "../src/mock/oneinch/MockAggregationRouterV6.sol";
import "../src/mock/oneinch/MockAggregationExecutor.sol";

contract AggregationRouterV6Test is Test {
  using Address for address payable;
  Buyback public buyback;
  address public manager = makeAddr("MANAGER");
  address public admin = makeAddr("ADMIN");
  address public pauser = makeAddr("PAUSER");
  address public bot = makeAddr("BOT");

  address public receiver = makeAddr("receiver");
  MockAggregationRouterV6 public oneInchRouter;
  MockERC20 public swapDstToken;
  MockERC20 public swapSrcToken;
  address public immutable SWAP_NATIVE_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
  address public swapSrcNative = SWAP_NATIVE_ADDRESS;

  address public user1 = address(0xACC4);

  function setUp() public {
    vm.startPrank(user1);

    swapSrcToken = new MockERC20("DOGE", "DOGE");
    swapDstToken = new MockERC20("CAKE", "CAKE");
    oneInchRouter = new MockAggregationRouterV6(SWAP_NATIVE_ADDRESS);

    // deploy buyback with user1
    address buybackProxy = Upgrades.deployUUPSProxy(
      "Buyback.sol",
      abi.encodeCall(
        Buyback.initialize,
        (admin, manager, pauser, address(swapDstToken), address(receiver), address(oneInchRouter), SWAP_NATIVE_ADDRESS)
      )
    );
    buyback = Buyback(payable(buybackProxy));
    console.log("buyback proxy address: %s", buybackProxy);
    vm.stopPrank();

    //grant access
    vm.startPrank(admin);
    buyback.grantRole(buyback.BOT(), bot);
    vm.stopPrank();

    // add swapSrcToken
    vm.startPrank(manager);
    deal(address(swapSrcToken), buybackProxy, 10000 ether);
    deal(buybackProxy, 10000 ether);
    deal(address(swapDstToken), address(oneInchRouter), 10000 ether);

    buyback.addSwapSrcTokenWhitelist(address(swapSrcToken));
    assertEq(buyback.swapSrcTokenWhitelist(address(swapSrcToken)), true);

    buyback.addSwapSrcTokenWhitelist(swapSrcNative);

    vm.stopPrank();
  }

  /**
   * @dev test buyback
   */
  function testBuybackSuccess() public {
    //contract no pause
    vm.startPrank(admin);
    if (buyback.paused() == true) {
      buyback.unpause();
      assertEq(buyback.paused(), false);
    }
    vm.stopPrank();

    vm.startPrank(bot);
    uint256 beforeTotalBought = buyback.totalBought();
    uint256 beforeReceiverBalance = IERC20(swapDstToken).balanceOf(receiver);
    uint256 beforeBuybackBalance = IERC20(swapSrcToken).balanceOf(address(buyback));
    uint256 today = (block.timestamp / 1 days) * 1 days;
    uint256 beforeDailyBought = buyback.dailyBought(today);
    uint256 beforeDstTokenOneInchRouter = IERC20(swapDstToken).balanceOf(address(oneInchRouter));

    IBuyback.SwapDescription memory swapDesc = IBuyback.SwapDescription({
      srcToken: IERC20(swapSrcToken),
      dstToken: IERC20(swapDstToken),
      srcReceiver: payable(receiver),
      dstReceiver: payable(receiver),
      amount: 1 ether,
      minReturnAmount: 1 ether,
      flags: 0
    });

    bytes memory swapData = abi.encode(IAggregationExecutor(new MockAggregationExecutor()), swapDesc, "");

    buyback.buyback(address(oneInchRouter), bytes.concat(buyback.SWAP_SELECTOR(), swapData));

    uint256 afterTotalBought = buyback.totalBought();
    uint256 afterReceiverBalance = IERC20(swapDstToken).balanceOf(receiver);
    uint256 afterBuybackBalance = IERC20(swapSrcToken).balanceOf(address(buyback));
    uint256 afterDailyBought = buyback.dailyBought(today);
    uint256 afterDstTokenOneInchRouter = IERC20(swapDstToken).balanceOf(address(oneInchRouter));

    uint256 diffTotalBought = afterTotalBought - beforeTotalBought;
    uint256 diffReceiverBalance = afterReceiverBalance - beforeReceiverBalance;
    uint256 diffBuybackBalance = beforeBuybackBalance - afterBuybackBalance;
    uint256 diffDailyBought = afterDailyBought - beforeDailyBought;
    uint256 diffDstTokenOneInchRouter = beforeDstTokenOneInchRouter - afterDstTokenOneInchRouter;

    assertEq(diffTotalBought, diffReceiverBalance);
    assertEq(diffDailyBought, diffReceiverBalance);
    assertEq(diffBuybackBalance, swapDesc.amount);
    assertGe(diffReceiverBalance, swapDesc.minReturnAmount);
    assertEq(diffDstTokenOneInchRouter, swapDesc.minReturnAmount);

    vm.stopPrank();
  }

  /**
   * @dev test buyback
   */
  function testBuybackNativeSuccess() public {
    //contract no pause
    vm.startPrank(admin);
    if (buyback.paused() == true) {
      buyback.unpause();
      assertEq(buyback.paused(), false);
    }
    vm.stopPrank();

    vm.startPrank(bot);
    uint256 beforeTotalBought = buyback.totalBought();
    uint256 beforeReceiverBalance = IERC20(swapDstToken).balanceOf(receiver);
    uint256 beforeBuybackBalance = address(buyback).balance;
    uint256 today = (block.timestamp / 1 days) * 1 days;
    uint256 beforeDailyBought = buyback.dailyBought(today);
    uint256 beforeDstTokenOneInchRouter = IERC20(swapDstToken).balanceOf(address(oneInchRouter));

    IBuyback.SwapDescription memory swapDesc = IBuyback.SwapDescription({
      srcToken: IERC20(swapSrcNative),
      dstToken: IERC20(swapDstToken),
      srcReceiver: payable(receiver),
      dstReceiver: payable(receiver),
      amount: 1 ether,
      minReturnAmount: 1 ether,
      flags: 0
    });

    bytes memory swapData = abi.encode(IAggregationExecutor(new MockAggregationExecutor()), swapDesc, "");

    buyback.buyback(address(oneInchRouter), bytes.concat(buyback.SWAP_SELECTOR(), swapData));

    uint256 afterTotalBought = buyback.totalBought();
    uint256 afterReceiverBalance = IERC20(swapDstToken).balanceOf(receiver);
    uint256 afterBuybackBalance = address(buyback).balance;
    uint256 afterDailyBought = buyback.dailyBought(today);
    uint256 afterDstTokenOneInchRouter = IERC20(swapDstToken).balanceOf(address(oneInchRouter));

    uint256 diffTotalBought = afterTotalBought - beforeTotalBought;
    uint256 diffReceiverBalance = afterReceiverBalance - beforeReceiverBalance;
    uint256 diffBuybackBalance = beforeBuybackBalance - afterBuybackBalance;
    uint256 diffDailyBought = afterDailyBought - beforeDailyBought;
    uint256 diffDstTokenOneInchRouter = beforeDstTokenOneInchRouter - afterDstTokenOneInchRouter;

    assertEq(diffTotalBought, diffReceiverBalance);
    assertEq(diffDailyBought, diffReceiverBalance);
    assertEq(diffBuybackBalance, swapDesc.amount);
    assertGe(diffReceiverBalance, swapDesc.minReturnAmount);
    assertEq(diffDstTokenOneInchRouter, swapDesc.minReturnAmount);

    vm.stopPrank();
  }
}
