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

interface IListaStakeManager {
  function convertBnbToSnBnb(uint256 amt) external returns (uint256);
}

contract asBnbOftTestnet2Script is Script {
  using OptionsBuilder for bytes;

  uint256 public userPK;
  address public user;
  address public receiver;

  AsBNB public asBnb;
  AsBnbOFTAdapter public asBnbOFTAdapter;
  AsBnbMinter public asBnbMinter;
  IListaStakeManager public listaStakeManager;

  uint32 public toChainEid;


  function setUp() public {
    address _asBnb = vm.envAddress("ASBNB");
    address _asBnbMinter = vm.envAddress("MINTER");
    address _asBnbOFTAdapter = vm.envAddress("OFT_ADAPTER");
    address _listaStakeManager = vm.envAddress("STAKE_MANAGER");

    asBnb = AsBNB(_asBnb);
    asBnbOFTAdapter = AsBnbOFTAdapter(_asBnbOFTAdapter);
    asBnbMinter = AsBnbMinter(_asBnbMinter);
    listaStakeManager = IListaStakeManager(_listaStakeManager);

    userPK = vm.envUint("PRIVATE_KEY");
    user = vm.addr(userPK);
    receiver = user; // or change to any address u want
    console.log("User: %s", user);
    console.log("Receiver: %s", receiver);

    toChainEid = uint32(vm.envUint("TARGET_CHAIN_EID"));
  }

  /**
   * @dev mint asBNB with !!--- BNB ---!!
   *      then send it from BSC to target chain
   * @notice the whole process is done in one tx within AsBnbMinter
   */
  function run() public {
    // amount of BNB to send
    uint256 amountOfBNB = 0.1 ether;
    // calculate how much slisBNB can be mint
    uint256 slisBNBAmount = listaStakeManager.convertBnbToSnBnb(amountOfBNB);
    // calculate how much asBNB can be mint
    uint256 crossChainAmount = asBnbMinter.convertToAsBnb(slisBNBAmount);
    // remove dust as Cross-chain decimal conversion rate is 6 digits
    uint256 decimalConversionRate = asBnbOFTAdapter.decimalConversionRate();
    crossChainAmount = (crossChainAmount/decimalConversionRate)*decimalConversionRate;
    // build cross chain option
    bytes memory options = OptionsBuilder.newOptions().addExecutorLzReceiveOption(200000, 0);
    // build cross chain params
    SendParam memory sendParam = SendParam(toChainEid, bytes32(uint256(uint160(receiver))), crossChainAmount, crossChainAmount, options, "", "");
    // get fee
    MessagingFee memory fee = asBnbOFTAdapter.quoteSend(sendParam, false);
    // start to broadcast tx
    vm.startBroadcast(userPK);
    // @notice total BNB to send = fee + amountOfBNB
    asBnbMinter.mintAsBnbToChain{ value: fee.nativeFee + amountOfBNB }(sendParam);
    vm.stopBroadcast();
  }
}
