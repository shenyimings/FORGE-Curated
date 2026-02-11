// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;
pragma abicoder v2;

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

/** cmd:
 forge clean && \
 forge build --via-ir && \
 forge test -vvvv --match-contract MinterTest --via-ir
*/

contract MinterTest is Test {
  using SafeERC20 for IERC20;
  Minter public minter;
  UniversalProxy universalProxy;
  MockERC20 public token;
  AssToken public assToken;
  MockPancakeStableSwapRouter public pancakeSwapRouter;
  MockPancakeStableSwapPool public pancakeSwapPool;
  MockVeCake public veToken;
  address manager = makeAddr("MANAGER");
  address pauser = makeAddr("PAUSER");
  address bot = makeAddr("BOT");
  address compounder = makeAddr("COMPOUNDER");

  address public admin = address(0xACC0);
  address public user1 = address(0xACC1);
  address public user2 = address(0xACC2);
  address public user3 = address(0xACC3);

  // Prepare Fee Ratio
  // (10_000 = 100%)
  uint256 public veTokenRewardsFeeRate = 1000;
  uint256 public voteRewardsFeeRate = 2000;
  uint256 public donateRewardsFeeRate = 3000;

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
    //    assToken.mint(address(pancakeSwapPool), 1000 ether);
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

    // set compounder role for compounder
    minter.grantRole(minter.COMPOUNDER(), compounder);

    vm.stopPrank();
  }

  /**
   * @dev test smartMint  assToken/token=1
   */
  function testSmartMintSuccess_assToken_vs_token_eq_1() public {
    //(tokens * (assTokenTotalSupply+1)) / (totalTokens+1);
    uint256 convertToAssTokens = minter.convertToAssTokens(1 ether);
    uint256 convertToTokens = minter.convertToTokens(convertToAssTokens);
    assertEq(convertToAssTokens, 1 ether);
    assertEq(convertToTokens, 1 ether);
    smartMintSuccess(10 ether, 1_0000);
  }

  /**
   * @dev test smartMint swap assToken/token<1
   */
  function testSmartMintSuccess_swap_assToken_vs_token_lt_1() public {
    smartMintSuccess(10 ether, 1_0000); //assTokenTotalSupply =10，TotalTokens=10
    compoundRewardsSuccess(10 ether); //assTokenTotalSupply =10，TotalTokens=10+9
    //(tokens * (assTokenTotalSupply+1)) / (totalTokens+1);
    uint256 convertToAssTokens = minter.convertToAssTokens(1 ether);
    assertNotEq(convertToAssTokens, 1 ether);

    vm.startPrank(user1);
    token.transfer(address(pancakeSwapPool), 11 ether);
    assToken.transfer(address(pancakeSwapPool), 10 ether);
    uint256 tokenAmount = 11 ether;
    uint256 assTokenAmount = 10 ether;
    pancakeSwapPool.setExchangeRate((assTokenAmount * 1e5) / tokenAmount);
    vm.stopPrank();

    smartMintSuccess(1 ether, 1_000);
  }

  /**
   * @dev test smartMint swap assToken/token>1
   */
  function testSmartMintSuccess_swap_assToken_vs_token_gt_1() public {
    smartMintSuccess(10 ether, 1_0000); //assTokenTotalSupply =10，TotalTokens=10
    compoundRewardsSuccess(10 ether); //assTokenTotalSupply =10，TotalTokens=10+9
    //(tokens * (assTokenTotalSupply+1)) / (totalTokens+1);
    uint256 convertToAssTokens = minter.convertToAssTokens(1 ether);
    assertNotEq(convertToAssTokens, 1 ether);

    vm.startPrank(user1);
    token.transfer(address(pancakeSwapPool), 9 ether);
    assToken.transfer(address(pancakeSwapPool), 10 ether);
    uint256 tokenAmount = 9 ether;
    uint256 assTokenAmount = 10 ether;
    pancakeSwapPool.setExchangeRate((assTokenAmount * 1e5) / tokenAmount);
    vm.stopPrank();

    smartMintSuccess(10 ether, 1_000);
  }

  /**
   * @dev test smartMint
   */
  function smartMintSuccess(uint256 amountIn, uint256 mintRatio) private {
    //(tokens * (assTokenTotalSupply+1)) / (totalTokens+1);
    uint256 convertToAssTokens = minter.convertToAssTokens(1 ether);
    uint256 swapToAssTokens = minter.swapToAssTokens(1 ether);

    console.log("convertToAssTokens:%s", convertToAssTokens);
    console.log("swapToAssTokens:%s", convertToAssTokens);

    vm.startPrank(user1);
    1 ether;
    // mint AssTokenAmount + buyback AssTokenAmount
    uint256 userReceiveAssTokenAmount = (((convertToAssTokens * amountIn) / 1 ether) * mintRatio) /
      minter.DENOMINATOR() +
      ((amountIn - (amountIn * mintRatio) / minter.DENOMINATOR()) * swapToAssTokens) /
      1 ether;
    uint256 estimateTotalOut = minter.estimateTotalOut(amountIn, mintRatio);
    assertEq(estimateTotalOut, userReceiveAssTokenAmount);
    token.approve(address(minter), amountIn);

    uint256 beforeTotalTokens = minter.totalTokens();
    uint256 beforeMinterBalance = IERC20(token).balanceOf(address(minter));

    minter.smartMint(amountIn, mintRatio, userReceiveAssTokenAmount);

    uint256 afterTotalTokens = minter.totalTokens();
    uint256 afterMinterBalance = IERC20(token).balanceOf(address(minter));

    assertEq(afterTotalTokens - beforeTotalTokens, (amountIn * mintRatio) / minter.DENOMINATOR());
    assertEq(afterMinterBalance - beforeMinterBalance, 0);

    uint256 assTokenTotalSupply = IERC20(assToken).totalSupply();

    //(tokens * (totalSupply+1)) / (totalTokens+1)
    assertEq((1 ether * (assTokenTotalSupply + 1)) / (afterTotalTokens + 1), minter.convertToAssTokens(1 ether));

    //(assTokens * (totalTokens+1)) / (totalSupply+1)
    assertEq((1 ether * (afterTotalTokens + 1)) / (assTokenTotalSupply + 1), minter.convertToTokens(1 ether));

    vm.stopPrank();
  }

  /**
   * @dev test estimateTotalOut
   */
  function testEstimateTotalOut() public {
    //default assTokenTotalSupply=1000 ether

    //Incorrect Ratio
    uint256 amountIn = 100 ether;
    uint256 estimateTotalOut = 0;
    vm.expectRevert("Incorrect Ratio");
    estimateTotalOut = minter.estimateTotalOut(amountIn, 10_0000);

    uint256 convertToAssTokens = minter.convertToAssTokens(1 ether);
    uint256 convertToTokens = minter.convertToTokens(convertToAssTokens);
    assertEq(convertToTokens, 1 ether);
    console.log("convertToAssTokens:%s", convertToAssTokens);

    vm.startPrank(user1);

    uint256 mintRatio = 0;
    uint256 mintAssTokenAmount = (((convertToAssTokens * amountIn) / 1 ether) * mintRatio) / minter.DENOMINATOR();
    uint256 buybackAssTokenAmount = amountIn - (amountIn * mintRatio) / minter.DENOMINATOR();

    //_mintRatio=0
    estimateTotalOut = minter.estimateTotalOut(amountIn, mintRatio);
    assertEq(estimateTotalOut, mintAssTokenAmount + buybackAssTokenAmount);

    //_mintRatio=1_0000
    mintRatio = 1_0000;
    mintAssTokenAmount = (((convertToAssTokens * amountIn) / 1 ether) * mintRatio) / minter.DENOMINATOR();
    buybackAssTokenAmount = amountIn - (amountIn * mintRatio) / minter.DENOMINATOR();
    estimateTotalOut = minter.estimateTotalOut(amountIn, mintRatio);
    assertEq(estimateTotalOut, mintAssTokenAmount + buybackAssTokenAmount);

    //_mintRatio=5000
    mintRatio = 5000;
    mintAssTokenAmount = (((convertToAssTokens * amountIn) / 1 ether) * mintRatio) / minter.DENOMINATOR();
    buybackAssTokenAmount = amountIn - (amountIn * mintRatio) / minter.DENOMINATOR();
    estimateTotalOut = minter.estimateTotalOut(amountIn, mintRatio);
    assertEq(estimateTotalOut, mintAssTokenAmount + buybackAssTokenAmount);
  }

  /**
   * @dev test swapToAssTokens
   */
  function testSwapToAssTokens() public {
    uint256 swapToAssTokens = minter.swapToAssTokens(1 ether);
    assertEq(swapToAssTokens, 1 ether);
  }

  /**
   * @dev test convertToTokens
   */
  function testConvertToTokens() public {
    //default assTokenTotalSupply=1000 ether
    uint256 convertToTokens = minter.convertToTokens(1 ether);
    assertEq(convertToTokens, 1 ether);
  }

  /**
   * @dev test compoundRewards
   */
  function testCompoundRewardsSuccess() public {
    compoundRewardsSuccess(100 ether);
  }

  /**
   * @dev  compoundRewards
   */
  function compoundRewardsSuccess(uint256 amountIn) public {
    vm.startPrank(manager);
    minter.updateFeeRate(IMinter.RewardsType.VeTokenRewards, veTokenRewardsFeeRate);
    minter.updateFeeRate(IMinter.RewardsType.VoteRewards, voteRewardsFeeRate);
    minter.updateFeeRate(IMinter.RewardsType.Donate, donateRewardsFeeRate);
    vm.stopPrank();

    // rewards type array
    IMinter.RewardsType[] memory rewardsTypes = new IMinter.RewardsType[](3);
    rewardsTypes[0] = IMinter.RewardsType.VeTokenRewards;
    rewardsTypes[1] = IMinter.RewardsType.VoteRewards;
    rewardsTypes[2] = IMinter.RewardsType.Donate;
    // total rewards per type array
    uint256[] memory totalRewards = new uint256[](3);
    totalRewards[0] = amountIn;
    totalRewards[1] = amountIn;
    totalRewards[2] = amountIn;

    vm.startPrank(compounder);
    deal(address(token), compounder, amountIn * 3);

    uint256 beforeTotalFee = minter.totalFee();
    uint256 beforeTotalTokens = minter.totalTokens();

    IERC20(token).safeIncreaseAllowance(address(minter), amountIn * 3);
    minter.compoundRewards(rewardsTypes, totalRewards);

    // vesting after 1 hour
    skip(3600);

    // verify fee
    uint256 fee = (amountIn * veTokenRewardsFeeRate) /
      minter.DENOMINATOR() +
      (amountIn * voteRewardsFeeRate) /
      minter.DENOMINATOR() +
      (amountIn * donateRewardsFeeRate) /
      minter.DENOMINATOR();
    // verify fee
    assertEq(minter.totalFee() - beforeTotalFee, fee);
    // verify total tokens
    assertEq(minter.totalTokens() - beforeTotalTokens, amountIn * 3 - minter.getUnvestedAmount() - fee);

    uint256 assTokenTotalSupply = IERC20(assToken).totalSupply();

    //(tokens * totalSupply) / totalTokens
    assertEq((1 ether * (assTokenTotalSupply + 1)) / (minter.totalTokens() + 1), minter.convertToAssTokens(1 ether));
    //(assTokens * (totalTokens+1)) / (totalSupply+1)
    assertEq((1 ether * (minter.totalTokens() + 1)) / (assTokenTotalSupply + 1), minter.convertToTokens(1 ether));

    vm.stopPrank();
  }

  function testFeeAfterCompoundSuccess() public {
    uint256 amountIn = 100 ether;

    uint256 beforeVeTokenRewards = minter.totalRewards(IMinter.RewardsType.VeTokenRewards);
    uint256 beforeVoteRewards = minter.totalRewards(IMinter.RewardsType.VoteRewards);
    uint256 beforeDonate = minter.totalRewards(IMinter.RewardsType.Donate);

    compoundRewardsSuccess(amountIn);

    uint256 afterVeTokenRewards = minter.totalRewards(IMinter.RewardsType.VeTokenRewards);
    uint256 afterVoteRewards = minter.totalRewards(IMinter.RewardsType.VoteRewards);
    uint256 afterDonate = minter.totalRewards(IMinter.RewardsType.Donate);

    assertEq(
      afterVeTokenRewards - beforeVeTokenRewards,
      amountIn - (amountIn * veTokenRewardsFeeRate) / minter.DENOMINATOR()
    );
    assertEq(afterVoteRewards - beforeVoteRewards, amountIn - (amountIn * voteRewardsFeeRate) / minter.DENOMINATOR());
    assertEq(afterDonate - beforeDonate, amountIn - (amountIn * donateRewardsFeeRate) / minter.DENOMINATOR());
  }

  /**
   * @dev test compoundRewards
   */
  function testCompoundRewardsFail() public {
    // rewards type array
    IMinter.RewardsType[] memory rewardsTypes = new IMinter.RewardsType[](3);
    rewardsTypes[0] = IMinter.RewardsType.VeTokenRewards;
    rewardsTypes[1] = IMinter.RewardsType.VoteRewards;
    rewardsTypes[2] = IMinter.RewardsType.Donate;
    // total rewards per type array
    uint256[] memory totalRewards = new uint256[](3);
    totalRewards[0] = 0;
    totalRewards[1] = 0;
    totalRewards[2] = 0;

    //user no access
    vm.expectRevert();
    minter.compoundRewards(rewardsTypes, totalRewards);

    //Invalid amount
    vm.startPrank(compounder);
    vm.expectRevert("Invalid compound amount");
    minter.compoundRewards(rewardsTypes, totalRewards);
    vm.stopPrank();
  }

  /**
   * @dev test updateFeeRate
   */
  function testUpdateFeeRate() public {
    //user no access
    vm.expectRevert();
    minter.updateFeeRate(IMinter.RewardsType.VoteRewards, 1000);

    //Incorrect Fee Ratio
    vm.startPrank(manager);
    vm.expectRevert("Incorrect Fee Ratio");
    minter.updateFeeRate(IMinter.RewardsType.VoteRewards, 10_0000);
    vm.stopPrank();

    //update VoteRewards(newFeeRate can not be equal oldFeeRate)
    vm.startPrank(manager);
    minter.updateFeeRate(IMinter.RewardsType.VoteRewards, 9999);
    vm.expectRevert("newFeeRate can not be equal oldFeeRate");
    minter.updateFeeRate(IMinter.RewardsType.VoteRewards, 9999);
    vm.stopPrank();

    //update VeTokenRewards(newFeeRate can not be equal oldFeeRate)
    vm.startPrank(manager);
    minter.updateFeeRate(IMinter.RewardsType.VeTokenRewards, 9999);
    vm.expectRevert("newFeeRate can not be equal oldFeeRate");
    minter.updateFeeRate(IMinter.RewardsType.VeTokenRewards, 9999);
    vm.stopPrank();

    //update Donate(newFeeRate can not be equal oldFeeRate)
    vm.startPrank(manager);
    minter.updateFeeRate(IMinter.RewardsType.Donate, 9999);
    vm.expectRevert("newFeeRate can not be equal oldFeeRate");
    minter.updateFeeRate(IMinter.RewardsType.Donate, 9999);
    vm.stopPrank();

    //update VoteRewards success
    vm.startPrank(manager);
    minter.updateFeeRate(IMinter.RewardsType.VoteRewards, voteRewardsFeeRate);
    assertEq(minter.voteRewardsFeeRate(), voteRewardsFeeRate);
    vm.stopPrank();

    //update VeTokenRewards success
    vm.startPrank(manager);
    minter.updateFeeRate(IMinter.RewardsType.VeTokenRewards, veTokenRewardsFeeRate);
    assertEq(minter.veTokenRewardsFeeRate(), veTokenRewardsFeeRate);
    vm.stopPrank();

    //update Donate success
    vm.startPrank(manager);
    minter.updateFeeRate(IMinter.RewardsType.Donate, donateRewardsFeeRate);
    assertEq(minter.donateRewardsFeeRate(), donateRewardsFeeRate);
    vm.stopPrank();
  }

  /**
   * @dev test withdrawFee
   */
  function testWithdrawFee() public {
    address receipt = makeAddr("receipt");
    uint256 amountIn = 100 ether;
    //user no access
    vm.expectRevert();
    minter.withdrawFee(receipt, amountIn);

    //receipt is null
    vm.startPrank(manager);
    vm.expectRevert("Invalid address");
    minter.withdrawFee(address(0), amountIn);
    vm.stopPrank();

    //amountIn=0
    vm.startPrank(manager);
    vm.expectRevert("Invalid amount");
    minter.withdrawFee(receipt, 0);
    vm.stopPrank();

    uint256 totalFee = minter.totalFee();
    totalFee += 1;
    //amountIn > totalFee
    vm.startPrank(manager);
    vm.expectRevert("Invalid amount");
    minter.withdrawFee(receipt, totalFee);
    vm.stopPrank();

    // compound rewards
    compoundRewardsSuccess(amountIn);

    vm.startPrank(manager);

    uint256 beforeTotalFee = minter.totalFee();
    uint256 beforeMinterBalance = IERC20(token).balanceOf(address(minter));
    uint256 beforeReceiptBalance = IERC20(token).balanceOf(receipt);

    console.log("beforeTotalFee:%s", beforeTotalFee);
    console.log("beforeMinterBalance:%s", beforeMinterBalance);

    // withdraw all
    uint256 withdrawAmt = beforeTotalFee;
    minter.withdrawFee(receipt, withdrawAmt);

    assertEq(beforeTotalFee - minter.totalFee(), withdrawAmt);
    assertEq(beforeMinterBalance - IERC20(token).balanceOf(address(minter)), withdrawAmt);

    vm.stopPrank();
  }

  /**
   * @dev test changePancakeSwapRouter
   */
  function testChangePancakeSwapRouter() public {
    address pancakeSwapRouterAddress = makeAddr("PancakeSwapRouter");
    //user no access
    vm.expectRevert();
    minter.changePancakeSwapRouter(pancakeSwapRouterAddress);

    //zero address
    vm.startPrank(manager);
    vm.expectRevert("_pancakeSwapRouter is the zero address");
    minter.changePancakeSwapRouter(address(0));
    vm.stopPrank();

    //change success
    vm.startPrank(manager);
    minter.changePancakeSwapRouter(pancakeSwapRouterAddress);
    assertEq(minter.pancakeSwapRouter(), pancakeSwapRouterAddress);
    vm.stopPrank();

    //duplicate change
    vm.startPrank(manager);
    assertEq(minter.pancakeSwapRouter(), pancakeSwapRouterAddress);
    vm.expectRevert("_pancakeSwapRouter is the same");
    minter.changePancakeSwapRouter(pancakeSwapRouterAddress);
    vm.stopPrank();
  }

  /**
   * @dev test changePancakeSwapPool
   */
  function testChangePancakeSwapPool() public {
    address pancakeSwapPoolAddress = makeAddr("PancakeSwapPool");
    //user no access
    vm.expectRevert();
    minter.changePancakeSwapPool(pancakeSwapPoolAddress);

    //zero address
    vm.startPrank(manager);
    vm.expectRevert("_pancakeSwapPool is the zero address");
    minter.changePancakeSwapPool(address(0));
    vm.stopPrank();

    //change success
    vm.startPrank(manager);
    minter.changePancakeSwapPool(pancakeSwapPoolAddress);
    assertEq(minter.pancakeSwapPool(), pancakeSwapPoolAddress);
    vm.stopPrank();

    //duplicate change
    vm.startPrank(manager);
    assertEq(minter.pancakeSwapPool(), pancakeSwapPoolAddress);
    vm.expectRevert("_pancakeSwapPool is the same");
    minter.changePancakeSwapPool(pancakeSwapPoolAddress);
    vm.stopPrank();
  }

  /**
   * @dev test testChangeMaxSwapRatio
   */
  function testChangeMaxSwapRatio() public {
    uint256 maxSwapRatio = 99;
    //user no access
    vm.expectRevert();
    minter.changeMaxSwapRatio(maxSwapRatio);

    //zero address
    vm.startPrank(manager);
    vm.expectRevert("Invalid max swap ratio");
    minter.changeMaxSwapRatio(10_0000);
    vm.stopPrank();

    //change success
    vm.startPrank(manager);
    minter.changeMaxSwapRatio(maxSwapRatio);
    assertEq(minter.maxSwapRatio(), maxSwapRatio);
    vm.stopPrank();

    //duplicate change
    vm.startPrank(manager);
    if (minter.maxSwapRatio() != maxSwapRatio) {
      minter.changeMaxSwapRatio(maxSwapRatio);
    }
    assertEq(minter.maxSwapRatio(), maxSwapRatio);

    vm.expectRevert("_maxSwapRatio is the same");
    minter.changeMaxSwapRatio(maxSwapRatio);
    vm.stopPrank();
  }

  /**
   * @dev test Flips the pause state
   */
  function testTogglePause() public {
    //user no access
    vm.expectRevert();
    minter.unpause();

    // pause contract
    vm.startPrank(pauser);
    minter.pause();
    assertEq(minter.paused(), true);
    vm.stopPrank();

    // unpause contract
    vm.startPrank(manager);
    minter.unpause();
    assertEq(minter.paused(), false);
    vm.stopPrank();
  }

  /**
   * @dev test pause the contract
   */
  function testPause() public {
    //user no access
    vm.expectRevert();
    minter.pause();

    //pauser no access
    vm.startPrank(pauser);
    vm.expectRevert();
    minter.unpause();
    vm.stopPrank();

    //grant access
    vm.startPrank(admin);
    minter.grantRole(minter.DEFAULT_ADMIN_ROLE(), pauser);
    vm.stopPrank();

    //togglePause success
    vm.startPrank(pauser);
    minter.pause();
    assertEq(minter.paused(), true);
    vm.stopPrank();
  }

  /**
   * @dev test upgrade
   */
  function testUpgrade() public {
    address proxyAddress = address(minter);
    address implAddressV1 = Upgrades.getImplementationAddress(proxyAddress);

    vm.expectRevert();
    Upgrades.upgradeProxy(proxyAddress, "Minter.sol", "", msg.sender);

    vm.startPrank(admin);
    Upgrades.upgradeProxy(proxyAddress, "Minter.sol", "", msg.sender);
    address implAddressV2 = Upgrades.getImplementationAddress(proxyAddress);
    assertFalse(implAddressV2 == implAddressV1);
    vm.stopPrank();
    console.log("implAddressV1: %s", implAddressV1);
    console.log("implAddressV2: %s", implAddressV2);
  }
}
