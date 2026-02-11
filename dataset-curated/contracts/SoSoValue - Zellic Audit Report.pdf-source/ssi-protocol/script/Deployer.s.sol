// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.25;

import {Script, console} from "forge-std/Script.sol";
import {Swap} from "../src/Swap.sol";
import {AssetToken} from "../src/AssetToken.sol";
import {AssetFactory} from "../src/AssetFactory.sol";
import {AssetController} from "../src/AssetController.sol";
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
        address factory;
        {
            Swap swapImpl = new Swap();
            address swap = address(new ERC1967Proxy(
                address(swapImpl),
                abi.encodeCall(Swap.initialize, (owner, chain))
            ));
            AssetToken tokenImpl = new AssetToken();
            AssetFactory factoryImpl = new AssetFactory();
            factory = address(new ERC1967Proxy(
                address(factoryImpl),
                abi.encodeCall(AssetFactory.initialize, (owner, vault, chain, address(tokenImpl)))
            ));
            console.log(string.concat("tokenImpl=", vm.toString(address(tokenImpl))));
            console.log(string.concat("factoryImpl=", vm.toString(address(factoryImpl))));
            console.log(string.concat("swapImpl=", vm.toString(address(swapImpl))));
            console.log(string.concat("swap=", vm.toString(address(swap))));
            console.log(string.concat("factory=", vm.toString(address(factory))));
        }
        {
            AssetIssuer issuerImpl = new AssetIssuer();
            address issuer = address(new ERC1967Proxy(
                address(issuerImpl),
                abi.encodeCall(AssetController.initialize, (owner, address(factory)))
            ));
            AssetRebalancer rebalancerImpl = new AssetRebalancer();
            address rebalancer = address(new ERC1967Proxy(
                address(rebalancerImpl),
                abi.encodeCall(AssetController.initialize, (owner, address(factory)))
            ));
            AssetFeeManager feeManagerImpl = new AssetFeeManager();
            address feeManager = address(new ERC1967Proxy(
                address(feeManagerImpl),
                abi.encodeCall(AssetController.initialize, (owner, address(factory)))
            ));
            console.log(string.concat("issuerImpl=", vm.toString(address(issuerImpl))));
            console.log(string.concat("rebalancerImpl=", vm.toString(address(rebalancerImpl))));
            console.log(string.concat("feeMangerImpl=", vm.toString(address(feeManagerImpl))));
            console.log(string.concat("issuer=", vm.toString(address(issuer))));
            console.log(string.concat("rebalancer=", vm.toString(address(rebalancer))));
            console.log(string.concat("feeManager=", vm.toString(address(feeManager))));
        }
        StakeToken stakeTokenImpl;
        {
            stakeTokenImpl = new StakeToken();
            StakeFactory stakeFactoryImpl = new StakeFactory();
            address stakeFactory = address(new ERC1967Proxy(
                address(stakeFactoryImpl),
                abi.encodeCall(StakeFactory.initialize, (owner, address(factory), address(stakeTokenImpl)))
            ));
            AssetLocking assetLockingImpl = new AssetLocking();
            address assetLocking = address(new ERC1967Proxy(
                address(assetLockingImpl),
                abi.encodeCall(AssetLocking.initialize, owner)
            ));
            console.log(string.concat("stakeTokenImpl=", vm.toString(address(stakeTokenImpl))));
            console.log(string.concat("stakeFactoryImpl=", vm.toString(address(stakeFactoryImpl))));
            console.log(string.concat("assetLockingImpl=", vm.toString(address(assetLockingImpl))));
            console.log(string.concat("stakeFactory=", vm.toString(address(stakeFactory))));
            console.log(string.concat("assetLocking=", vm.toString(address(assetLocking))));
        }
        {
            USSI uSSIImpl = new USSI();
            address uSSI = address(new ERC1967Proxy(
                address(uSSIImpl),
                abi.encodeCall(USSI.initialize, (owner, orderSigner, address(factory), redeemToken, chain))
            ));
            address sUSSI = address(new ERC1967Proxy(
                address(stakeTokenImpl),
                abi.encodeCall(StakeToken.initialize, ("Staked USSI", "sUSSI", address(uSSI), 7 days, owner))
            ));
            console.log(string.concat("uSSIImpl=", vm.toString(address(uSSIImpl))));
            console.log(string.concat("USSI=", vm.toString(address(uSSI))));
            console.log(string.concat("sUSSI=", vm.toString(address(sUSSI))));
        }
        vm.stopBroadcast();
    }
}
