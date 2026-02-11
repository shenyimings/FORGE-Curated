// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import { Script } from "forge-std/Script.sol";
import { CustomConfig } from "./config/CustomConfig.sol";
import { Comptroller } from "../../src/contracts/Comptroller.sol";
import { SimplePriceOracle } from "../../src/contracts/SimplePriceOracle.sol";
import { InterestRateModel } from "../../src/contracts/InterestRateModel.sol";
import { CEther } from "../../src/contracts/CEther.sol";
import { Config } from "./config/Config.sol";
import { ProdConfig } from "./config/ProdConfig.sol";
import { console } from "forge-std/console.sol";
import { HelperConfig } from "../HelperConfig.s.sol";

contract DeployCEther is Script {
    address public cEtherAddress;

    function run(address account) external returns (address) {
        console.log("Deploying CEther token with account:", account);

        Config config;
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory networkConfig = helperConfig.getConfig();

        console.log(networkConfig.unitroller);

        config = helperConfig.getConfigBasedOnNetwork();


        Config.CTokenInfo[] memory configCtokens = config.getCTokens();
        vm.startBroadcast(account);

        for (uint256 i = 0; i < configCtokens.length; i++) {
            Config.CTokenInfo memory c = configCtokens[i];

            if (keccak256(abi.encodePacked(c.args.symbol)) == keccak256(abi.encodePacked("caWETH"))) {
                console.log("Deploying caETH...");

                c.args.underlying = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
                c.args.interestRateModel = networkConfig.interestRateModels.iRM_WETH_Updateable;
                c.args.unitroller = networkConfig.unitroller;
                c.args.admin = account;

                CEther cEther = new CEther(
                    Comptroller(c.args.unitroller),
                    InterestRateModel(c.args.interestRateModel),
                    c.args.initialExchangeRateMantissa,
                    "Capyfi Ether",
                    "caETH",
                    c.args.decimals,
                    payable(c.args.admin)
                );

                cEtherAddress = address(cEther);
                console.log("Deployed caETH at:", cEtherAddress);
                break; 
            }
        }

        vm.stopBroadcast();
        return cEtherAddress;
    }
}
