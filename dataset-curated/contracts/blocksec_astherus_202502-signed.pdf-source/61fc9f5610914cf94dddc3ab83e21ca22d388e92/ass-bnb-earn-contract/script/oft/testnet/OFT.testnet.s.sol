// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

// Forge imports
import "forge-std/console.sol";
import "forge-std/Script.sol";

import { AsBNB } from "../../../src/AsBNB.sol";
import { AsBnbOFT } from "../../../src/oft/AsBnbOFT.sol";
import { AsBnbOFTAdapter } from "../../../src/oft/AsBnbOFTAdapter.sol";
import { TransferLimiter } from "../../../src/oft/TransferLimiter.sol";

import { OptionsBuilder } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import { IOFT, SendParam, OFTReceipt } from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import { MessagingFee, MessagingReceipt } from "@layerzerolabs/oft-evm/contracts/OFTCore.sol";

contract asBnbOftTestnetScript is Script {
  using OptionsBuilder for bytes;

  uint256 public userPK;
  address public user;
  address public receiver;

  AsBNB public asBnb;
  AsBnbOFT public asBnbOFT;
  AsBnbOFTAdapter public asBnbOFTAdapter;

  uint32 public toChainEid;

  // Change this for sending from target chain to src chain
  bool public sendFromSourceChain = true;

  function setUp() public {
    address _asBnb = vm.envAddress("ASBNB");
    address _asBnbOFTAdapter = vm.envAddress("OFT_ADAPTER");
    address _asBnbOFT = vm.envAddress("OFT");

    asBnb = AsBNB(_asBnb);
    asBnbOFTAdapter = AsBnbOFTAdapter(_asBnbOFTAdapter);
    asBnbOFT = AsBnbOFT(_asBnbOFT);

    userPK = vm.envUint("PRIVATE_KEY");
    user = vm.addr(userPK);
    receiver = user; // or change to any address u want
    console.log("User: %s", user);
    console.log("Receiver: %s", receiver);

    toChainEid = uint32(vm.envUint(
      sendFromSourceChain ? "TARGET_CHAIN_EID" : "SOURCE_CHAIN_EID"
    ));
  }

  function run() public {
    // amount of token to send
    uint256 tokensToSend = 0.001 ether;
    // build cross chain option
    bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
    SendParam memory sendParam = SendParam(toChainEid, bytes32(uint256(uint160(receiver))), tokensToSend, tokensToSend, options, "", "");
    MessagingFee memory fee;
    // start to broadcast tx
    vm.startBroadcast(userPK);
    // send from BSC
    if (sendFromSourceChain) {
      asBnb.approve(address(asBnbOFTAdapter), tokensToSend);
      fee = asBnbOFTAdapter.quoteSend(sendParam, false);
      asBnbOFTAdapter.send{ value: fee.nativeFee }(sendParam, fee, payable(address(this)));
    } else {
      fee = asBnbOFT.quoteSend(sendParam, false);
      asBnbOFT.send{ value: fee.nativeFee }(sendParam, fee, payable(address(this)));
    }
    vm.stopBroadcast();
  }
}
