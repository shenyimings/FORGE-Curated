pragma solidity ^0.8.22;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";

import { FrxUSDOFTUpgradeable } from "contracts/frxUsd/FrxUSDOFTUpgradeable.sol";

/// @notice Deploy 1.1.0 implementation of frxUSD OFT
// TODO: add deploy scripts
contract DeployFrxUsdV110 is DeployFraxOFTProtocol {

    function run() public override {
        deployFrxUsd();
    }

    function deployFrxUsd() public broadcastAs(configDeployerPK) {
        address frxUsdOftImplementation = address(new FrxUSDOFTUpgradeable(broadcastConfig.endpoint));
        console.log("frxUSD v1.1.0 implementation: %s", frxUsdOftImplementation);
    }
}