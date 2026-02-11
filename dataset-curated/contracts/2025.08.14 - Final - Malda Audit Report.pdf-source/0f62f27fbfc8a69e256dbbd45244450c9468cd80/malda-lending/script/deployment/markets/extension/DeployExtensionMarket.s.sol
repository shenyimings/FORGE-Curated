// SPDX-License-Identifier: BSL-1.1
pragma solidity =0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {Deployer} from "src/utils/Deployer.sol";
import {mTokenGateway} from "src/mToken/extension/mTokenGateway.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

/**
 * forge script DeployExtensionMarket  \
 *     --slow \
 *     --verify \
 *     --verifier-url <url> \
 *     --rpc-url <url> \
 *     --etherscan-api-key <key> \
 *     --sig "run((address,address,address))" "(0x0,0x0,0x0)" \
 *     --broadcast
 */
contract DeployExtensionMarket is Script {
    function run(
        Deployer deployer,
        address underlyingToken,
        string calldata name,
        address owner,
        address zkVerifier,
        address roles
    ) public returns (address) {
        uint256 key = vm.envUint("OWNER_PRIVATE_KEY");

        // Deploy implementation
        bytes32 implSalt = getSalt(string.concat("mTokenGateway-implementationV1.0.1", addressToString(underlyingToken)));

        address implementation = deployer.precompute(implSalt);

        console.log("Deploying mTokenGateway implementation", name);
        console.log("Deploying mTokenGateway implementation for token ", underlyingToken);

        // Check if implementation already exists
        if (implementation.code.length > 0) {
            console.log("Implementation already exists at ", implementation);
        } else {
            vm.startBroadcast(key);
            implementation = deployer.create(implSalt, type(mTokenGateway).creationCode);
            vm.stopBroadcast();

            console.log("Extension implementation deployed at:", implementation);
        }

        // Prepare initialization data
        bytes memory initData = abi.encodeWithSelector(
            mTokenGateway.initialize.selector, payable(owner), underlyingToken, roles, zkVerifier
        );

        // Deploy proxy
        bytes32 proxySalt = getSalt(string.concat(name, "V1.0.1"));
        address proxy = deployer.precompute(proxySalt);
        // Check if proxy already exists
        if (proxy.code.length > 0) {
            console.log("Extension Proxy already exists at ", proxy);
        } else {
            vm.startBroadcast(key);
            proxy = deployer.create(
                proxySalt,
                abi.encodePacked(
                    type(TransparentUpgradeableProxy).creationCode, abi.encode(implementation, owner, initData)
                )
            );
            vm.stopBroadcast();
            console.log("Extension Proxy deployed at:", proxy);
        }

        return proxy;
    }

    function getSalt(string memory name) internal view returns (bytes32) {
        return keccak256(
            abi.encodePacked(msg.sender, bytes(vm.envString("DEPLOY_SALT")), bytes(string.concat(name, "-v1")))
        );
    }

    function addressToString(address _addr) internal pure returns (string memory) {
        bytes32 value = bytes32(uint256(uint160(_addr)));
        bytes memory alphabet = "0123456789abcdef";

        bytes memory str = new bytes(42);
        str[0] = "0";
        str[1] = "x";
        for (uint256 i = 0; i < 20; i++) {
            str[2 + i * 2] = alphabet[uint8(value[i + 12] >> 4)];
            str[3 + i * 2] = alphabet[uint8(value[i + 12] & 0x0f)];
        }
        return string(str);
    }
}
