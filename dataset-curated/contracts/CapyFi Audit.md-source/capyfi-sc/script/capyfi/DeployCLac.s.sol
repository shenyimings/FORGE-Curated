// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import { Script } from "forge-std/Script.sol";
import { CustomConfig } from "./config/CustomConfig.sol";
import { Comptroller } from "../../src/contracts/Comptroller.sol";
import { SimplePriceOracle } from "../../src/contracts/SimplePriceOracle.sol";
import { InterestRateModel } from "../../src/contracts/InterestRateModel.sol";
import { CLac } from "../../src/contracts/CLac.sol";
import { Config } from "./config/Config.sol";
import { ProdConfig } from "./config/ProdConfig.sol";
import { console } from "forge-std/console.sol";
import { HelperConfig } from "../HelperConfig.s.sol";

contract DeploycaLAC is Script {
    address public caLACAddress;

    function run(address account) external returns (address) {
        console.log("Deploying caLAC token with account:", account);

        Config config;
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory networkConfig = helperConfig.getConfig();

        console.log(networkConfig.unitroller);

        if (block.chainid == 274) { // Lachain mainnet
            console.log(" Deploying on Lachain Mainnet");
            config = new ProdConfig();
        } else {
            console.log("Deploying on Test/Dev Network");
            config = new CustomConfig();
        }

        Config.CTokenInfo[] memory configCtokens = config.getCTokens();
        vm.startBroadcast(account);

        for (uint256 i = 0; i < configCtokens.length; i++) {
            Config.CTokenInfo memory c = configCtokens[i];

            if (keccak256(abi.encodePacked(c.args.symbol)) == keccak256(abi.encodePacked("caLAC"))) {
                console.log("Deploying caLAC...");

                c.args.underlying = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
                c.args.interestRateModel = networkConfig.interestRateModels.iRM_LAC_Updateable;
                c.args.unitroller = networkConfig.unitroller;
                c.args.admin = account;

                CLac cLac = new CLac(
                    Comptroller(c.args.unitroller),
                    InterestRateModel(c.args.interestRateModel),
                    c.args.initialExchangeRateMantissa,
                    c.args.name,
                    c.args.symbol,
                    c.args.decimals,
                    payable(c.args.admin)
                );

                caLACAddress = address(cLac);
                console.log("Deployed caLAC at:", caLACAddress);
                break; 
            }
        }

        vm.stopBroadcast();
        return caLACAddress;
    }
}
