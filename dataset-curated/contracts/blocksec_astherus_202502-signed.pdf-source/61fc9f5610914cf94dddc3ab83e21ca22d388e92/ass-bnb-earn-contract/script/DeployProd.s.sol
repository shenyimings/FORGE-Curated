// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Script.sol";
import { Timelock } from "../src/Timelock.sol";
import { AsBNB } from "../src/AsBNB.sol";
import { YieldProxy } from "../src/YieldProxy.sol";
import { AsBnbMinter } from "../src/AsBnbMinter.sol";
import { Upgrades } from "openzeppelin-foundry-upgrades/Upgrades.sol";

interface AltIYieldProxy {
  function setMPCWallet(address _mpcWallet) external;
  function setRewardsSender(address _rewardsSender) external;
  function setSlisBNBProvider(address _slisBNBProvider) external;
  function setMinter(address _minter) external;
}

/*
 forge clean &&
 forge build &&
 forge script script/DeployProd.s.sol --rpc-url RPC_URL --verify --broadcast --private-key PRIVATE_KEY
*/

contract ProdDeploymentScript is Script {
  uint256 public deployerPrivateKey;
  address public deployer;

  address public admin;
  address public manager;
  address public bot;
  address public pauser;
  address public pauser2;

  // Lista
  address public slisBNB;
  address public slisBNBProvider;
  address public listaStakeManager;
  address public rewardSender;
  address public mpcWallet;

  // contracts
  address asBnb;
  address asBnbMinter;
  address payable yieldProxy;
  address timelock;

  // add this to be excluded from coverage report
  function test() public {}
  function setUp() public {
    // get private key
    deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    deployer = vm.addr(deployerPrivateKey);
    console.log("Deployer: %s", deployer);

    // --- roles
    admin = vm.envOr("ADMIN", deployer);
    console.log("Admin: %s", admin);

    pauser = vm.envAddress("PAUSER");
    require(pauser != address(0), "pauser is required");
    console.log("Pauser: %s", pauser);

    pauser2 = vm.envAddress("PAUSER2");
    require(pauser2 != address(0), "pauser2 is required");
    console.log("Pauser2: %s", pauser2);

    manager = vm.envAddress("MANAGER");
    require(manager != address(0), "manager is required");
    console.log("Manager: %s", manager);

    bot = vm.envAddress("BOT");
    require(bot != address(0), "bot is required");
    console.log("Pauser: %s", bot);

    // --- Lista
    slisBNB = vm.envAddress("SLISBNB");
    require(slisBNB != address(0), "slisBNB is required");
    console.log("slisBNB: %s", slisBNB);

    slisBNBProvider = vm.envAddress("SLISBNB_PROVIDER");
    require(slisBNBProvider != address(0), "slisBNBProvider is required");
    console.log("slisBNBProvider: %s", slisBNBProvider);

    listaStakeManager = vm.envAddress("LISTA_STAKE_MANAGER");
    require(listaStakeManager != address(0), "listaStakeManager is required");
    console.log("listaStakeManager: %s", listaStakeManager);

    rewardSender = vm.envAddress("REWARD_SENDER");
    require(rewardSender != address(0), "rewardSender is required");
    console.log("rewardSender: %s", rewardSender);

    mpcWallet = vm.envAddress("MPC_WALLET");
    require(mpcWallet != address(0), "mpcWallet is required");
    console.log("mpcWallet: %s", mpcWallet);
  }

  function run() public {
    vm.startBroadcast(deployerPrivateKey);

    // deploy asBNB
    asBnb = address(new AsBNB("Astherus BNB", "asBNB", deployer, deployer));
    console.log("AsBNB address: %s", asBnb);

    // deploy yieldProxy
    yieldProxy = payable(
      Upgrades.deployUUPSProxy(
        "YieldProxy.sol",
        abi.encodeCall(
          YieldProxy.initialize,
          (admin, manager, pauser, bot, slisBNB, asBnb, listaStakeManager, mpcWallet)
        )
      )
    );
    console.log("YieldProxy address: %s", yieldProxy);

    // deploy asBnbMinter
    asBnbMinter = Upgrades.deployUUPSProxy(
      "AsBnbMinter.sol",
      abi.encodeCall(AsBnbMinter.initialize, (admin, manager, pauser, bot, slisBNB, asBnb, yieldProxy))
    );
    console.log("AsBnbMinter address: %s", asBnbMinter);

    // deploy timelock
    address[] memory proposers = new address[](2);
    proposers[0] = manager;
    proposers[1] = deployer;
    address[] memory executors = new address[](2);
    executors[0] = manager;
    executors[1] = deployer;
    // min delay 60s, max delay 48 hours
    timelock = address(new Timelock(60, 48 hours, proposers, executors));
    console.log("Timelock address: %s", timelock);

    // ----- set roles ----- //
    // grant timelock as the admin of YieldProxy and asBnbMinter
    YieldProxy(yieldProxy).grantRole(YieldProxy(yieldProxy).DEFAULT_ADMIN_ROLE(), timelock);
    AsBnbMinter(asBnbMinter).grantRole(AsBnbMinter(asBnbMinter).DEFAULT_ADMIN_ROLE(), timelock);
    // add deployer as manager (temporary)
    YieldProxy(yieldProxy).grantRole(YieldProxy(yieldProxy).MANAGER(), deployer);
    AsBnbMinter(asBnbMinter).grantRole(AsBnbMinter(asBnbMinter).MANAGER(), deployer);
    // add deployer as bot
    YieldProxy(yieldProxy).grantRole(YieldProxy(yieldProxy).BOT(), deployer);
    AsBnbMinter(asBnbMinter).grantRole(AsBnbMinter(asBnbMinter).BOT(), deployer);
    // add pauser2
    YieldProxy(yieldProxy).grantRole(YieldProxy(yieldProxy).PAUSER(), pauser2);
    AsBnbMinter(asBnbMinter).grantRole(AsBnbMinter(asBnbMinter).PAUSER(), pauser2);

    // ----- configurations ----- //
    // config yieldProxy
    YieldProxy(yieldProxy).setMinter(asBnbMinter);
    YieldProxy(yieldProxy).setRewardsSender(rewardSender);
    YieldProxy(yieldProxy).setSlisBNBProvider(slisBNBProvider);

    // configure asBnbMinter
    AsBnbMinter(asBnbMinter).setMinMintAmount(0.001 ether);

    // configure asBnb
    AsBNB(asBnb).setMinter(asBnbMinter);

    vm.stopBroadcast();
  }
}
