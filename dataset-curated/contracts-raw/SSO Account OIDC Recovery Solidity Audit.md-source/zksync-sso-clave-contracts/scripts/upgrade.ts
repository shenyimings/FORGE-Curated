import { ethers } from "ethers";
import { task } from "hardhat/config";
import { Wallet } from "zksync-ethers";

// TODO: add support for constructor args
task("upgrade", "Upgrades ZKsync SSO contracts")
  .addParam("proxy", "address of the proxy to upgrade")
  .addParam("beaconAddress", "address of the beacon proxy for the upgrade")
  .addPositionalParam("artifactName", "name of the artifact to upgrade to")
  .setAction(async (cmd, hre) => {
    const { LOCAL_RICH_WALLETS, getProvider, deployFactory, create2, ethersStaticSalt } = require("../test/utils");

    let privateKey: string;
    if (hre.network.name == "inMemoryNode" || hre.network.name == "dockerizedNode") {
      console.log("Using local rich wallet");
      privateKey = LOCAL_RICH_WALLETS[0].privateKey;
      cmd.fund = "1";
    } else {
      if (!process.env.WALLET_PRIVATE_KEY) throw "Wallet private key wasn't found in .env file!";
      privateKey = process.env.WALLET_PRIVATE_KEY;
    }

    const wallet = new Wallet(privateKey, getProvider());
    let newImpl;

    console.log("Deploying new implementation of", cmd.artifactName, "contract...");
    if (cmd.artifactName == "AAFactory") {
      if (!cmd.beaconAddress) throw "Deploying the AAFactory requires a Beacon Address '--beacon-address <value>'";
      newImpl = await deployFactory(wallet, cmd.beaconAddress);
    } else {
      newImpl = await create2(cmd.artifactName, wallet, ethersStaticSalt, []);
    }
    console.log("New implementation deployed at:", await newImpl.getAddress());

    console.log("Upgrading proxy at", cmd.proxy, "to new implementation...");
    const abi = ["function upgradeTo(address newImplementation)"];
    const proxy = new ethers.Contract(cmd.proxy, abi, wallet);
    const tx = await proxy.upgradeTo(await newImpl.getAddress());
    await tx.wait();
    console.log("Proxy upgraded successfully");
  });
