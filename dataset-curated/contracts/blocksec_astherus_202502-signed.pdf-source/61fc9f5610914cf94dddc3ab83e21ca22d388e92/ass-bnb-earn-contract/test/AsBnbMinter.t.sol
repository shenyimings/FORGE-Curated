// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.28;

import { Test, console } from "forge-std/Test.sol";
import { Upgrades } from "openzeppelin-foundry-upgrades/Upgrades.sol";
import { AsBnbMinter } from "../src/AsBnbMinter.sol";
import { IAsBnbMinter } from "../src/interfaces/IAsBnbMinter.sol";
import { YieldProxy } from "../src/YieldProxy.sol";
import { IYieldProxy } from "../src/interfaces/IYieldProxy.sol";
import { AsBnbOFTAdapter } from "../src/oft/AsBnbOFTAdapter.sol";
import { TransferLimiter } from "../src/oft/TransferLimiter.sol";
import { AsBNB } from "../src/AsBNB.sol";
import { MockERC20 } from "../src/mock/MockERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { IOFT, SendParam, OFTReceipt } from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import { MessagingFee, MessagingReceipt } from "@layerzerolabs/oft-evm/contracts/OFTCore.sol";

import { IListaStakeManager } from "../src/interfaces/IListaStakeManager.sol";
import { ISlisBNBProvider } from "../src/interfaces/ISlisBNBProvider.sol";
import { OptionsBuilder } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";

// Run this command to test:
// forge clean && forge build && forge test -vvv --match-contract AsBnbMinterTest
// if you want to run specific test, you can add `--match-function flag` as well

interface IStakeManagerAlt {
  function convertBnbToSnBnb(uint256 _amount) external view returns (uint256);
}

contract AsBnbMinterTest is Test {
  using OptionsBuilder for bytes;
  using SafeERC20 for IERC20;
  using SafeERC20 for AsBNB;

  address admin = makeAddr("ADMIN");
  address manager = makeAddr("MANAGER");
  address pauser = makeAddr("PAUSER");
  address bot = makeAddr("BOT");
  address user = makeAddr("USER");
  address rewardSender = makeAddr("REWARD_SENDER");
  address feeReceiver = makeAddr("FEE_RECEIVER");
  address MPCWallet = makeAddr("MPC_WALLET");

  // --- contracts
  YieldProxy yieldProxy;
  AsBnbMinter minter;
  AsBNB asBnb;
  AsBnbOFTAdapter asBnbOFTAdapter;
  // slisBNB
  IERC20 token = IERC20(0xCc752dC4ae72386986d011c2B485be0DAd98C744);
  // StakeManager - BNB <> slisBNB
  IListaStakeManager listaStakeManager = IListaStakeManager(0xc695F964011a5a1024931E2AF0116afBaC41B31B);
  // slisBNBProvider - slisBNB <> clisBNB
  ISlisBNBProvider slisBNBProvider = ISlisBNBProvider(0x11f6aDcb73473FD7bdd15f32df65Fa3ECdD0Bc20);
  // Sei Chain
  address LZ_Endpoint = 0x6EDCE65403992e310A62460808c4b910D972f10f;
  uint32 SEI_EID = 40258;

  // min. amount to mint
  uint256 minMintAmount = 0.001 ether;

  function setUp() public {
    // fork testnet
    string memory url = vm.envString("TESTNET_RPC");
    vm.createSelectFork(url);

    // deploy AsBNB
    asBnb = new AsBNB("Astherus BNB", "asBNB", admin, admin);

    // deploy yieldProxy
    address ypProxy = Upgrades.deployUUPSProxy(
      "YieldProxy.sol",
      abi.encodeCall(
        YieldProxy.initialize,
        (admin, manager, pauser, bot, address(token), address(asBnb), address(listaStakeManager), admin)
      )
    );
    yieldProxy = YieldProxy(payable(ypProxy));

    // deploy minter
    address minterProxy = Upgrades.deployUUPSProxy(
      "AsBnbMinter.sol",
      abi.encodeCall(AsBnbMinter.initialize, (admin, manager, pauser, bot, address(token), address(asBnb), ypProxy))
    );
    minter = AsBnbMinter(minterProxy);

    // deploy AsBNB OFT Adapter ------------
    // deploy impl.
    AsBnbOFTAdapter asBnbOFTAdapterImpl = new AsBnbOFTAdapter(address(asBnb), LZ_Endpoint);
    // Encode initialization call
    bytes memory asBnbOFTAdapterInitData = abi.encodeWithSignature(
      "initialize(address,address,address,address)",
      admin,
      manager,
      pauser,
      admin
    );
    // deploy proxy
    ERC1967Proxy asBnbOFTAdapterProxy = new ERC1967Proxy(address(asBnbOFTAdapterImpl), asBnbOFTAdapterInitData);
    asBnbOFTAdapter = AsBnbOFTAdapter(address(asBnbOFTAdapterProxy));

    // set roles
    vm.startPrank(admin);
    asBnb.setMinter(address(minter));
    vm.stopPrank();

    vm.startPrank(manager);
    yieldProxy.setMinter(address(minter));
    yieldProxy.setSlisBNBProvider(address(slisBNBProvider));
    yieldProxy.setMPCWallet(MPCWallet);
    yieldProxy.setRewardsSender(rewardSender);
    minter.setMinMintAmount(minMintAmount);
    minter.setAsBnbOFTAdapter(SEI_EID, address(asBnbOFTAdapter));
    vm.stopPrank();

    // set peer and transfer limit
    vm.prank(admin);
    asBnbOFTAdapter.setPeer(SEI_EID, bytes32(uint256(uint160(makeAddr("OFT_AT_SEI")))));

    TransferLimiter.TransferLimit[] memory tlb = new TransferLimiter.TransferLimit[](1);
    tlb[0] = TransferLimiter.TransferLimit(SEI_EID, 100000 ether, 10000 ether, 0.01 ether, 20000 ether, 100);
    vm.prank(manager);
    asBnbOFTAdapter.setTransferLimitConfigs(tlb);

    // give all roles some BNB
    deal(admin, 100000 ether);
    deal(manager, 100000 ether);
    deal(pauser, 100000 ether);
    deal(bot, 100000 ether);
    deal(user, 100000 ether);
    deal(rewardSender, 100000 ether);
  }

  /**
   * @dev User convert their BNB to slisBNB
   *      then deposit their slisBNB to the Minter to mint AsBNB
   *      meanwhile, slisBNB transferred to YieldProxy and converted to clisBNB
   *      and delegated to the specific address(We set yieldProxy at this case)
   */
  function test_mint_asBnb() public {
    vm.startPrank(user);

    // user convert 100 BNB and get less then 100 slisBNB
    listaStakeManager.deposit{ value: 100 ether }();
    uint256 userTokenBalance = token.balanceOf(user);
    assertLe(userTokenBalance, 100 ether);
    console.log("user slisBNB balance: %s", userTokenBalance);

    // try to mint less then minMintAmount
    token.safeIncreaseAllowance(address(minter), minMintAmount - 1);
    vm.expectRevert("amount is less than minMintAmount");
    minter.mintAsBnb(minMintAmount - 1);
    vm.stopPrank();

    // disable deposit
    vm.prank(manager);
    minter.toggleCanDeposit();
    assertEq(minter.canDeposit(), false);
    token.safeIncreaseAllowance(address(minter), userTokenBalance);
    vm.prank(user);
    vm.expectRevert("Deposit is disabled");
    minter.mintAsBnb(userTokenBalance);

    // resume deposit
    vm.prank(manager);
    minter.toggleCanDeposit();

    vm.startPrank(user);
    // user mint asBnb
    token.safeIncreaseAllowance(address(minter), userTokenBalance);
    minter.mintAsBnb(userTokenBalance);

    // verify asBnb balance
    uint256 convertRate = minter.convertToAsBnb(userTokenBalance);
    assertLe(asBnb.balanceOf(user), userTokenBalance * convertRate);
    assertLe(minter.totalTokens(), userTokenBalance);
    console.log("user AsBNB balance: %s", asBnb.balanceOf(user));

    // user out of slisBNB now
    token.safeIncreaseAllowance(address(minter), userTokenBalance);
    vm.expectRevert();
    minter.mintAsBnb(userTokenBalance);

    vm.stopPrank();
  }

  /**
   * @dev similar with the previous scenario
   *      instead of depositing slisBNB,
   *      user directly mint asBnb from their native token
   */
  function test_mint_asBnb_from_native_token() public {
    vm.startPrank(user);

    // try to mint less then minMintAmount
    vm.expectRevert("amount is less than minMintAmount");
    minter.mintAsBnb{ value: minMintAmount - 1 }();
    vm.stopPrank();

    // disable deposit
    vm.prank(manager);
    minter.toggleCanDeposit();
    assertEq(minter.canDeposit(), false);
    vm.prank(user);
    vm.expectRevert("Deposit is disabled");
    minter.mintAsBnb{ value: 1 ether }();

    // resume deposit
    vm.prank(manager);
    minter.toggleCanDeposit();

    vm.startPrank(user);
    // user mint asBnb
    minter.mintAsBnb{ value: 1 ether }();

    // verify asBnb balance
    uint256 conversionRate1 = IStakeManagerAlt(address(listaStakeManager)).convertBnbToSnBnb(1 ether);
    uint256 conversionRate2 = minter.convertToAsBnb(1 ether);
    assertLe(asBnb.balanceOf(user), 1 ether * conversionRate1 * conversionRate2);
    console.log("user AsBNB balance: %s", asBnb.balanceOf(user));

    vm.stopPrank();
  }

  /**
   * @dev User convert their BNB to slisBNB, and mint asBNB to SEI chain
   */
  function test_mint_asBnb_to_sei() public {
    deal(address(token), user, 1 ether);

    // get est. amount to cross-chain
    uint256 crossChainAmt = minter.convertToAsBnb(1 ether);

    // disable deposit
    vm.prank(manager);
    minter.toggleCanDeposit();
    assertEq(minter.canDeposit(), false);
    token.safeIncreaseAllowance(address(minter), crossChainAmt);

    uint256 _rate = asBnbOFTAdapter.decimalConversionRate();
    crossChainAmt = (crossChainAmt / _rate) * _rate;

    // quote fee
    bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
    SendParam memory sendParam = SendParam(
      SEI_EID,
      addressToBytes32(user),
      crossChainAmt,
      crossChainAmt,
      options,
      "",
      ""
    );
    MessagingFee memory fee = asBnbOFTAdapter.quoteSend(sendParam, false);
    // mint asBnb and send to SEI chain
    vm.prank(user);
    vm.expectRevert("Deposit is disabled");
    minter.mintAsBnbToChain{ value: fee.nativeFee }(crossChainAmt, sendParam);

    // resume deposit
    vm.prank(manager);
    minter.toggleCanDeposit();

    vm.startPrank(user);
    // user mint asBnb
    token.safeIncreaseAllowance(address(minter), crossChainAmt);
    minter.mintAsBnbToChain{ value: fee.nativeFee }(crossChainAmt, sendParam);

    // verify asBnb balance
    uint256 convertRate = minter.convertToAsBnb(crossChainAmt);
    assertLe(asBnb.balanceOf(user), crossChainAmt * convertRate);
    assertLe(minter.totalTokens(), crossChainAmt);
    console.log("user AsBNB balance: %s", asBnb.balanceOf(user));

    vm.stopPrank();
  }

  /**
   * @dev similar with the previous scenario, mint asBNB to SEI with native BNB
   */
  function test_mint_asBnb_to_sei_from_native_token() public {
    // get est. mint token
    uint256 tokenGet = IStakeManagerAlt(address(listaStakeManager)).convertBnbToSnBnb(1 ether);
    uint256 asTokenToMintEst = minter.convertToAsBnb(tokenGet);

    // quote fee
    bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
    // remove dust
    uint256 _rate = asBnbOFTAdapter.decimalConversionRate();
    asTokenToMintEst = (asTokenToMintEst / _rate) * _rate;

    SendParam memory sendParam = SendParam(
      SEI_EID,
      addressToBytes32(user),
      asTokenToMintEst,
      asTokenToMintEst,
      options,
      "",
      ""
    );
    MessagingFee memory fee = asBnbOFTAdapter.quoteSend(sendParam, false);

    console.log("asTokenToMintEst: %s", asTokenToMintEst);
    console.log("OFT Adapter address: %s", address(asBnbOFTAdapter));
    console.log("Minter address: %s", address(minter));

    // disable deposit
    vm.prank(manager);
    minter.toggleCanDeposit();
    assertEq(minter.canDeposit(), false);
    vm.prank(user);
    vm.expectRevert("Deposit is disabled");
    minter.mintAsBnbToChain{ value: 1 ether + fee.nativeFee }(sendParam);

    // resume deposit
    vm.prank(manager);
    minter.toggleCanDeposit();

    vm.prank(user);
    // user mint asBnb
    minter.mintAsBnbToChain{ value: 1 ether + fee.nativeFee }(sendParam);
  }

  /**
   * @dev user requests 10 times to mint asBnb
   *      requests are queued as a activity is on-going
   */
  function test_mint_queue() public {
    // add an activity
    vm.prank(manager);
    yieldProxy.addActivity(block.timestamp + 1000, block.timestamp + 2000, "TestToken");

    // start launchpool
    skip(1001);

    // launchpool on-going
    assertEq(yieldProxy.activitiesOnGoing(), true);

    vm.startPrank(user);
    // user convert 100 BNB and get less then 100 slisBNB
    listaStakeManager.deposit{ value: 100 ether }();
    uint256 userTokenBalance = token.balanceOf(user);
    assertLe(userTokenBalance, 100 ether);

    // mint 10 times
    token.safeIncreaseAllowance(address(minter), userTokenBalance);
    for (uint256 i = 0; i < 10; i++) {
      minter.mintAsBnb(userTokenBalance / 10);
    }
    // user should not have any asBnb
    assertEq(asBnb.balanceOf(user), 0);
    // all requests should be queued
    assertEq(minter.queueRear(), 10);
    // request are not being processed
    assertEq(minter.queueFront(), 0);
    vm.stopPrank();
  }

  /**
   * @dev bot process mint request
   */
  function test_bot_process_mint_request() public {
    // still have on-going activity
    this.test_mint_queue();
    assertEq(yieldProxy.activitiesOnGoing(), true);

    // should not be able to process mint request
    vm.prank(bot);
    vm.expectRevert("Activity is on going");
    minter.processMintQueue(11);

    // end activity
    vm.prank(manager);
    yieldProxy.endActivity(5);
    // all launchpools are done
    assertEq(yieldProxy.activitiesOnGoing(), false);

    // process 0 request
    vm.prank(bot);
    vm.expectRevert("Invalid batch size");
    minter.processMintQueue(0);

    // process mint request
    vm.prank(bot);
    minter.processMintQueue(20);
    assertApproxEqAbs(asBnb.balanceOf(user), 100 ether, 1 ether);

    // all request should be processed
    vm.prank(bot);
    vm.expectRevert("No pending mint request");
    minter.processMintQueue(20);
  }

  /**
   * @dev User burn asBnb
   */
  function test_burn_ass_token() public {
    // mint asBnb
    this.test_mint_asBnb();

    uint256 amountToBurn = 50 ether;
    uint256 amountToRelease = minter.convertToTokens(amountToBurn);
    uint256 preBalance = token.balanceOf(user);

    // disable withdrawal
    vm.prank(manager);
    minter.toggleCanWithdraw();
    assertEq(minter.canWithdraw(), false);

    // can't withdraw
    vm.startPrank(user);
    vm.expectRevert("Withdrawal is disabled");
    minter.burnAsBnb(amountToBurn);
    vm.stopPrank();

    // resume withdrawal
    vm.prank(manager);
    minter.toggleCanWithdraw();
    assertEq(minter.canWithdraw(), true);

    // burn asBnb
    vm.startPrank(user);
    asBnb.safeIncreaseAllowance(address(minter), amountToBurn);
    minter.burnAsBnb(amountToBurn);
    vm.stopPrank();

    uint256 postBalance = token.balanceOf(user);
    uint256 net = postBalance - preBalance;
    assertEq(net, amountToRelease);
  }

  // @dev for this.test_compound_rewards();
  // please refer to YieldProxy.t.sol
  function test_compound_rewards() public {
    // set a 10% fee rate
    vm.prank(manager);
    minter.setFeeRate(1000); // 1000/10000

    // add 2 activities
    vm.startPrank(manager);
    yieldProxy.addActivity(block.timestamp + 1000, block.timestamp + 2000, "TestToken1");
    yieldProxy.addActivity(block.timestamp + 1000, block.timestamp + 3000, "TestToken2");
    yieldProxy.addActivity(block.timestamp + 1000, block.timestamp + 4000, "TestToken3");
    vm.stopPrank();

    // activity started
    skip(1001);

    // launchpool rewards 5000 BNB
    vm.prank(rewardSender);
    (bool success, ) = address(yieldProxy).call{ value: 5000 ether }("");
    assertEq(success, true);

    uint256 totalTokens_1 = minter.totalTokens();
    uint256 netFee_1 = minter.feeAvailable();
    console.log("totalTokens_1: %s", totalTokens_1);
    console.log("netFee_1: %s", netFee_1);

    // compoundRewards
    vm.prank(bot);
    yieldProxy.settleActivity();

    uint256 totalTokens_2 = minter.totalTokens();
    uint256 netFee_2 = minter.feeAvailable();
    assertGt(totalTokens_2, totalTokens_1);
    assertGt(netFee_2, netFee_1);
    console.log("totalTokens_2: %s", totalTokens_2);
    console.log("netFee_2: %s", netFee_2);

    // at this point all rewards has been converted to slisBNB and compounded
    vm.prank(bot);
    vm.expectRevert("No rewards to compound");
    yieldProxy.settleActivity();

    // another rewards for activity 2 comes in
    vm.prank(rewardSender);
    (success, ) = address(yieldProxy).call{ value: 5000 ether }("");
    assertEq(success, true);

    // compoundRewards
    vm.prank(bot);
    yieldProxy.settleActivity();

    uint256 totalTokens_3 = minter.totalTokens();
    uint256 netFee_3 = minter.feeAvailable();
    assertGt(totalTokens_3, totalTokens_2);
    assertGt(netFee_3, netFee_2);
    console.log("totalTokens_3: %s", totalTokens_3);
    console.log("netFee_3: %s", netFee_3);

    // at this point, there are only 1 active activity
    // but try to end 5 more and endActivity() shall able to handle it
    vm.prank(manager);
    yieldProxy.endActivity(5);

    // no more activities to settle
    vm.prank(bot);
    vm.expectRevert("No active activity");
    yieldProxy.settleActivity();

    // add one more activity
    vm.prank(manager);
    yieldProxy.addActivity(block.timestamp + 1000, block.timestamp + 5000, "TestToken4");

    skip(1001);

    // should trigger to the first assert
    vm.prank(bot);
    vm.expectRevert("No rewards to compound");
    yieldProxy.settleActivity();

    // end the last activity
    vm.prank(manager);
    yieldProxy.endActivity(1);
  }

  /**
   * @dev test withdraw fee from rewards commission
   */
  function test_withdraw_fee() public {
    this.test_compound_rewards();

    uint256 totalFee = minter.feeAvailable();

    uint256 preBalance = token.balanceOf(feeReceiver);
    // withdraw fee to feeReceiver
    vm.prank(manager);
    minter.withdrawFee(feeReceiver, totalFee);
    uint256 postBalance = token.balanceOf(feeReceiver);
    assertEq(postBalance - preBalance, totalFee);
  }

  /**
   * @dev test pause and unpause function
   */
  function test_pause_and_unpause() public {
    // pause and unpause with no access
    vm.expectRevert();
    minter.unpause();

    vm.expectRevert();
    minter.pause();

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
   * @dev test upgrade
   */
  function test_upgrade() public {
    address proxyAddress = address(minter);
    address implAddressV1 = Upgrades.getImplementationAddress(proxyAddress);

    vm.expectRevert();
    Upgrades.upgradeProxy(proxyAddress, "AsBnbMinter.sol", "", msg.sender);

    vm.startPrank(admin);
    Upgrades.upgradeProxy(proxyAddress, "AsBnbMinter.sol", "", msg.sender);
    address implAddressV2 = Upgrades.getImplementationAddress(proxyAddress);
    assertFalse(implAddressV2 == implAddressV1);
    vm.stopPrank();
    console.log("implAddressV1: %s", implAddressV1);
    console.log("implAddressV2: %s", implAddressV2);
  }

  function addressToBytes32(address _addr) internal pure returns (bytes32) {
    return bytes32(uint256(uint160(_addr)));
  }
}
