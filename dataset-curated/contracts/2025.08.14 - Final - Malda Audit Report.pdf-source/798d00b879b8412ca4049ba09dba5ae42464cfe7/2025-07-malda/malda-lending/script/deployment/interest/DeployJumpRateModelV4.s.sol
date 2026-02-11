// SPDX-License-Identifier: BSL-1.1
pragma solidity =0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {Deployer} from "src/utils/Deployer.sol";
import {JumpRateModelV4} from "src/interest/JumpRateModelV4.sol";

/**
 * forge script script/deployment/interest/DeployJumpRateModelV4.s.sol:DeployJumpRateModelV4  \
 *     --slow \
 *     --verify \
 *     --verifier-url <url> \
 *     --rpc-url <url> \
 *     --etherscan-api-key <key> \
 *     --sig "run((uint256,string,uint256,uint256,uint256,uint256))" "(750000000000000000,'ExampleName',2102400,20000000000000000,100000000000000000,500000000000000000)" \
 *     --broadcast
 */
contract DeployJumpRateModelV4 is Script {
    struct InterestData {
        uint256 kink;
        string name;
        uint256 blocksPerYear;
        uint256 baseRatePerYear;
        uint256 multiplierPerYear;
        uint256 jumpMultiplierPerYear;
    }

    function run(Deployer deployer, InterestData memory data, address owner) public returns (address) {
        uint256 key = vm.envUint("PRIVATE_KEY");

        bytes32 salt = getSalt(string.concat(data.name, "JumpRateModelV1.0.0"));

        console.log("Deploying JumpRateModelV4 for %s", data.name);

        address created = deployer.precompute(salt);

        // Deploy only if not already deployed
        if (created.code.length == 0) {
            vm.startBroadcast(key);
            created = deployer.create(
                salt,
                abi.encodePacked(
                    type(JumpRateModelV4).creationCode,
                    abi.encode(
                        data.blocksPerYear,
                        data.baseRatePerYear,
                        data.multiplierPerYear,
                        data.jumpMultiplierPerYear,
                        data.kink,
                        owner,
                        data.name
                    )
                )
            );
            vm.stopBroadcast();
            console.log("JumpRateModelV4 deployed at: %s", created);
        } else {
            console.log("Using existing JumpRateModelV4 at: %s", created);
        }

        return created;
    }

    function getSalt(string memory name) internal view returns (bytes32) {
        return keccak256(
            abi.encodePacked(msg.sender, bytes(vm.envString("DEPLOY_SALT")), bytes(string.concat(name, "-v1")))
        );
    }
}
