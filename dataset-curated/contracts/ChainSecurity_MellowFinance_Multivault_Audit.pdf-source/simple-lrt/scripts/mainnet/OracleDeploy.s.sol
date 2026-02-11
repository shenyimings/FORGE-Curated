// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "../../src/utils/DVVRateOracle.sol";
import "../../src/utils/VaultRateOracle.sol";
import "forge-std/Script.sol";

contract Deploy is Script {
    function run() external {
        vm.startBroadcast(uint256(bytes32(vm.envBytes("MAINNET_DEPLOYER"))));
        VaultRateOracle oracle = new VaultRateOracle(0x7a4EffD87C2f3C55CA251080b1343b605f327E3a);

        console2.log("rate:", oracle.getRate());
        vm.stopBroadcast();
    }
}
