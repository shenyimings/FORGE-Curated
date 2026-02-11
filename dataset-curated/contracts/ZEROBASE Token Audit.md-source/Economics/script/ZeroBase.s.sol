// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;
 
import {Script} from "../lib/forge-std/src/Script.sol";
import {console2} from "../lib/forge-std/src/console2.sol";
import "../src/ZeroBase.sol";
 
contract ZeroBaseScript is Script {
    address constant LAYERZERO_ENDPOINT = 0x6EDCE65403992e310A62460808c4b910D972f10f;
    // address constant LAYERZERO_ENDPOINT = 0x6EDCE65403992e310A62460808c4b910D972f10f;

    function run() public {
        // Setup
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(privateKey);

        // Deploy
        ZEROBASE zeroBase = new ZEROBASE(LAYERZERO_ENDPOINT, vm.addr(privateKey), vm.addr(privateKey));
        console2.log("ZEROBASE deployed at:", address(zeroBase));

        vm.stopBroadcast();
    }
}
//forge script script/ZeroBase.s.sol:ZeroBaseScript --rpc-url https://eth-sepolia.api.onfinality.io/public --broadcast --etherscan-api-key F41MZG297XBH3D4RHMN96Y6S15HYFDJQNC --verify
//forge script script/ZeroBase.s.sol:ZeroBaseScript --rpc-url https://bsc-testnet.public.blastapi.io --broadcast --etherscan-api-key XUXXIDDRA5UMHVVXFUSKDFUGRXVM5ZX2E2 --verify
