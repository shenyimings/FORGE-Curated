// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {StableWrapper} from "../src/StableWrapper.sol";
import {StreamVault} from "../src/StreamVault.sol";
import {console2} from "forge-std/console2.sol";

contract SetPeersArbitrumScript is Script {
    function addressToBytes32(address _addr) public pure returns (bytes32) {
        return bytes32(uint256(uint160(_addr)));
    }

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // Arbitrum contracts
        address arbWrapper = 0xc380Fc06B25242DbeD574132a0C0e7ED77e8eD28;
        address arbVault = 0x58107a168E54802A7D35ebDBE6e9f82447d5Fb8d;

        // Base contracts
        address baseWrappedOFT = 0x450607C6A43F9Acb671aff183dD2Bd048261DD70;
        address baseStakedOFT = 0x2B890881268172d1697eB7bc9744F8424E5A3f5a;

        // Base Sepolia EID
        uint32 baseSepolia = 40245;

        vm.startBroadcast(deployerPrivateKey);

        StableWrapper wrapper = StableWrapper(arbWrapper);
        StreamVault vault = StreamVault(arbVault);

        wrapper.setPeer(baseSepolia, addressToBytes32(baseWrappedOFT));
        vault.setPeer(baseSepolia, addressToBytes32(baseStakedOFT));

        vm.stopBroadcast();

        console2.log("\nArbitrum Peer Setup Complete:");
        console2.log("-------------------");
        console2.log("Set Base peer for StableWrapper");
        console2.log("Set Base peer for StreamVault");
    }
}