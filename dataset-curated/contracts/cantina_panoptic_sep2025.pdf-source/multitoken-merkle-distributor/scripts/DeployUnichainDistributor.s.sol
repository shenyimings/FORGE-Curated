pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {MerkleDistributor} from "../contracts/MerkleDistributor.sol";

contract DeployUnichainDistributor is Script {
    address[] tokenList = [
      0x078D782b760474a361dDA0AF3839290b0EF57AD6,
      0x20CAb320A855b39F724131C69424240519573f81,
      0x4200000000000000000000000000000000000006,
      0x8f187aA05619a017077f5308904739877ce9eA21,
      0x9151434b16b9763660705744891fA906F660EcC5,
      0x927B51f251480a681271180DA4de28D44EC4AfB8
    ];

    function run() external {
        uint256 pk = vm.envUint("PK"); // can be anvil default or your own
        vm.startBroadcast(pk);


        address[] memory tokens = new address[](6);
        for (uint i = 0; i < tokens.length; i++) {
            tokens[i] = tokenList[i];
        }

        MerkleDistributor dist = new MerkleDistributor(
            0xbdd0e6e4a36de4cdb9aa3ff02899863cb75ce2680f1db9d9fde6c8bfb246fdb6, // from unichain-merkle-data.json
            tokens, // from unichain-merkle-data.json
            35297793, // https://uniscan.xyz/block/countdown/35297793, ~Thu Dec 18 2025 09:22:12 UTC
            0x82BF455e9ebd6a541EF10b683dE1edCaf05cE7A1 // vault.panoptic.eth
        );

        console2.log("Distributor:", address(dist));
        vm.stopBroadcast();
    }
}
