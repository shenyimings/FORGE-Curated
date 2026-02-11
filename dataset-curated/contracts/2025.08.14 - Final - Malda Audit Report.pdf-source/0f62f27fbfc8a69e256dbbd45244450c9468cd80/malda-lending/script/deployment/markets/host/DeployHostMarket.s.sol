// SPDX-License-Identifier: BSL-1.1
pragma solidity =0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {Deployer} from "src/utils/Deployer.sol";
import {mErc20Host} from "src/mToken/host/mErc20Host.sol";
import {mErc20Immutable} from "src/mToken/mErc20Immutable.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

/**
 * forge script DeployHostMarket  \
 *     --slow \
 *     --verify \
 *     --verifier-url <url> \
 *     --rpc-url <url> \
 *     --etherscan-api-key <key> \
 *     --sig "run((address,address,address,uint256,string,string,uint8,address,address,address))" "(0xD718826bBC28e61dC93aaCaE04711c8e755B4915,0x421f6ff3691e2c9d6e0447e0fc0157ef578f92c6,0x62def138a240b86dd44048b9e7dcc01b6391e638,20000000000000000,'Name','Sym',18,0x62def138a240b86dd44048b9e7dcc01b6391e638,0xb0fe2cdded33f9331e5ecd1c35640846a4fb9058,0x5cc15473f5bd753a09b81c7bc3d8dcea50eb0f9a)"  \
 *     --broadcast
 */
contract DeployHostMarket is Script {
    struct MarketData {
        address underlyingToken;
        address operator;
        address interestModel;
        uint256 exchangeRateMantissa;
        string name;
        string symbol;
        uint8 decimals;
        address owner;
        address zkVerifier;
        address roles;
    }

    function run(Deployer deployer, MarketData memory marketData) public returns (address) {
        uint256 key = vm.envUint("OWNER_PRIVATE_KEY");
        
        // Deploy implementation
        bytes32 implSalt =
            getSalt(string.concat("mTokenHost-implementationV1.0.1", addressToString(marketData.underlyingToken)));

        address implementation = deployer.precompute(implSalt);

        console.log("Deploying mErc20Host implementation", marketData.name);

        // Check if implementation already exists
        if (implementation.code.length > 0) {
            console.log("Implementation already exists at ", implementation);
        } else {
            console.log("Deploying mErc20Host implementation");
            vm.startBroadcast(key);
            implementation = deployer.create(implSalt, type(mErc20Host).creationCode);
            vm.stopBroadcast();
            console.log("Host implementation deployed at:", implementation);
        }

        // Prepare initialization data
        console.log("Details: ");
        console.log("  - marketData.underlyingToken: %", marketData.underlyingToken);
        console.log("  - marketData.operator: %", marketData.operator);
        console.log("  - marketData.interestModel: %", marketData.interestModel);
        console.log("  - marketData.exchangeRateMantissa: %", marketData.exchangeRateMantissa);
        console.log("  - marketData.owner: %", marketData.owner);
        console.log("  - marketData.zkVerifier: %", marketData.zkVerifier);
        console.log("  - marketData.roles: %", marketData.roles);
        console.log("  - marketData.name: ");
        console.logString(marketData.name);
        bytes memory initData = abi.encodeWithSelector(
            mErc20Host.initialize.selector,
            marketData.underlyingToken,
            marketData.operator,
            marketData.interestModel,
            marketData.exchangeRateMantissa,
            marketData.name,
            marketData.symbol,
            marketData.decimals,
            marketData.owner,
            marketData.zkVerifier,
            marketData.roles
        );

        // Deploy proxy
        bytes32 proxySalt = getSalt(string.concat(marketData.name, "V1.0.1"));
        address proxy = deployer.precompute(proxySalt);
        if (proxy.code.length > 0) {
            console.log("HostProxy already exists at ", proxy);
        } else {
            console.log("Deploying mErc20Host proxy");
            vm.startBroadcast(key);
            proxy = deployer.create(
                proxySalt,
                abi.encodePacked(
                    type(TransparentUpgradeableProxy).creationCode,
                    abi.encode(implementation, marketData.owner, initData)
                )
            );
            vm.stopBroadcast();
            console.log("Host Proxy deployed at:", proxy);
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
