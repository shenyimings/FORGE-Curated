// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { Test, console } from "forge-std/Test.sol";
import { Upgrades } from "openzeppelin-foundry-upgrades/Upgrades.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IVeCake } from "../src/interfaces/pancakeswap/IVeCake.sol";
import { UniversalProxy } from "../src/UniversalProxy.sol";
import { RewardDistributionScheduler } from "../src/RewardDistributionScheduler.sol";
import { MockGaugeVoting } from "../src/mock/pancakeswap/MockGaugeVoting.sol";
import { MockIFO } from "../src/mock/pancakeswap/MockIFO.sol";
import { MockCakePlatform } from "../src/mock/stakeDao/MockCakePlatform.sol";
import { MockRevenueSharingPool } from "../src/mock/pancakeswap/MockRevenueSharingPool.sol";
import { MockRevenueSharingPoolGateway } from "../src/mock/pancakeswap/MockRevenueSharingPoolGateway.sol";

/** cmd:
 forge clean && \
 forge build --via-ir && \
 forge test -vvvv --match-contract UniversalProxyTest --via-ir
*/

interface altIVeToken {
  function setWhitelistedCallers(address[] calldata callers, bool ok) external;
  function balanceOf(address) external view returns (uint256);
}

contract UniversalProxyTest is Test {
  using SafeERC20 for IERC20;

  address admin = makeAddr("ADMIN");
  address minter = makeAddr("MINTER");
  address pauser = makeAddr("PAUSER");
  address manager = makeAddr("MANAGER");
  address bot = makeAddr("BOT");
  address recipient = makeAddr("RECIPIENT");
  // BSC CAKE
  IERC20 token = IERC20(0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82);
  // veCake owner
  address veCakeOwner = 0xe6cdC66A96458FbF11F632B50964153fBDa78548;
  // BSC veCake
  IVeCake veToken = IVeCake(0x5692DB8177a81A6c6afc8084C2976C9933EC1bAB);
  altIVeToken altVeToken = altIVeToken(0x5692DB8177a81A6c6afc8084C2976C9933EC1bAB);
  MockGaugeVoting gaugeVoting;
  MockIFO ifo;
  RewardDistributionScheduler rewardDistributionScheduler;
  UniversalProxy universalProxy;
  MockRevenueSharingPoolGateway revenueSharingPoolGateway;
  address[] revenueSharingPools;
  address cakePlatform;
  uint256 maxLockDuration;
  // For IFO, we set IFO token as TON for example
  uint8 pid = 1;
  address ifoToken = 0x76A797A59Ba2C17726896976B7B3747BfD1d220f;

  function setUp() public {
    // fork mainnet
    vm.createSelectFork("https://rpc.ankr.com/bsc");

    // minter's functionality please refer to Minter.t.sol
    // give 10000 tokens to minter
    deal(address(token), minter, 10000 ether);

    // deploy deploy gaugeVoting
    gaugeVoting = new MockGaugeVoting();
    console.log("Mock GaugeVoting address: %s", address(gaugeVoting));

    // deploy ifo
    ifo = new MockIFO(pid, ifoToken);
    // give ifo pool 1000 token
    deal(address(ifoToken), address(ifo), 1000 ether);
    console.log("Mock IFO address: %s", address(ifo));

    // deploy rewardDistributionScheduler proxy
    address rdsProxy = Upgrades.deployUUPSProxy(
      "RewardDistributionScheduler.sol",
      abi.encodeCall(RewardDistributionScheduler.initialize, (admin, address(token), minter, manager, pauser))
    );
    rewardDistributionScheduler = RewardDistributionScheduler(address(rdsProxy));
    console.log("RewardDistributionScheduler address: %s", address(rdsProxy));

    // deploy revenueSharingPools
    revenueSharingPools = new address[](2);
    revenueSharingPools[0] = address(new MockRevenueSharingPool(address(token)));
    revenueSharingPools[1] = address(new MockRevenueSharingPool(address(token)));
    // give some reward token to pools
    deal(address(token), revenueSharingPools[0], 1000 ether);
    deal(address(token), revenueSharingPools[1], 1000 ether);

    // deploy RevenueSharingPoolGateway
    revenueSharingPoolGateway = new MockRevenueSharingPoolGateway();

    // deploy cakePlatform
    cakePlatform = address(new MockCakePlatform(address(token)));
    console.log("Mock CakePlatform address: %s", address(cakePlatform));
    deal(address(token), cakePlatform, 1000 ether);

    // deploy UniversalProxy's Proxy
    address upProxy = Upgrades.deployUUPSProxy(
      "UniversalProxy.sol",
      abi.encodeCall(
        UniversalProxy.initialize,
        (
          admin,
          pauser,
          minter,
          bot,
          manager,
          address(token),
          address(veToken),
          address(gaugeVoting),
          address(ifo),
          address(rewardDistributionScheduler),
          revenueSharingPools,
          address(revenueSharingPoolGateway),
          address(cakePlatform)
        )
      )
    );
    console.log("UniversalProxy address: %s", upProxy);
    universalProxy = UniversalProxy(address(upProxy));

    // grant universalProxy as admin of rewardDistributionScheduler
    vm.startPrank(admin);
    rewardDistributionScheduler.grantRole(rewardDistributionScheduler.MANAGER(), address(universalProxy));
    vm.stopPrank();

    // add universalProxy into veCake whitelist
    address[] memory callers = new address[](1);
    callers[0] = address(universalProxy);
    vm.prank(veCakeOwner);
    altVeToken.setWhitelistedCallers(callers, true);
  }

  function test_minter_lock() public {
    // lock not created
    assertEq(universalProxy.lockCreated(), false);

    // simulate Minter lock tokens in to universalProxy
    vm.startPrank(minter);
    // approve 100 tokens to universalProxy
    token.approve(address(universalProxy), 100 ether);
    // lock 100 tokens
    universalProxy.lock(100 ether);
    vm.stopPrank();

    // lock is created
    assertEq(universalProxy.lockCreated(), true);
    // no token left
    assertEq(token.balanceOf(address(universalProxy)), 0);
    // veCake balance > 0
    assertGt(altVeToken.balanceOf(address(universalProxy)), 0);
  }

  function test_cast_vote() public {
    // lock token first
    this.test_minter_lock();
    // PEPE-WBNB gauge at PCS
    address[] memory gauges = new address[](1);
    gauges[0] = address(0xdD82975ab85E745c84e497FD75ba409Ec02d4739);
    uint256[] memory weights = new uint256[](1);
    weights[0] = 500;
    uint256[] memory chainIds = new uint256[](1);
    chainIds[0] = 56;
    // cast vote
    vm.prank(manager);
    universalProxy.castVote(gauges, weights, chainIds, false, false);
  }

  function test_claim_veToken_rewards() public {
    vm.prank(bot);
    universalProxy.claimVeTokenRewards();
    // rewardDistributionScheduler should receive tokens
    assertEq(
      token.balanceOf(address(rewardDistributionScheduler)),
      20 ether // 10 ethers from each revenueSharingPool
    );
  }

  function test_deposit_IFO() public {
    deal(address(token), manager, 1000 ether);
    // participant ifo
    vm.startPrank(manager);
    token.safeIncreaseAllowance(address(universalProxy), 100 ether);
    universalProxy.depositIFO(pid, 100 ether);
    vm.stopPrank();
  }

  function test_harvest_IFO() public {
    // participant ifo
    vm.prank(manager);
    universalProxy.harvestIFO(pid, address(ifoToken));
    // TON token should be transferred to admin
    assertEq(IERC20(ifoToken).balanceOf(manager), 1000 ether);
  }

  function test_claim_from_stakeDao() public {
    uint256[] memory bountyIds = new uint256[](1);
    bountyIds[0] = 1;
    vm.startPrank(manager);
    universalProxy.setRecipient(recipient);
    universalProxy.claimRewardsFromStakeDao(bountyIds);
    vm.stopPrank();
    // cake platform will distribute 10 tokens to each recipient
    assertEq(token.balanceOf(recipient), 10 ether);
  }
}
