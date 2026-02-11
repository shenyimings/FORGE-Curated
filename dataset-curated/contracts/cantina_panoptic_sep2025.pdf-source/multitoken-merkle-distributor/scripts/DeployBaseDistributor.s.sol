pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {MerkleDistributor} from "../contracts/MerkleDistributor.sol";

contract DeployBaseDistributor is Script {
    address[] tokenList = [
        0x2Da56AcB9Ea78330f947bD57C54119Debda7AF71,
        0x4200000000000000000000000000000000000006,
        0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913,
        0x940181a94A35A4569E4529A3CDfB74e38FD98631,
        0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf
    ];

    function run() external {
        uint256 pk = vm.envUint("PK"); // can be anvil default or your own
        vm.startBroadcast(pk);

        address[] memory tokens = new address[](5);
        for (uint i = 0; i < tokens.length; i++) {
            tokens[i] = tokenList[i];
        }

        MerkleDistributor dist = new MerkleDistributor(
            0xb2b025a07391f5072db59ddbd44c1f08d8c45aaf6540daab2f8a5ba21bb340d0, // from base-merkle-data.json
            tokens, // from base-merkle-data.json
            39629300, // https://basescan.org/block/countdown/39629300, ~Thu Dec 18 2025 09:52:04 UTC
            0x82BF455e9ebd6a541EF10b683dE1edCaf05cE7A1 // vault.panoptic.eth
        );

        console2.log("Distributor:", address(dist));
        vm.stopBroadcast();
    }
}
