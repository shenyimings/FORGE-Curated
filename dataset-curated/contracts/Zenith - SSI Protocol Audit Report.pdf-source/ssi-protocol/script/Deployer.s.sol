// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {Swap} from "../src/Swap.sol";
import {AssetToken} from "../src/AssetToken.sol";
import {AssetFactory} from "../src/AssetFactory.sol";
import {AssetIssuer} from "../src/AssetIssuer.sol";
import {AssetRebalancer} from "../src/AssetRebalancer.sol";
import {AssetFeeManager} from "../src/AssetFeeManager.sol";
import {StakeFactory} from "../src/StakeFactory.sol";
import {StakeToken} from "../src/StakeToken.sol";
import {AssetLocking} from "../src/AssetLocking.sol";
import {USSI} from "../src/USSI.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployerScript is Script {
    function setUp() public {}

    function run() public {
        address owner = vm.envAddress("OWNER");
        address vault = vm.envAddress("VAULT");
        address orderSigner = vm.envAddress("ORDER_SIGNER");
        address redeemToken = vm.envAddress("REDEEM_TOKEN");
        string memory chain = vm.envString("CHAIN_CODE");
        vm.startBroadcast();
        Swap swap = new Swap(owner, chain);
        AssetToken tokenImpl = new AssetToken();
        AssetFactory factoryImpl = new AssetFactory();
        address factory = address(new ERC1967Proxy(
            address(factoryImpl),
            abi.encodeCall(AssetFactory.initialize, (owner, address(swap), vault, chain, address(tokenImpl)))
        ));
        AssetIssuer issuer = new AssetIssuer(owner, address(factory));
        AssetRebalancer rebalancer = new AssetRebalancer(owner, address(factory));
        AssetFeeManager feeManager = new AssetFeeManager(owner, address(factory));
        // staking contracts
        StakeToken stakeTokenImpl = new StakeToken();
        StakeFactory stakeFactoryImpl = new StakeFactory();
        address stakeFactory = address(new ERC1967Proxy(
            address(stakeFactoryImpl),
            abi.encodeCall(StakeFactory.initialize, (owner, address(factory), address(stakeTokenImpl)))
        ));
        address assetLocking = address(new ERC1967Proxy(
            address(new AssetLocking()),
            abi.encodeCall(AssetLocking.initialize, owner)
        ));
        address uSSI = address(new ERC1967Proxy(
            address(new USSI()),
            abi.encodeCall(USSI.initialize, (owner, orderSigner, address(factory), redeemToken))
        ));
        address sUSSI = address(new ERC1967Proxy(
            address(stakeTokenImpl),
            abi.encodeCall(StakeToken.initialize, ("Staked USSI", "sUSSI", address(uSSI), 7 days, owner))
        ));
        vm.stopBroadcast();
        console.log(string.concat("swap=", vm.toString(address(swap))));
        console.log(string.concat("factory=", vm.toString(address(factory))));
        console.log(string.concat("issuer=", vm.toString(address(issuer))));
        console.log(string.concat("rebalancer=", vm.toString(address(rebalancer))));
        console.log(string.concat("feeManager=", vm.toString(address(feeManager))));
        console.log(string.concat("stakeFactory=", vm.toString(address(stakeFactory))));
        console.log(string.concat("assetLocking=", vm.toString(address(assetLocking))));
        console.log(string.concat("USSI=", vm.toString(address(uSSI))));
        console.log(string.concat("sUSSI=", vm.toString(address(sUSSI))));
    }
}
