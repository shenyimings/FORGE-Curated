// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
 
import {Script} from "../lib/forge-std/src/Script.sol";
import {console2} from "../lib/forge-std/src/console2.sol";
import {ClaimVault} from "../src/ClaimVault.sol";
 
contract ZeroBaseScript is Script {
    address constant ZBT = 0xfAB99fCF605fD8f4593EDb70A43bA56542777777;
    address signer = address(0xffff);
    address owner;

    function run() public {
        // Setup
        uint256 privateKey = vm.envUint("PRIVATE_KEY_MAIN");//Main
        vm.startBroadcast(privateKey);

        owner = vm.addr(privateKey);
        ClaimVault claimVault = new ClaimVault(address(ZBT),signer);
    
        console2.log("ZEROBASE deployed at:", address(claimVault));

        vm.stopBroadcast();
    }
}
