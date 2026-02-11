// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { Test, console } from "forge-std/Test.sol";
import { Upgrades } from "openzeppelin-foundry-upgrades/Upgrades.sol";
import { Minter } from "../src/Minter.sol";
import { IMinter } from "../src/interfaces/IMinter.sol";

import { AssToken } from "../src/AssToken.sol";
import { MockERC20 } from "../src/mock/MockERC20.sol";
import { MockPancakeStableSwapRouter } from "../src/mock/pancakeswap/MockPancakeStableSwapRouter.sol";
import { MockPancakeStableSwapPool } from "../src/mock/pancakeswap/MockPancakeStableSwapPool.sol";
import { MockVeCake } from "../src/mock/pancakeswap/MockVeCake.sol";
import { UniversalProxy } from "../src/UniversalProxy.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../src/interfaces/IRewardDistributionScheduler.sol";
import { RewardDistributionScheduler } from "../src/RewardDistributionScheduler.sol";

contract RewardDistributionSchedulerTest is Test {
  using SafeERC20 for IERC20;
  Minter public minter;
  UniversalProxy universalProxy;
  MockERC20 public token;
  AssToken public assToken;
  MockPancakeStableSwapRouter public pancakeSwapRouter;
  MockPancakeStableSwapPool public pancakeSwapPool;
  MockVeCake public veToken;
  RewardDistributionScheduler public rewardDistributionScheduler;

  address manager = makeAddr("MANAGER");
  address pauser = makeAddr("PAUSER");
  address bot = makeAddr("BOT");
  address compounder = makeAddr("COMPOUNDER");

  address public admin = address(0xACC0);
  address public user1 = address(0xACC1);
  address public user2 = address(0xACC2);
  address public user3 = address(0xACC3);

  function setUp() public {
    // fork mainnet
    vm.createSelectFork("https://rpc.ankr.com/bsc");

    token = new MockERC20("CAKE", "CAKE");
    console.log("token address: %s", address(token));
    token.mint(user1, 10000 ether);
    console.log("user1: %s", user1);

    vm.startPrank(user1);
    // deploy assToken
    address assTokenProxy = Upgrades.deployUUPSProxy(
      "AssToken.sol",
      abi.encodeCall(AssToken.initialize, ("AssCAKE", "AssCAKE", admin, admin))
    );
    console.log("AssTokenProxy address: %", assTokenProxy);
    assToken = AssToken(assTokenProxy);
    console.log("AssToken proxy address: %s", assTokenProxy);
    // deploy mock pancake swap contract
    pancakeSwapPool = new MockPancakeStableSwapPool(address(token), assTokenProxy, 1e5);
    console.log("pancakeSwapPool address: %s", address(pancakeSwapPool));
    // deploy mock pancake swap router
    pancakeSwapRouter = new MockPancakeStableSwapRouter(address(pancakeSwapPool));
    console.log("pancakeSwapRouter address: %s", address(pancakeSwapRouter));
    // transfer cake to swap contract
    token.transfer(address(pancakeSwapPool), 1000 ether);
    // deploy VeCake
    veToken = new MockVeCake(address(token));
    console.log("VeCake address: %s", address(veToken));
    vm.stopPrank();

    vm.startPrank(admin);
    // mint assToken to swap contract
    assToken.mint(address(pancakeSwapPool), 1000 ether);
    vm.stopPrank();

    vm.startPrank(user1);
    // deploy UniversalProxy's Proxy
    address[] memory revenueSharingPools = new address[](1);
    revenueSharingPools[0] = address(token);
    address upProxy = Upgrades.deployUUPSProxy(
      "UniversalProxy.sol",
      abi.encodeCall(
        UniversalProxy.initialize,
        (
          admin,
          pauser,
          admin,
          bot,
          manager,
          address(token),
          address(veToken),
          address(token),
          address(token),
          address(token),
          revenueSharingPools,
          address(token),
          address(token)
        )
      )
    );
    console.log("UniversalProxy address: %s", upProxy);
    universalProxy = UniversalProxy(upProxy);

    uint256 maxSwapRatio = 10000;

    // deploy minter with user1
    address minterProxy = Upgrades.deployUUPSProxy(
      "Minter.sol",
      abi.encodeCall(
        Minter.initialize,
        (
          admin,
          manager,
          pauser,
          address(token),
          assTokenProxy,
          address(upProxy),
          address(pancakeSwapRouter),
          address(pancakeSwapPool),
          maxSwapRatio
        )
      )
    );
    minter = Minter(minterProxy);
    console.log("minter proxy address: %s", minterProxy);
    vm.stopPrank();

    vm.startPrank(admin);
    // set minter for assToken
    assToken.setMinter(minterProxy);
    require(assToken.minter() == minterProxy, "minter not set");

    // set minter role for UniversalProxy
    universalProxy.grantRole(universalProxy.MINTER(), minterProxy);

    vm.stopPrank();

    vm.startPrank(user1);
    // deploy rewardDistributionScheduler with user1
    address rewardDistributionSchedulerProxy = Upgrades.deployUUPSProxy(
      "RewardDistributionScheduler.sol",
      abi.encodeCall(RewardDistributionScheduler.initialize, (admin, address(token), address(minter), manager, pauser))
    );
    rewardDistributionScheduler = RewardDistributionScheduler(rewardDistributionSchedulerProxy);
    console.log("rewardDistributionScheduler proxy address: %s", rewardDistributionSchedulerProxy);
    vm.stopPrank();

    //grant access
    vm.startPrank(admin);
    rewardDistributionScheduler.grantRole(rewardDistributionScheduler.BOT(), bot);
    rewardDistributionScheduler.grantRole(rewardDistributionScheduler.PAUSER(), pauser);
    rewardDistributionScheduler.grantRole(rewardDistributionScheduler.MANAGER(), manager);
    // set compounder role for compounder
    minter.grantRole(minter.COMPOUNDER(), rewardDistributionSchedulerProxy);
    vm.stopPrank();

    deal(address(token), manager, 10000 ether);
  }

  /**
   * @dev test addRewardsSchedule
   */
  function testAddRewardsScheduleFail() public {
    //user no access
    vm.expectRevert();
    rewardDistributionScheduler.addRewardsSchedule(IMinter.RewardsType.VeTokenRewards, 1 ether, 7, block.timestamp);

    //contract pause
    vm.startPrank(pauser);
    if (rewardDistributionScheduler.paused() != true) {
      rewardDistributionScheduler.pause();
    }
    assertEq(rewardDistributionScheduler.paused(), true);
    vm.stopPrank();

    vm.startPrank(manager);
    vm.expectRevert();
    rewardDistributionScheduler.addRewardsSchedule(IMinter.RewardsType.VeTokenRewards, 1 ether, 7, block.timestamp);
    vm.stopPrank();

    //resume contract
    vm.startPrank(manager);
    if (rewardDistributionScheduler.paused() == true) {
      rewardDistributionScheduler.unpause();
    }
    assertEq(rewardDistributionScheduler.paused(), false);
    vm.stopPrank();

    // Invalid amount
    vm.startPrank(manager);
    vm.expectRevert("Invalid amount");
    rewardDistributionScheduler.addRewardsSchedule(IMinter.RewardsType.VeTokenRewards, 0, 7, block.timestamp);
    vm.stopPrank();

    //Invalid epochs
    vm.startPrank(manager);
    vm.expectRevert("Invalid epochs");
    rewardDistributionScheduler.addRewardsSchedule(IMinter.RewardsType.VeTokenRewards, 1 ether, 0, block.timestamp);
    vm.stopPrank();

    //Invalid startTime
    vm.startPrank(manager);
    vm.expectRevert("Invalid startTime");
    rewardDistributionScheduler.addRewardsSchedule(IMinter.RewardsType.VeTokenRewards, 1 ether, 7, 0);
    vm.stopPrank();
  }

  /**
   * @dev test addRewardsSchedule
   */
  function testAddRewardsScheduleSuccess() public {
    uint256 startTime = block.timestamp - 2 days;
    addRewardsScheduleSuccess(IMinter.RewardsType.VeTokenRewards, 7 ether, 7, startTime, 1);
    addRewardsScheduleSuccess(IMinter.RewardsType.VeTokenRewards, 7 ether, 7, startTime, 2);
  }

  /**
   * @dev test addRewardsSchedule
   */
  function addRewardsScheduleSuccess(
    IMinter.RewardsType rewardsType,
    uint256 amount,
    uint256 epochs,
    uint256 startTime,
    uint256 index
  ) public {
    vm.startPrank(manager);

    uint256 beforeManagerBalance = IERC20(token).balanceOf(manager);
    uint256 beforeRewardDistributionSchedulerBalance = IERC20(token).balanceOf(address(rewardDistributionScheduler));
    uint256 beforeLastDistributeRewardsTimestamp = rewardDistributionScheduler.lastDistributeRewardsTimestamp();

    token.approve(address(rewardDistributionScheduler), amount);
    rewardDistributionScheduler.addRewardsSchedule(rewardsType, amount, epochs, startTime);

    startTime = (startTime / 1 days) * 1 days;

    uint256 afterManagerBalance = IERC20(token).balanceOf(manager);
    uint256 afterRewardDistributionSchedulerBalance = IERC20(token).balanceOf(address(rewardDistributionScheduler));

    assertEq(beforeManagerBalance - afterManagerBalance, amount);
    assertEq(afterRewardDistributionSchedulerBalance - beforeRewardDistributionSchedulerBalance, amount);
    assertEq(
      startTime < beforeLastDistributeRewardsTimestamp ? startTime : beforeLastDistributeRewardsTimestamp,
      rewardDistributionScheduler.lastDistributeRewardsTimestamp()
    );

    uint256 amountPerDay = amount / epochs;
    for (uint256 i; i < epochs; i++) {
      console.log("startTime:%s", startTime + i * 1 days);
      assertEq(rewardDistributionScheduler.epochs(startTime + i * 1 days, rewardsType), amountPerDay * index);
    }

    vm.stopPrank();
  }

  /**
   * @dev test executeRewardSchedules
   */
  function testExecuteRewardSchedulesFail() public {
    //user no access
    vm.expectRevert();
    rewardDistributionScheduler.executeRewardSchedules();

    //contract pause
    vm.startPrank(pauser);
    if (rewardDistributionScheduler.paused() != true) {
      rewardDistributionScheduler.pause();
    }
    assertEq(rewardDistributionScheduler.paused(), true);
    vm.stopPrank();

    vm.startPrank(manager);
    vm.expectRevert();
    rewardDistributionScheduler.executeRewardSchedules();
    vm.stopPrank();
  }

  /**
   * @dev test executeRewardSchedules
   */
  function testExecuteRewardSchedulesSuccess() public {
    uint256 startTime = block.timestamp - 2 days;
    //prepare rewards
    addRewardsScheduleSuccess(IMinter.RewardsType.VoteRewards, 7 ether, 7, startTime, 1);
    addRewardsScheduleSuccess(IMinter.RewardsType.VoteRewards, 7 ether, 7, startTime, 2);

    //start
    vm.startPrank(bot);
    startTime = (startTime / 1 days) * 1 days;
    uint256 amount = rewardDistributionScheduler.epochs(startTime, IMinter.RewardsType.VoteRewards);
    uint256 beforeRewardDistributionSchedulerBalance = IERC20(token).balanceOf(address(rewardDistributionScheduler));

    rewardDistributionScheduler.executeRewardSchedules();

    uint256 afterRewardDistributionSchedulerBalance = IERC20(token).balanceOf(address(rewardDistributionScheduler));

    assertEq(beforeRewardDistributionSchedulerBalance - afterRewardDistributionSchedulerBalance, amount * 3);

    startTime = (block.timestamp / 1 days) * 1 days;
    assertEq(rewardDistributionScheduler.lastDistributeRewardsTimestamp(), startTime + 1 days);

    assertEq(rewardDistributionScheduler.epochs(startTime + 1 days, IMinter.RewardsType.VoteRewards), amount);
    assertEq(rewardDistributionScheduler.epochs(startTime, IMinter.RewardsType.VoteRewards), 0);

    assertEq(rewardDistributionScheduler.epochs(startTime - 1 days, IMinter.RewardsType.VoteRewards), 0);

    assertEq(rewardDistributionScheduler.epochs(startTime - 2 days, IMinter.RewardsType.VoteRewards), 0);

    assertEq(rewardDistributionScheduler.epochs(startTime - 3 days, IMinter.RewardsType.VoteRewards), 0);

    vm.stopPrank();
  }

  /**
   * @dev test Flips the pause state
   */
  function testPauseAndUnpause() public {
    //user no access
    vm.expectRevert();
    rewardDistributionScheduler.unpause();

    // pause contract
    vm.startPrank(pauser);
    rewardDistributionScheduler.pause();
    assertEq(rewardDistributionScheduler.paused(), true);
    vm.stopPrank();

    // unpause contract
    vm.startPrank(manager);
    rewardDistributionScheduler.unpause();
    assertEq(rewardDistributionScheduler.paused(), false);
    vm.stopPrank();
  }

  /**
   * @dev test upgrade
   */
  function testUpgrade() public {
    address proxyAddress = address(rewardDistributionScheduler);
    address implAddressV1 = Upgrades.getImplementationAddress(proxyAddress);

    //no access
    vm.expectRevert();
    Upgrades.upgradeProxy(proxyAddress, "RewardDistributionScheduler.sol", "", msg.sender);

    //upgradeProxy success
    vm.startPrank(admin);
    Upgrades.upgradeProxy(proxyAddress, "RewardDistributionScheduler.sol", "", msg.sender);
    address implAddressV2 = Upgrades.getImplementationAddress(proxyAddress);
    assertFalse(implAddressV2 == implAddressV1);
    vm.stopPrank();
    console.log("implAddressV1: %s", implAddressV1);
    console.log("implAddressV2: %s", implAddressV2);
  }
}
