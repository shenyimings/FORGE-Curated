pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import {MerkleDistributor} from "../contracts/MerkleDistributor.sol";

contract DeployMainnetDistributor is Script {
    address[] tokenList = [
        0x0000000000c5dc95539589fbD24BE07c6C14eCa4,
        0x18084fbA666a33d37592fA2633fD49a74DD93a88,
        0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599,
        0x27702a26126e0B3702af63Ee09aC4d1A084EF628,
        0x30aE41D5f9988D359c733232C6c693c0e645C77E,
        0x4E15361FD6b4BB609Fa63C81A2be19d873717870,
        0x514910771AF9Ca656af840dff83E8264EcF986CA,
        0x5aFE3855358E112B5647B952709E6165e1c1eEEe,
        0x6982508145454Ce325dDbE47a25d4ec3d2311933,
        0x6B175474E89094C44Da98b954EedeAC495271d0F,
        0x72e4f9F808C49A2a61dE9C5896298920Dc4EEEa9,
        0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2,
        0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48,
        0xb23d80f5FefcDDaa212212F028021B41DEd428CF,
        0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
        0xD31a59c85aE9D8edEFeC411D448f90841571b89c,
        0xd9Fcd98c322942075A5C3860693e9f4f03AAE07b,
        0xdAC17F958D2ee523a2206206994597C13D831ec7,
        0xdB792B1D8869A7CFc34916d6c845Ff05A7C9b789,
        0xDEf1CA1fb7FBcDC777520aa7f396b4E015F497aB,
        0xE0f63A424a4439cBE457D80E4f4b51aD25b2c56C,
        0xec53bF9167f50cDEB3Ae105f56099aaaB9061F83
    ];

    function run() external {
        uint256 pk = vm.envUint("PK"); // can be anvil default or your own
        vm.startBroadcast(pk);


        address[] memory tokens = new address[](22);
        for (uint i = 0; i < tokens.length; i++) {
            tokens[i] = tokenList[i];
        }

        MerkleDistributor dist = new MerkleDistributor(
            0xfc98cc0d1bbbbddd72b72d70d01dd5fc1bcf5bdb4286da286eb14c7174ea6895, // from mainnet-merkle-data.json
            tokens, // from mainnet-merkle-data.json
            24038514, // https://etherscan.io/block/countdown/24038514,  ~ Thu Dec 18 2025 09:19:27 
            0x82BF455e9ebd6a541EF10b683dE1edCaf05cE7A1 // vault.panoptic.eth
        );

        console2.log("Distributor:", address(dist));
        vm.stopBroadcast();
    }
}
