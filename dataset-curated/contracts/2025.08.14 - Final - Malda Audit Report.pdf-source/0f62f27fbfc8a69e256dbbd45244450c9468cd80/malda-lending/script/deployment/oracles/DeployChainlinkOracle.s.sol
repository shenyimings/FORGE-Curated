// SPDX-License-Identifier: BSL-1.1
pragma solidity =0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {Deployer} from "src/utils/Deployer.sol";
import {ChainlinkOracle} from "src/oracles/ChainlinkOracle.sol";
import {IAggregatorV3} from "src/interfaces/external/chainlink/IAggregatorV3.sol";

/**
 * forge script DeployChainlinkOracle  \
 *     --slow \
 *     --verify \
 *     --verifier-url <url> \
 *     --rpc-url <url> \
 *     --etherscan-api-key <key> \
 *     --broadcast
 */
contract DeployChainlinkOracle is Script {
    function run(Deployer deployer) public returns (address) {
        uint256 key = vm.envUint("OWNER_PRIVATE_KEY");

        string[] memory symbols = new string[](1);
        symbols[0] = "USDCETH";

        IAggregatorV3[] memory feeds = new IAggregatorV3[](1);
        feeds[0] = IAggregatorV3(address(0));

        uint256[] memory baseUnits = new uint256[](1);
        baseUnits[0] = 18;

        bytes32 salt = getSalt("ChainlinkOracleV1.0");
        address created = deployer.precompute(salt);
        if (created.code.length > 0) {
            console.log(" ChainlinkOracle already deployed at: %s", created);
        } else {
            vm.startBroadcast(key);
            created = deployer.create(
                salt, abi.encodePacked(type(ChainlinkOracle).creationCode, abi.encode(symbols, feeds, baseUnits))
            );
            vm.stopBroadcast();
            console.log(" ChainlinkOracle deployed at: %s", created);
        }

        return created;
    }

    function getSalt(string memory name) internal view returns (bytes32) {
        return keccak256(
            abi.encodePacked(msg.sender, bytes(vm.envString("DEPLOY_SALT")), bytes(string.concat(name, "-v1")))
        );
    }
}
