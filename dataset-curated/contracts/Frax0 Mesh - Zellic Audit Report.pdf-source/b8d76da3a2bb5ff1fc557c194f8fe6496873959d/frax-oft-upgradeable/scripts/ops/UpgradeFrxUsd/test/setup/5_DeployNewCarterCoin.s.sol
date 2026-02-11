// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { FraxOFTAdapterUpgradeable } from "contracts/FraxOFTAdapterUpgradeable.sol";
import { ERC20Mock } from "contracts/mocks/ERC20Mock.sol";
import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";

/// @dev deploy "new" Carter coin with initial supply of the lockbox
/// forge script scripts/UpgradeFrax/test/setup/5_DeployNewCarterCoin.s.sol --rpc-url https://rpc.frax.com
contract DeployNewCarterCoin is DeployFraxOFTProtocol {
    ERC20Mock public erc20;

    function run() public override broadcastAs(configDeployerPK) {
        erc20 = new ERC20Mock("New Carter Coin", "nCAC");
        erc20.mint(vm.addr(configDeployerPK), 500_000e18);
    
        console.log("New Carter coin @ ", address(erc20));
    }

}