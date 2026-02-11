// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import { Script, console2 as console } from "forge-std/Script.sol";

import { ProxyLib } from "@aragon/osx-commons-contracts/src/utils/deployment/ProxyLib.sol";

import { AccessControlManager } from "@merkl/AccessControlManager.sol";
import { Distributor as MerklDistributor } from "@merkl/Distributor.sol";

import { MockERC20 } from "@mocks/MockERC20.sol";

contract DeployMerkl is Script {
    using ProxyLib for address;

    uint256 deployerPrivateKey = vm.envUint("DEPLOYMENT_PRIVATE_KEY");
    address deployer = vm.addr(deployerPrivateKey);

    function run() public {
        vm.startBroadcast(deployerPrivateKey);

        // Deploy OZ's AccessControlManager. This is needed for MerklDistributor contract.
        address acm = address(new AccessControlManager()).deployUUPSProxy(
            abi.encodeCall(
                AccessControlManager.initialize,
                (0x8bF0280B2557B98532EC21e6c070Dba1bFAaDbf2, 0xe96A819B77A0D54eC5773f079fe5E2A3d84995fC)
            )
        );

        address merklDistributor = address(new MerklDistributor()).deployUUPSProxy(
            abi.encodeCall(MerklDistributor.initialize, AccessControlManager(acm))
        );

        address tokenA = address(new MockERC20());
        address tokenB = address(new MockERC20());
        address tokenC = address(new MockERC20());
        MockERC20(tokenA).mint(merklDistributor, 1000e18);
        MockERC20(tokenB).mint(merklDistributor, 1000e18);

        console.log("MerklDistributor", merklDistributor);
        vm.stopBroadcast();
    }
}
