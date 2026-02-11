pragma solidity ^0.8.20;

import "./BaseScript.sol";

import {ERC1967Proxy} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {CCTPRelayer} from "src/CCTPRelayer.sol";

contract DeploymentScript is BaseScript {
    function run() public {
        vm.startBroadcast();

        CCTPRelayer relayerImpl = new CCTPRelayer();
        ERC1967Proxy relayerProxy = new ERC1967Proxy(
            address(relayerImpl),
            abi.encodeWithSignature("initialize(address,address,address)", usdc, messenger, transmitter)
        );

        vm.stopBroadcast();

        console2.log("Deployed Relayer Address: ", address(relayerProxy));
    }
}
