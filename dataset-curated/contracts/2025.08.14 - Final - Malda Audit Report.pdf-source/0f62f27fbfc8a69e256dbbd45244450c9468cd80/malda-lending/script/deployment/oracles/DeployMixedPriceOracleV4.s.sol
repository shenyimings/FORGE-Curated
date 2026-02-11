// SPDX-License-Identifier: BSL-1.1
pragma solidity =0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {Deployer} from "src/utils/Deployer.sol";
import {MixedPriceOracleV4} from "src/oracles/MixedPriceOracleV4.sol";
import {OracleFeedV4} from "script/deployers/Types.sol";
import {IDefaultAdapter} from "src/interfaces/IDefaultAdapter.sol";

/**
 * forge script DeployMixedPriceOracleV4  \
 *     --slow \
 *     --verify \
 *     --verifier-url <url> \
 *     --rpc-url <url> \
 *     --etherscan-api-key <key> \
 *     --broadcast
 */
contract DeployMixedPriceOracleV4 is Script {
    //function runWithFeeds(Deployer deployer, OracleFeedV4[] memory feeds, address roles, uint256 stalenessPeriod)
    function run()
        public
        returns (address)
    {
        Deployer deployer = Deployer(payable(0xc781BaD08968E324D1B91Be3cca30fAd86E7BF98));
        address roles = 0x1211d07F0EBeA8994F23EC26e1e512929FC8Ab08;
        uint256 stalenessPeriod = 86400;
        
        OracleFeedV4[] memory feeds = new OracleFeedV4[](16);
        // usdc
        feeds[0] = OracleFeedV4({
            symbol: "mUSDC",
            apiV3Feed: 0x874b4573B30629F696653EE101528C7426FFFb6b,
            eOracleFeed: 0x6E4cda6DfFAB6b72682Bf1693c32ed75074905D9,
            toSymbol: "USD",
            underlyingDecimals: 6
        });
        feeds[1] = OracleFeedV4({
            symbol: "USDC",
            apiV3Feed: 0x874b4573B30629F696653EE101528C7426FFFb6b,
            eOracleFeed: 0x6E4cda6DfFAB6b72682Bf1693c32ed75074905D9,
            toSymbol: "USD",
            underlyingDecimals: 6
        });
        //usdt
        feeds[2] = OracleFeedV4({
            symbol: "mUSDT",
            apiV3Feed: 0x0c547EC8B69F50d023D52391b8cB82020c46b848,
            eOracleFeed: 0x71BEf769d87249D61Edd31941A6BB7257d4bAE5F,
            toSymbol: "USD",
            underlyingDecimals: 6
        });
        feeds[3] = OracleFeedV4({
            symbol: "USDT",
            apiV3Feed: 0x0c547EC8B69F50d023D52391b8cB82020c46b848,
            eOracleFeed: 0x71BEf769d87249D61Edd31941A6BB7257d4bAE5F,
            toSymbol: "USD",
            underlyingDecimals: 6
        });
        //WBTC
        feeds[4] = OracleFeedV4({
            symbol: "mWBTC",
            apiV3Feed: 0xa34Aa6654A7E45fB000F130453Ba967Fd57851C1,
            eOracleFeed: 0xdEd5C17969220990de62cd1894BcDf49dC28583E,
            toSymbol: "USD",
            underlyingDecimals: 8
        });
        feeds[5] = OracleFeedV4({
            symbol: "WBTC",
            apiV3Feed: 0xa34Aa6654A7E45fB000F130453Ba967Fd57851C1,
            eOracleFeed: 0xdEd5C17969220990de62cd1894BcDf49dC28583E,
            toSymbol: "USD",
            underlyingDecimals: 8
        });
        //WETH
        feeds[6] = OracleFeedV4({
            symbol: "mWETH",
            apiV3Feed: 0x2284eC83978Fe21A0E667298d9110bbeaED5E9B4,
            eOracleFeed: 0x58B375D4A5ddAa7df7C54FE5A6A4B7024747fBE3,
            toSymbol: "USD",
            underlyingDecimals: 18
        });
        feeds[7] = OracleFeedV4({
            symbol: "WETH",
            apiV3Feed: 0x2284eC83978Fe21A0E667298d9110bbeaED5E9B4,
            eOracleFeed: 0x58B375D4A5ddAa7df7C54FE5A6A4B7024747fBE3,
            toSymbol: "USD",
            underlyingDecimals: 18
        });
        //ezETH
        feeds[8] = OracleFeedV4({
            symbol: "mezETH",
            apiV3Feed: 0x01600fE800B9a1c3638F24c1408F2d177133074C,
            eOracleFeed: 0x1C19C36926D353fD5889F0FD9e2a72570196B4EC,
            toSymbol: "USD",
            underlyingDecimals: 18
        });
        feeds[9] = OracleFeedV4({
            symbol: "ezETH",
            apiV3Feed: 0x01600fE800B9a1c3638F24c1408F2d177133074C,
            eOracleFeed: 0x1C19C36926D353fD5889F0FD9e2a72570196B4EC,
            toSymbol: "USD",
            underlyingDecimals: 18
        });
        //weETH
        feeds[10] = OracleFeedV4({
            symbol: "mweETH",
            apiV3Feed: 0x6Bd45e0f0adaAE6481f2B4F3b867911BF5f8321b,
            eOracleFeed: 0xA0a8c2c8e506a92DE06D0815d6b0B8042e246BB4,
            toSymbol: "USD",
            underlyingDecimals: 18
        });
        feeds[11] = OracleFeedV4({
            symbol: "weETH",
            apiV3Feed: 0x6Bd45e0f0adaAE6481f2B4F3b867911BF5f8321b,
            eOracleFeed: 0xb71B0D0Bf654D360E5CD5B39E8bbD7CEE9970E09,
            toSymbol: "USD",
            underlyingDecimals: 18
        });
        //rsETH
        feeds[12] = OracleFeedV4({
            symbol: "mwrsETH",
            apiV3Feed: 0xB7b25D8e8490a138c854426e7000C7E114C2DebF,
            eOracleFeed: 0xE6690E91d399e9f522374399412EbE04DA991315,
            toSymbol: "USD",
            underlyingDecimals: 18
        });
        feeds[13] = OracleFeedV4({
            symbol: "wrsETH",
            apiV3Feed: 0xB7b25D8e8490a138c854426e7000C7E114C2DebF,
            eOracleFeed: 0xE6690E91d399e9f522374399412EbE04DA991315,
            toSymbol: "USD",
            underlyingDecimals: 18
        });
        //wstETH
        feeds[14] = OracleFeedV4({
            symbol: "mwstETH",
            apiV3Feed: 0x043F8c576154E19E05cD53b21Baab86deC75c728,
            eOracleFeed: 0xB37568E6d24715E0C97e345C328f208dDbF8A7A9,
            toSymbol: "USD",
            underlyingDecimals: 18
        });
        feeds[15] = OracleFeedV4({
            symbol: "wstETH",
            apiV3Feed: 0x043F8c576154E19E05cD53b21Baab86deC75c728,
            eOracleFeed: 0xB37568E6d24715E0C97e345C328f208dDbF8A7A9,
            toSymbol: "USD",
            underlyingDecimals: 18
        });




        uint256 key = vm.envUint("OWNER_PRIVATE_KEY");

        uint256 len = feeds.length;
        string[] memory symbols = new string[](len);
        MixedPriceOracleV4.PriceConfig[] memory configs = new MixedPriceOracleV4.PriceConfig[](len);
        for (uint256 i; i < len;) {
            symbols[i] = feeds[i].symbol;
            configs[i] = MixedPriceOracleV4.PriceConfig({
                api3Feed: feeds[i].apiV3Feed,
                eOracleFeed: feeds[i].eOracleFeed,
                toSymbol: feeds[i].toSymbol,
                underlyingDecimals: feeds[i].underlyingDecimals
            });
            unchecked {
                ++i;
            }
        }
        bytes32 salt = getSalt("MixedPriceOracleV4V1.0.1");
        address created = deployer.precompute(salt);
        if (created.code.length > 0) {
            console.log("MixedPriceOracleV4 already deployed at: %s", created);
        } else {
            vm.startBroadcast(key);
            created = deployer.create(
                salt,
                abi.encodePacked(
                    type(MixedPriceOracleV4).creationCode, abi.encode(symbols, configs, roles, stalenessPeriod)
                )
            );
            vm.stopBroadcast();
            console.log("MixedPriceOracleV4 deployed at: %s", created);
        }

        return created;
    }

    function getSalt(string memory name) internal view returns (bytes32) {
        return keccak256(
            abi.encodePacked(msg.sender, bytes(vm.envString("DEPLOY_SALT")), bytes(string.concat(name, "-v1")))
        );
    }
}
