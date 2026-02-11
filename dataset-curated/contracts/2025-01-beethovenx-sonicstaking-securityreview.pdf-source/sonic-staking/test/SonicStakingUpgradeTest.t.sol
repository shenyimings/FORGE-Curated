// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.27;

import {Test, console} from "forge-std/Test.sol";
import {DeploySonicStaking} from "script/DeploySonicStaking.sol";
import {SonicStaking} from "src/SonicStaking.sol";
import {SonicStakingUpgrade} from "src/mock/SonicStakingUpgrade.sol";
import {ISFC} from "src/interfaces/ISFC.sol";
import {ERC20} from "openzeppelin-contracts/token/ERC20/ERC20.sol";
import {SonicStakingTestSetup} from "./SonicStakingTestSetup.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {Options} from "openzeppelin-foundry-upgrades/Options.sol";

contract SonicStakingUpgradeTest is Test, SonicStakingTestSetup {
    function testContractUpgraded() public {
        // upgrade the proxy
        vm.startPrank(SONIC_STAKING_OWNER);
        Options memory opts;
        opts.referenceContract = "SonicStaking.sol:SonicStaking";
        Upgrades.upgradeProxy(address(sonicStaking), "SonicStakingUpgrade.sol:SonicStakingUpgrade", "", opts);
        SonicStakingUpgrade sonicStakingUpgrade = SonicStakingUpgrade(payable(address(sonicStaking)));
        vm.stopPrank();

        // run the added function on the contract
        assertEq(sonicStakingUpgrade.testUpgrade(), 1);
    }
}
