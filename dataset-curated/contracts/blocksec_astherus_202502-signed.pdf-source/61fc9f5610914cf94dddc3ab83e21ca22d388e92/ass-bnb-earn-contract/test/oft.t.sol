// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import { AsBNB } from "../src/AsBNB.sol";
import { AsBnbOFT } from "../src/oft/AsBnbOFT.sol";
import { AsBnbOFTAdapter } from "../src/oft/AsBnbOFTAdapter.sol";
import { TransferLimiter } from "../src/oft/TransferLimiter.sol";
import { OFTComposerMock } from "./mocks/OFTComposerMock.sol";
// OApp imports
import { IOAppOptionsType3, EnforcedOptionParam } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OAppOptionsType3.sol";
import { OptionsBuilder } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
// OFT imports
import { IOFT, SendParam, OFTReceipt } from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import { MessagingFee, MessagingReceipt } from "@layerzerolabs/oft-evm/contracts/OFTCore.sol";
import { OFTMsgCodec } from "@layerzerolabs/oft-evm/contracts/libs/OFTMsgCodec.sol";
import { OFTComposeMsgCodec } from "@layerzerolabs/oft-evm/contracts/libs/OFTComposeMsgCodec.sol";
// OZ imports
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
// Forge imports
import "forge-std/console.sol";
import { Upgrades } from "openzeppelin-foundry-upgrades/Upgrades.sol";
import { Options } from "openzeppelin-foundry-upgrades/Options.sol";
// DevTools imports
import { TestHelperOz5 } from "@layerzerolabs/test-devtools-evm-foundry/contracts/TestHelperOz5.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// Run this command to test
// forge clean && forge build && forge test -vvv --match-contract asBnbOFTTest

contract asBnbOFTTest is TestHelperOz5 {
  using OptionsBuilder for bytes;

  uint32 aEid = 1;
  uint32 bEid = 2;

  AsBNB asBnb;
  AsBnbOFTAdapter asBnbOFTAdapter;
  AsBnbOFT asBnbOFT;

  address public userA = address(0x1);
  address public userB = address(0x2);

  // for the convience of testing, using admin as admin, owner and manager
  address public admin = address(this);
  address public pauser = makeAddr("pauser");

  uint256 public initialBalance = 100 ether;

  address public proxyAdmin = makeAddr("proxyAdmin");

  function setUp() public virtual override {
    vm.deal(userA, 1000 ether);
    vm.deal(userB, 1000 ether);

    super.setUp();
    setUpEndpoints(2, LibraryType.UltraLightNode);

    // ----------- deploy asBNB ------------
    asBnb = new AsBNB("Astherus BNB", "asBNB", admin, admin);

    // ----------- deploy AsBNB OFT Adapter ------------
    // deploy impl.
    AsBnbOFTAdapter asBnbOFTAdapterImpl = new AsBnbOFTAdapter(address(asBnb), address(endpoints[aEid]));
    // Encode initialization call
    bytes memory asBnbOFTAdapterInitData = abi.encodeWithSignature(
      "initialize(address,address,address,address)",
      admin,
      admin,
      pauser,
      admin
    );
    // deploy proxy
    ERC1967Proxy asBnbOFTAdapterProxy = new ERC1967Proxy(address(asBnbOFTAdapterImpl), asBnbOFTAdapterInitData);
    asBnbOFTAdapter = AsBnbOFTAdapter(address(asBnbOFTAdapterProxy));

    // ----------- deploy AsBNBOFT ------------
    // deploy impl.
    AsBnbOFT asBnbOFTImpl = new AsBnbOFT(address(endpoints[bEid]));
    // Encode initialization call
    bytes memory asBnbOFTInitData = abi.encodeWithSignature(
      "initialize(address,address,address,string,string,address)",
      admin,
      admin,
      pauser,
      "Astherus BNB",
      "asBNB",
      admin
    );
    // deploy proxy
    ERC1967Proxy asBnbOFTProxy = new ERC1967Proxy(address(asBnbOFTImpl), asBnbOFTInitData);
    asBnbOFT = AsBnbOFT(address(asBnbOFTProxy));

    // setup transfer Limit Configs
    setupLimits();

    // config and wire the ofts
    address[] memory ofts = new address[](2);
    ofts[0] = address(asBnbOFTAdapter);
    ofts[1] = address(asBnbOFT);
    this.wireOApps(ofts);

    // give user tokens
    deal(address(asBnb), userA, initialBalance);
  }

  function setupLimits() public {
    TransferLimiter.TransferLimit[] memory tla = new TransferLimiter.TransferLimit[](1);
    tla[0] = TransferLimiter.TransferLimit(
      bEid,
      100000000000000000000000,
      10000000000000000000000,
      100000000000000000,
      20000000000000000000000,
      10
    );
    asBnbOFTAdapter.setTransferLimitConfigs(tla);

    TransferLimiter.TransferLimit[] memory tlb = new TransferLimiter.TransferLimit[](1);
    tlb[0] = TransferLimiter.TransferLimit(
      aEid,
      100000000000000000000000,
      10000000000000000000000,
      100000000000000000,
      20000000000000000000000,
      10
    );
    asBnbOFT.setTransferLimitConfigs(tlb);
  }

  // @notice the main flow of how to use OFT
  // @dev Lock asBnb at 1, mint asBnbOFT at 2
  function test_send_back_and_forth() public {
    uint256 tokensToSend = 0.1 ether;

    /** ---------------------------------
     ----- Send OFT from EID 1 to 2 -----
     ------------------------------------ */
    bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
    SendParam memory aSendParam = SendParam(bEid, addressToBytes32(userB), tokensToSend, tokensToSend, options, "", "");
    MessagingFee memory aFee = asBnbOFTAdapter.quoteSend(aSendParam, false);

    assertEq(asBnb.balanceOf(userA), initialBalance);
    assertEq(asBnbOFT.balanceOf(userB), 0);

    vm.startPrank(userA);
    asBnb.approve(address(asBnbOFTAdapter), tokensToSend);
    asBnbOFTAdapter.send{ value: aFee.nativeFee }(aSendParam, aFee, payable(address(this)));
    vm.stopPrank();
    verifyPackets(bEid, addressToBytes32(address(asBnbOFT)));

    assertEq(asBnb.balanceOf(userA), initialBalance - tokensToSend);
    assertEq(asBnbOFT.balanceOf(userB), tokensToSend);

    /** ---------------------------------
     ----- Send OFT from EID 2 to 1 -----
     ------------------------------------ */
    bytes memory bOptions = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
    SendParam memory bSendParam = SendParam(
      aEid,
      addressToBytes32(userA),
      tokensToSend,
      tokensToSend,
      bOptions,
      "",
      ""
    );
    MessagingFee memory bFee = asBnbOFT.quoteSend(bSendParam, false);

    vm.startPrank(userB);
    asBnbOFT.approve(address(asBnbOFT), tokensToSend);
    asBnbOFT.send{ value: bFee.nativeFee }(bSendParam, bFee, payable(address(this)));
    vm.stopPrank();
    verifyPackets(aEid, addressToBytes32(address(asBnbOFTAdapter)));

    assertEq(asBnb.balanceOf(userA), initialBalance);
    assertEq(asBnbOFT.balanceOf(userB), 0);
  }

  // @dev simulate we transfer more than 100,000 tokens per day
  function test_exceeded_daily_global_limit() public {
    uint256 tokensToSend = 10000 ether;
    address[11] memory users = [
      address(0x3),
      address(0x4),
      address(0x5),
      address(0x6),
      address(0x7),
      address(0x8),
      address(0x9),
      address(0x11),
      address(0x12),
      address(0x13),
      address(0x14)
    ];
    // transfer 10000 with 11 different user
    // 110,000 tokens will exceed the global transfer limit
    for (uint i = 0; i < users.length; ++i) {
      address user = users[i];
      vm.deal(user, 1000 ether);
      try this.send_from_a_to_b(user, user, tokensToSend) {} catch (bytes memory reason) {
        console.log("test_exceeded_daily_global_limit(): Error caught: TransferLimitExceeded()");
        bytes4 desiredSelector = bytes4(keccak256(bytes("TransferLimitExceeded()")));
        bytes4 receivedSelector = bytes4(reason);
        assertEq(desiredSelector, receivedSelector);
      }
    }
    // after 1 day, the global transfer limit will be reset
    vm.warp(vm.getBlockTimestamp() + 86401);
    vm.deal(address(0x1234), 1000 ether);
    send_from_a_to_b(address(0x1234), address(0x1234), 10000 ether);
    console.log("test_exceeded_daily_global_limit(): succeeded after 1 day");
  }

  // @dev simulate an user transfer more than 20,000 tokens per day
  function test_exceeded_daily_user_transfer_limit() public {
    for (uint i = 0; i < 2; ++i) {
      try this.send_from_a_to_b(userA, userA, 10000 ether) {} catch (bytes memory reason) {
        console.log("test_exceeded_daily_user_transfer_limit(): Error caught: TransferLimitExceeded()");
        bytes4 desiredSelector = bytes4(keccak256(bytes("TransferLimitExceeded()")));
        bytes4 receivedSelector = bytes4(reason);
        assertEq(desiredSelector, receivedSelector);
      }
    }
    // after 1 day, the user transfer limit will be reset
    vm.warp(vm.getBlockTimestamp() + 86401);
    send_from_a_to_b(userA, userA, 10 ether);
    console.log("test_exceeded_daily_user_transfer_limit(): succeeded after 1 day");
  }

  // @dev simulate an user transfer more than 10 times per day
  function test_exceeded_daily_user_transfer_attempts() public {
    for (uint i = 0; i < 11; ++i) {
      try this.send_from_a_to_b(userA, userA, 1 ether) {} catch (bytes memory reason) {
        console.log("test_exceeded_daily_user_transfer_attempts(): Error caught: TransferLimitExceeded()");
        bytes4 desiredSelector = bytes4(keccak256(bytes("TransferLimitExceeded()")));
        bytes4 receivedSelector = bytes4(reason);
        assertEq(desiredSelector, receivedSelector);
      }
    }
    // after 1 day, the user transfer attempt will be reset
    vm.warp(vm.getBlockTimestamp() + 86401);
    send_from_a_to_b(userA, userA, 10 ether);
    console.log("test_exceeded_daily_user_transfer_attempts(): succeeded after 1 day");
  }

  // @dev simulate an user transfer token with an outbound amount that is too small or too large
  function test_outbound_upper_and_lower_limit() public {
    // amount too small
    try this.send_from_a_to_b(userA, userA, 0.001 ether) {} catch (bytes memory reason) {
      console.log("test_outbound_upper_and_lower_limit(): Error caught: TransferLimitExceeded(): Amount too small");
      bytes4 desiredSelector = bytes4(keccak256(bytes("TransferLimitExceeded()")));
      bytes4 receivedSelector = bytes4(reason);
      assertEq(desiredSelector, receivedSelector);
    }
    // amount too large
    try this.send_from_a_to_b(userA, userA, 10001 ether) {} catch (bytes memory reason) {
      console.log("test_outbound_upper_and_lower_limit(): Error caught: TransferLimitExceeded(): amount too large");
      bytes4 desiredSelector = bytes4(keccak256(bytes("TransferLimitExceeded()")));
      bytes4 receivedSelector = bytes4(reason);
      assertEq(desiredSelector, receivedSelector);
    }
  }

  // @dev simulate an user couldn't transfer if the OFT is paused
  function test_pausable() public {
    // ----- asBnbOFTAdapter
    // 1. not paused initially
    assertEq(asBnbOFTAdapter.paused(), false);
    // 2. pause it without a multiSig address
    vm.expectRevert();
    asBnbOFTAdapter.pause();
    // 3. pauser can pause
    vm.prank(pauser);
    asBnbOFTAdapter.pause();
    assertEq(asBnbOFTAdapter.paused(), true);
    // 4. pauser can't unpause
    vm.prank(pauser);
    vm.expectRevert();
    asBnbOFTAdapter.unpause();
    assertEq(asBnbOFTAdapter.paused(), true);
    // 4. only manager can unpause (in this case is address(this))
    asBnbOFTAdapter.unpause();
    assertEq(asBnbOFTAdapter.paused(), false);

    // ----- asBnbOFT
    // 1. not paused initially
    assertEq(asBnbOFT.paused(), false);
    // 2. pause it without a multiSig address
    vm.expectRevert();
    asBnbOFT.pause();
    // 3. pauser can pause
    vm.prank(pauser);
    asBnbOFT.pause();
    assertEq(asBnbOFT.paused(), true);
    // 4. pauser can't unpause
    vm.prank(pauser);
    vm.expectRevert();
    asBnbOFT.unpause();
    assertEq(asBnbOFT.paused(), true);
    // 4. only manager can unpause (in this case is address(this))
    asBnbOFT.unpause();
    assertEq(asBnbOFT.paused(), false);

    // can't transfer during pause
    vm.startPrank(pauser);
    asBnbOFT.pause();
    asBnbOFTAdapter.pause();
    vm.stopPrank();
    // should fail if paused
    vm.expectRevert();
    this.send_from_a_to_b(userA, userA, 1 ether);
  }

  // Verify msg integrity
  function test_send_oft_compose_msg() public {
    uint256 tokensToSend = 1 ether;

    OFTComposerMock composer = new OFTComposerMock();

    bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0).addExecutorLzComposeOption(
      0,
      500000,
      0
    );
    bytes memory composeMsg = hex"1234";
    SendParam memory sendParam = SendParam(
      bEid,
      addressToBytes32(address(composer)),
      tokensToSend,
      tokensToSend,
      options,
      composeMsg,
      ""
    );
    MessagingFee memory fee = asBnbOFTAdapter.quoteSend(sendParam, false);

    assertEq(asBnb.balanceOf(userA), initialBalance);
    assertEq(asBnbOFT.balanceOf(address(composer)), 0);

    vm.startPrank(userA);
    asBnb.approve(address(asBnbOFTAdapter), tokensToSend);
    (MessagingReceipt memory msgReceipt, OFTReceipt memory oftReceipt) = asBnbOFTAdapter.send{ value: fee.nativeFee }(
      sendParam,
      fee,
      payable(address(this))
    );
    vm.stopPrank();
    verifyPackets(bEid, addressToBytes32(address(asBnbOFT)));

    // lzCompose params
    uint32 dstEid_ = bEid;
    address from_ = address(asBnbOFT);
    bytes memory options_ = options;
    bytes32 guid_ = msgReceipt.guid;
    address to_ = address(composer);
    bytes memory composerMsg_ = OFTComposeMsgCodec.encode(
      msgReceipt.nonce,
      aEid,
      oftReceipt.amountReceivedLD,
      abi.encodePacked(addressToBytes32(userA), composeMsg)
    );
    this.lzCompose(dstEid_, from_, options_, guid_, to_, composerMsg_);

    assertEq(asBnb.balanceOf(userA), initialBalance - tokensToSend);
    assertEq(asBnbOFT.balanceOf(address(composer)), tokensToSend);

    assertEq(composer.from(), from_);
    assertEq(composer.guid(), guid_);
    assertEq(composer.message(), composerMsg_);
    assertEq(composer.executor(), address(this));
    assertEq(composer.extraData(), composerMsg_); // default to setting the extraData to the message as well to test
  }

  function test_upgrade_oftadapter() public {
    address proxyAddress = address(asBnbOFTAdapter);
    address oldImpl = Upgrades.getImplementationAddress(proxyAddress);

    vm.prank(address(0x12345));
    vm.expectRevert();
    asBnbOFTAdapter.upgradeToAndCall(address(0x12345), "");

    // deploy new AsBnbOFTAdapter impl
    address newImpl = address(new AsBnbOFTAdapter(address(asBnb), address(endpoints[aEid])));
    asBnbOFTAdapter.upgradeToAndCall(newImpl, "");

    // do upgrade
    asBnbOFTAdapter.upgradeToAndCall(newImpl, "");
    address _newImpl = Upgrades.getImplementationAddress(proxyAddress);
    assertFalse(_newImpl == oldImpl);

    console.log("old impl: %s", oldImpl);
    console.log("new impl: %s", _newImpl);
  }

  function test_upgrade_oft() public {
    address proxyAddress = address(asBnbOFT);
    address oldImpl = Upgrades.getImplementationAddress(proxyAddress);

    vm.prank(address(0x12345));
    vm.expectRevert();
    asBnbOFT.upgradeToAndCall(address(0x12345), "");

    // deploy new AsBnbOFTAdapter impl
    address newImpl = address(new AsBnbOFT(address(endpoints[bEid])));
    asBnbOFT.upgradeToAndCall(newImpl, "");

    // do upgrade
    asBnbOFT.upgradeToAndCall(newImpl, "");
    address _newImpl = Upgrades.getImplementationAddress(proxyAddress);
    assertFalse(_newImpl == oldImpl);

    console.log("old impl: %s", oldImpl);
    console.log("new impl: %s", _newImpl);
  }

  // ---- helper functions ----
  function send_from_a_to_b(address from, address to, uint256 amt) public {
    deal(address(asBnb), from, amt);
    vm.startPrank(from);
    bytes memory opts = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
    SendParam memory sendParam = SendParam(bEid, addressToBytes32(to), amt, amt, opts, "", "");
    MessagingFee memory fee = asBnbOFTAdapter.quoteSend(sendParam, false);
    asBnb.approve(address(asBnbOFTAdapter), amt);
    asBnbOFTAdapter.send{ value: fee.nativeFee }(sendParam, fee, payable(address(this)));
    verifyPackets(bEid, addressToBytes32(address(asBnbOFTAdapter)));
    vm.stopPrank();
  }
}
