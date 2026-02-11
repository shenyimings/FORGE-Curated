// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";

import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IMorpho} from "@morpho-blue/interfaces/IMorpho.sol";

import {LeverageManager} from "src/LeverageManager.sol";
import {LeverageToken} from "src/LeverageToken.sol";
import {BeaconProxyFactory} from "src/BeaconProxyFactory.sol";
import {MorphoLendingAdapter} from "src/lending/MorphoLendingAdapter.sol";
import {MorphoLendingAdapterFactory} from "src/lending/MorphoLendingAdapterFactory.sol";
import {ILeverageManager} from "src/interfaces/ILeverageManager.sol";
import {DeployConstants} from "script/DeployConstants.sol";

contract CoreDeploy is Script {
    function run() public {
        address deployerAddress = msg.sender;

        console.log("BlockNumber: ", block.number);
        console.log("ChainId: ", block.chainid);
        console.log("DeployerAddress: ", deployerAddress);

        console.log("Deploying...");

        vm.startBroadcast();

        LeverageToken leverageTokenImplementation = new LeverageToken();
        console.log("LeverageToken implementation deployed at: ", address(leverageTokenImplementation));

        BeaconProxyFactory leverageTokenFactory =
            new BeaconProxyFactory(address(leverageTokenImplementation), DeployConstants.SEAMLESS_TIMELOCK_SHORT);
        console.log("LeverageToken factory deployed at: ", address(leverageTokenFactory));

        address leverageManagerProxy = Upgrades.deployUUPSProxy(
            "LeverageManager.sol",
            abi.encodeCall(
                LeverageManager.initialize,
                (DeployConstants.SEAMLESS_TIMELOCK_SHORT, DeployConstants.SEAMLESS_TREASURY, leverageTokenFactory)
            )
        );
        console.log("LeverageManager proxy deployed at: ", address(leverageManagerProxy));

        MorphoLendingAdapter lendingAdapter =
            new MorphoLendingAdapter(ILeverageManager(address(leverageManagerProxy)), IMorpho(DeployConstants.MORPHO));
        console.log("LendingAdapter deployed at: ", address(lendingAdapter));

        MorphoLendingAdapterFactory lendingAdapterFactory = new MorphoLendingAdapterFactory(lendingAdapter);
        console.log("LendingAdapterFactory deployed at: ", address(lendingAdapterFactory));

        vm.stopBroadcast();
    }
}
