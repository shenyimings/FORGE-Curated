// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import { Script } from "forge-std/Script.sol";
import { JumpRateModelV2 } from "../../src/contracts/JumpRateModelV2.sol";
import { Config } from "./config/Config.sol";
import { CustomConfig } from "./config/CustomConfig.sol";
import { ProdConfig } from "./config/ProdConfig.sol";
import { console } from "forge-std/console.sol";

contract DeployInterestRateModels is Script {
    Config.CInterestRateModel[] public interestRateModels;
    mapping(string => address) public interestRateModelAddresses;

    event InterestRateModelDeployed(string name, address addr);

    function run(address account) external returns (Config.DeployedInterestRateModels memory) {
        Config config;
        
        if (block.chainid == 274) { // Lachain mainnet
            console.log("Deploying interest rate models on Lachain mainnet");
            config = new ProdConfig();
        } else {
            config = new CustomConfig();
        }

        Config.CInterestRateModel[] memory models = config.getInterestRateModels();

        vm.startBroadcast(account);

        for (uint256 i = 0; i < models.length; i++) {
            Config.CInterestRateModel memory irm = models[i];
            if (irm.modelType == Config.InterestRateModelType.JumpRateModelV2) {
                address ownerAddress = (irm.args.owner == address(0)) ? account : irm.args.owner;
                JumpRateModelV2 jumpRateModel = new JumpRateModelV2(
                    irm.args.baseRatePerYear,
                    irm.args.multiplierPerYear,
                    irm.args.jumpMultiplierPerYear,
                    irm.args.kink,
                    ownerAddress
                );
                interestRateModelAddresses[irm.name] = address(jumpRateModel);
                emit InterestRateModelDeployed(irm.name, address(jumpRateModel));
            }
        }

        vm.stopBroadcast();

        return Config.DeployedInterestRateModels({
            iRM_UXD_Updateable: interestRateModelAddresses["IRM_UXD_Updateable"],
            iRM_WETH_Updateable: interestRateModelAddresses["IRM_WETH_Updateable"],
            iRM_LAC_Updateable: interestRateModelAddresses["IRM_LAC_Updateable"],
            iRM_WBTC_Updateable: interestRateModelAddresses["IRM_WBTC_Updateable"],
            iRM_USDT_Updateable: interestRateModelAddresses["IRM_USDT_Updateable"],
            iRM_USDC_Updateable: interestRateModelAddresses["IRM_USDC_Updateable"],
            iRM_MockCToken_Updateable: interestRateModelAddresses["IRM_MockCToken_Updateable"]
        });
    }
}
