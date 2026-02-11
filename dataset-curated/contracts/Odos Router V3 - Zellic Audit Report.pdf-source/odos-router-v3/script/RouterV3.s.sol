// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {Script, console} from "forge-std/Script.sol";
import {OdosRouterV3} from "../contracts/OdosRouterV3.sol";
import {IOdosRouterV3} from "../interfaces/IOdosRouterV3.sol";


interface ImmutableCreate2Factory {
    function safeCreate2(
        bytes32 salt,
        bytes calldata initializationCode
    ) external payable returns (address deploymentAddress);
}

contract RouterV3Script is Script {
    bytes32 salt =
        0x000636843c30b6b10d3dc9af803e7a7956aa994ca799c086534bec424e8c0660;
    address liquidator = 0x498020622CA0d5De103b7E78E3eFe5819D0d28AB;
    uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);
    address newOwner = 0x498292DC123f19Bdbc109081f6CF1D0E849A9daF;
    ImmutableCreate2Factory create2Factory =
        ImmutableCreate2Factory(0x0000000000FFe8B47B3e2130213B802212439497);
    address targetAddress = 0x0D05a118E2f31d76237f3cd3868FFaE961A00D05;

    function run() public {
        vm.startBroadcast(deployerPrivateKey);
        console.log("Deploying Odos Router on chain:", block.chainid);
        bytes memory initializationCode = abi.encodePacked(
            type(OdosRouterV3).creationCode,
            abi.encode(deployer)
        );
        OdosRouterV3 odosRouter = OdosRouterV3(payable(create2Factory.safeCreate2(salt, initializationCode) ));
        console.log("Odos Router deployed:", address(odosRouter));
        require(address(odosRouter) == targetAddress, "Odos Router deployed to wrong address");
        console.log("Set liquidator address:", liquidator);
        odosRouter.changeLiquidatorAddress(liquidator);
        console.log("Transfer ownership to:", newOwner);
        odosRouter.transferOwnership(newOwner);
        vm.stopBroadcast();
    }
}
