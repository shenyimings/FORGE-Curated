// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import { Script } from "forge-std/Script.sol";
import { Unitroller } from "../../src/contracts/Unitroller.sol";
import { Comptroller } from "../../src/contracts/Comptroller.sol";
import { PriceOracle } from "../../src/contracts/PriceOracle.sol";
import { ChainlinkPriceOracle } from "../../src/contracts/PriceOracle/ChainlinkPriceOracle.sol";
import { SimplePriceOracle } from "../../src/contracts/SimplePriceOracle.sol";
import { Config } from "./config/Config.sol";
import { console } from "forge-std/console.sol";

contract DeployCapyfiProtocol is Script {
    function run(address account) external returns (Config.DeployedProtocolContracts memory) {
        console.log("Deploying Capyfi Protocol with account:", account);
        
        vm.startBroadcast(account);
        
        Unitroller unitroller = new Unitroller();
        Comptroller comptroller = new Comptroller();

        // Set the unitroller as the comptroller's unitroller
        unitroller._setPendingImplementation(address(comptroller));
        comptroller._become(unitroller);
        // Deploy the price oracle
        address priceOracle;
        if (block.chainid == 274 || block.chainid == 1 || block.chainid == 7400) {
            priceOracle = address(new ChainlinkPriceOracle(new ChainlinkPriceOracle.LoadConfig[](0)));
        } else {
            priceOracle = address(new SimplePriceOracle());
        }

        // Delegatecall to _setPriceOracle through the Unitroller
        PriceOracle oracleInterface = PriceOracle(priceOracle);

        Comptroller uni = Comptroller(address(unitroller));
        uni._setPriceOracle(oracleInterface);

        uni._setCloseFactor(0.5e18); // set close factor
        uni._setLiquidationIncentive(1.08e18); // set liquidation incentive

        vm.stopBroadcast();

        return Config.DeployedProtocolContracts({
            unitroller: address(unitroller),
            comptroller: address(comptroller),
            priceOracle: address(priceOracle)
        });
    }
}
