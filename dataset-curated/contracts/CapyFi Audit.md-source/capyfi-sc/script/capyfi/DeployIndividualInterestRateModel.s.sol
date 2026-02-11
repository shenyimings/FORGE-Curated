// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import { Script } from "forge-std/Script.sol";
import { JumpRateModelV2 } from "../../src/contracts/JumpRateModelV2.sol";
import { Config } from "./config/Config.sol";
import { CustomConfig } from "./config/CustomConfig.sol";
import { ProdConfig } from "./config/ProdConfig.sol";
import { console } from "forge-std/console.sol";

contract DeployIndividualInterestRateModel is Script {
    error ModelNotFound(string tokenSymbol);

    function run(address account, string memory tokenSymbol) external returns (address) {
        Config config;
        
        if (block.chainid == 274 || block.chainid == 1 || block.chainid == 7400) { // Lachain mainnet
            console.log("Deploying interest rate model for %s on Lachain mainnet", tokenSymbol);
            config = new ProdConfig();
        } else {
            console.log("Deploying interest rate model for %s", tokenSymbol);
            config = new CustomConfig();
        }

        Config.CInterestRateModel[] memory models = config.getInterestRateModels();
        string memory modelName = getModelNameForToken(tokenSymbol);
        
        for (uint256 i = 0; i < models.length; i++) {
            Config.CInterestRateModel memory irm = models[i];
            if (keccak256(abi.encodePacked(irm.name)) == keccak256(abi.encodePacked(modelName))) {
                vm.startBroadcast(account);
                
                address deployedModel;
                if (irm.modelType == Config.InterestRateModelType.JumpRateModelV2) {
                    address ownerAddress = (irm.args.owner == address(0)) ? account : irm.args.owner;
                    JumpRateModelV2 jumpRateModel = new JumpRateModelV2(
                        irm.args.baseRatePerYear,
                        irm.args.multiplierPerYear,
                        irm.args.jumpMultiplierPerYear,
                        irm.args.kink,
                        ownerAddress
                    );
                    deployedModel = address(jumpRateModel);
                    console.log("Interest rate model for %s deployed at: %s", tokenSymbol, deployedModel);
                    // log interest rate model args
                    console.log("Base rate per year: %s", irm.args.baseRatePerYear);
                    console.log("Multiplier per year: %s", irm.args.multiplierPerYear);
                    console.log("Jump multiplier per year: %s", irm.args.jumpMultiplierPerYear);
                    console.log("Kink: %s", irm.args.kink);
                    console.log("Owner: %s", ownerAddress);
                }
                
                vm.stopBroadcast();
                return deployedModel;
            }
        }
        
        revert ModelNotFound(tokenSymbol);
    }
    
    function getModelNameForToken(string memory tokenSymbol) internal pure returns (string memory) {
        bytes32 symbolHash = keccak256(abi.encodePacked(tokenSymbol));
        
        if (symbolHash == keccak256(abi.encodePacked("UXD"))) {
            return "IRM_UXD_Updateable";
        } else if (symbolHash == keccak256(abi.encodePacked("WETH"))) {
            return "IRM_WETH_Updateable";
        } else if (symbolHash == keccak256(abi.encodePacked("LAC"))) {
            return "IRM_LAC_Updateable";
        } else if (symbolHash == keccak256(abi.encodePacked("WBTC"))) {
            return "IRM_WBTC_Updateable";
        } else if (symbolHash == keccak256(abi.encodePacked("USDT"))) {
            return "IRM_USDT_Updateable";
        } else if (symbolHash == keccak256(abi.encodePacked("USDC"))) {
            return "IRM_USDC_Updateable";
        } else if (symbolHash == keccak256(abi.encodePacked("MOCK"))) {
            return "IRM_MockCToken_Updateable";
        } else {
            return "";
        }
    }
} 