// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Script.sol";
import { YieldProxy } from "../src/YieldProxy.sol";
import { Upgrades } from "openzeppelin-foundry-upgrades/Upgrades.sol";

interface AltIYieldProxy {
  function setMPCWallet(address _mpcWallet) external;
  function setRewardsSender(address _rewardsSender) external;
  function setSlisBNBProvider(address _slisBNBProvider) external;
  function setMinter(address _minter) external;
}

contract YieldProxyScript is Script {
  address admin;
  address manager;
  address pauser;
  address bot;
  address minter;
  address token;
  address asBnb;
  address stakeManager;
  address slisBNBProvider;
  address mpcWallet;
  uint256 deployerPK;
  address deployer;

  // add this to be excluded from coverage report
  function test() public {}
  function setUp() public {
    // get private key
    deployerPK = vm.envUint("PRIVATE_KEY");
    deployer = vm.addr(deployerPK);
    console.log("Deployer: %s", deployer);

    // --- roles
    admin = vm.envOr("ADMIN", deployer);
    console.log("Admin: %s", admin);

    pauser = vm.envOr("PAUSER", admin);
    console.log("Pauser: %s", pauser);

    minter = vm.envOr("MINTER", admin);
    console.log("Minter: %s", minter);

    manager = vm.envOr("MANAGER", admin);
    console.log("Manager: %s", manager);

    bot = vm.envOr("BOT", admin);
    console.log("Pauser: %s", bot);

    // --- contract addresses
    // token
    token = vm.envAddress("TOKEN");
    require(token != address(0), "Token address cannot be null");
    console.log("Token: %s", token);

    // asBnb
    asBnb = vm.envAddress("ASBNB");
    require(asBnb != address(0), "AsBnb address cannot be null");
    console.log("AsBnb: %s", asBnb);

    // Lista Stake Manager
    stakeManager = vm.envAddress("STAKE_MANAGER");
    require(stakeManager != address(0), "Stake Manager address cannot be null");
    console.log("Stake Manager: %s", stakeManager);

    // MPC Wallet
    mpcWallet = vm.envAddress("MPC_WALLET");
    require(mpcWallet != address(0), "MPC Wallet address cannot be null");
    console.log("MPC Wallet: %s", mpcWallet);

    slisBNBProvider = vm.envAddress("SLISBNB_PROVIDER");
    require(slisBNBProvider != address(0), "slisBNBProvider address cannot be null");
    console.log("slisBNBProvider: %s", slisBNBProvider);
  }

  function run() public {
    vm.startBroadcast(deployerPK);
    // deploy yield proxy
    address proxy = Upgrades.deployUUPSProxy(
      "YieldProxy.sol",
      abi.encodeCall(YieldProxy.initialize, (admin, manager, pauser, bot, token, asBnb, stakeManager, mpcWallet))
    );
    // ----- set minter
    AltIYieldProxy(proxy).setMPCWallet(deployer);
    AltIYieldProxy(proxy).setRewardsSender(deployer);
    if (minter != address(0)) {
      AltIYieldProxy(proxy).setMinter(minter);
    }
    if (slisBNBProvider != address(0)) {
      AltIYieldProxy(proxy).setSlisBNBProvider(slisBNBProvider);
    }
    vm.stopBroadcast();

    console.log("YieldProxy proxy address: %s", proxy);
    address implAddress = Upgrades.getImplementationAddress(proxy);
    console.log("YieldProxy implementation address: %s", implAddress);
  }
}
