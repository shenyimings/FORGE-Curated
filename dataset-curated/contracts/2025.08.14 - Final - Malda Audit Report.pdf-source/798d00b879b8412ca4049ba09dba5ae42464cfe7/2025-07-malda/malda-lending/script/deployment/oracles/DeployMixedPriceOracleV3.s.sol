// SPDX-License-Identifier: BSL-1.1
pragma solidity =0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {Deployer} from "src/utils/Deployer.sol";
import {MixedPriceOracleV3} from "src/oracles/MixedPriceOracleV3.sol";
import {OracleFeed} from "script/deployers/Types.sol";
import {IDefaultAdapter} from "src/interfaces/IDefaultAdapter.sol";

/**
 * forge script DeployMixedPriceOracleV3  \
 *     --slow \
 *     --verify \
 *     --verifier-url <url> \
 *     --rpc-url <url> \
 *     --etherscan-api-key <key> \
 *     --broadcast
 */
contract DeployMixedPriceOracleV3 is Script {
    function runWithFeeds(Deployer deployer, OracleFeed[] memory feeds, address roles, uint256 stalenessPeriod)
        public
        returns (address)
    {
        uint256 key = vm.envUint("PRIVATE_KEY");

        uint256 len = feeds.length;
        string[] memory symbols = new string[](len);
        IDefaultAdapter.PriceConfig[] memory configs = new IDefaultAdapter.PriceConfig[](len);
        for (uint256 i; i < len;) {
            symbols[i] = feeds[i].symbol;
            configs[i] = IDefaultAdapter.PriceConfig({
                defaultFeed: feeds[i].defaultFeed,
                toSymbol: feeds[i].toSymbol,
                underlyingDecimals: feeds[i].underlyingDecimals
            });
            unchecked {
                ++i;
            }
        }
        bytes32 salt = getSalt("MixedPriceOracleV1.0.0");
        address created = deployer.precompute(salt);
        if (created.code.length > 0) {
            console.log("MixedPriceOracleV3 already deployed at: %s", created);
        } else {
            vm.startBroadcast(key);
            created = deployer.create(
                salt,
                abi.encodePacked(
                    type(MixedPriceOracleV3).creationCode, abi.encode(symbols, configs, roles, stalenessPeriod)
                )
            );
            vm.stopBroadcast();
            console.log("MixedPriceOracleV3 deployed at: %s", created);
        }

        return created;
    }

    function run(Deployer deployer, address usdcFeed, address wethFeed, address roles, uint256 stalenessPeriod)
        public
        returns (address)
    {
        uint256 key = vm.envUint("PRIVATE_KEY");

        string[] memory symbols = new string[](2);
        symbols[0] = "mUSDC";
        symbols[1] = "mWETH";

        IDefaultAdapter.PriceConfig[] memory configs = new IDefaultAdapter.PriceConfig[](2);
        configs[0] = IDefaultAdapter.PriceConfig({defaultFeed: usdcFeed, toSymbol: "USD", underlyingDecimals: 6});

        configs[1] = IDefaultAdapter.PriceConfig({defaultFeed: wethFeed, toSymbol: "USD", underlyingDecimals: 18});

        bytes32 salt = getSalt("MixedPriceOracleV3");
        address created = deployer.precompute(salt);
        if (created.code.length > 0) {
            console.log("MixedPriceOracleV3 already deployed at: %s", created);
        } else {
            vm.startBroadcast(key);
            created = deployer.create(
                salt,
                abi.encodePacked(
                    type(MixedPriceOracleV3).creationCode, abi.encode(symbols, configs, roles, stalenessPeriod)
                )
            );
            vm.stopBroadcast();
            console.log("MixedPriceOracleV3 deployed at: %s", created);
        }

        return created;
    }

    function getSalt(string memory name) internal view returns (bytes32) {
        return keccak256(
            abi.encodePacked(msg.sender, bytes(vm.envString("DEPLOY_SALT")), bytes(string.concat(name, "-v1")))
        );
    }
}
