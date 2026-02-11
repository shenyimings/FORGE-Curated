// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

// Forge imports
import "forge-std/console.sol";
import "forge-std/Script.sol";

import { AsBNB } from "../../../src/AsBNB.sol";
import { AsBnbOFT } from "../../../src/oft/AsBnbOFT.sol";
import { AsBnbOFTAdapter } from "../../../src/oft/AsBnbOFTAdapter.sol";
import { TransferLimiter } from "../../../src/oft/TransferLimiter.sol";
import { AsBnbMinter } from "../../../src/AsBnbMinter.sol";

import { OptionsBuilder } from "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";
import { IOFT, SendParam, OFTReceipt } from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";
import { MessagingFee, MessagingReceipt } from "@layerzerolabs/oft-evm/contracts/OFTCore.sol";

contract asBnbOftTestnet2Script is Script {
  using OptionsBuilder for bytes;

  uint256 public userPK;
  address public user;
  address public receiver;

  AsBNB public asBnb;
  AsBnbOFTAdapter public asBnbOFTAdapter;
  AsBnbMinter public asBnbMinter;

  uint32 public toChainEid;


  function setUp() public {
    address _asBnb = vm.envAddress("ASBNB");
    address _asBnbMinter = vm.envAddress("MINTER");
    address _asBnbOFTAdapter = vm.envAddress("OFT_ADAPTER");

    asBnb = AsBNB(_asBnb);
    asBnbOFTAdapter = AsBnbOFTAdapter(_asBnbOFTAdapter);
    asBnbMinter = AsBnbMinter(_asBnbMinter);

    userPK = vm.envUint("PRIVATE_KEY");
    user = vm.addr(userPK);
    receiver = user; // or change to any address u want
    console.log("User: %s", user);
    console.log("Receiver: %s", receiver);

    toChainEid = uint32(vm.envUint("TARGET_CHAIN_EID"));
  }

  /**
   * @dev mint asBNB with !!--- slisBNB ---!!
   *      then send it from BSC to target chain
   * @notice the whole process is done in one tx within AsBnbMinter
   */
  function run() public {
    // amount of token to send
    uint256 tokensToSend = 0.01 ether;
    // calculate how much asBNB can be mint
    uint256 crossChainAmount = asBnbMinter.convertToAsBnb(tokensToSend);
    // remove dust as Cross-chain decimal conversion rate is 6 digits
    uint256 decimalConversionRate = asBnbOFTAdapter.decimalConversionRate();
    crossChainAmount = (crossChainAmount/decimalConversionRate) * decimalConversionRate;
    // build cross chain option
    bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
    // build cross chain params
    SendParam memory sendParam = SendParam(toChainEid, bytes32(uint256(uint160(receiver))), crossChainAmount, crossChainAmount, options, "", "");
    // get fee
    MessagingFee memory fee = asBnbOFTAdapter.quoteSend(sendParam, false);
    // start to broadcast tx
    vm.startBroadcast(userPK);
    // send from BSC
    asBnb.approve(address(asBnbOFTAdapter), tokensToSend);
    asBnbMinter.mintAsBnbToChain{ value: fee.nativeFee }(tokensToSend, sendParam);

    vm.stopBroadcast();
  }
}
