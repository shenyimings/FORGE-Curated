pragma solidity ^0.8.20;

import "./BaseScript.sol";

import {ERC1967Proxy} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {CCTPRelayer} from "src/CCTPRelayer.sol";

contract SetRouterScript is BaseScript {
    function run() public {
        vm.startBroadcast();

        CCTPRelayer relayer = CCTPRelayer(payable(address(0)));
        relayer.setSwapRouter(0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45);

        vm.stopBroadcast();
    }
}
