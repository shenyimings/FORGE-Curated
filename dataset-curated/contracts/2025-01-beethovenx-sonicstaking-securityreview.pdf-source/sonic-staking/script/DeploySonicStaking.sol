// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import {SonicStaking} from "src/SonicStaking.sol";
import {ISFC} from "src/interfaces/ISFC.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {TimelockController} from "openzeppelin-contracts/governance/TimelockController.sol";

import "forge-std/Script.sol";

contract DeploySonicStaking is Script {
    function run(
        address sfcAddress,
        address treasuryAddress,
        address sonicStakingOwner,
        address sonicStakingAdmin,
        address sonicStakingOperator,
        address sonicStakingOperator2,
        address sonicStakingClaimor
    ) public returns (SonicStaking) {
        vm.startBroadcast();

        address sonicStakingAddress = Upgrades.deployUUPSProxy(
            "SonicStaking.sol:SonicStaking",
            abi.encodeCall(SonicStaking.initialize, (ISFC(sfcAddress), treasuryAddress))
        );
        SonicStaking sonicStaking = SonicStaking(payable(sonicStakingAddress));

        // grant initial roles
        sonicStaking.grantRole(sonicStaking.OPERATOR_ROLE(), sonicStakingOperator);
        sonicStaking.grantRole(sonicStaking.OPERATOR_ROLE(), sonicStakingOperator2);
        sonicStaking.grantRole(sonicStaking.CLAIM_ROLE(), sonicStakingClaimor);

        // Deploy owner timelock (three week delay) that becomes owner of sonicStaking and can upgrade the contract
        address[] memory ownerProposers = new address[](1);
        ownerProposers[0] = sonicStakingOwner;
        TimelockController ownerTimelock = new TimelockController(21 days, ownerProposers, ownerProposers, address(0));

        // Deploy admin timelock (1 day delay) that can administer the protocol and roles on the staking contract
        address[] memory adminProposers = new address[](1);
        adminProposers[0] = sonicStakingAdmin;
        TimelockController adminTimelock = new TimelockController(1 days, adminProposers, adminProposers, address(0));

        // setup sonicStaking access control
        sonicStaking.transferOwnership(address(ownerTimelock));
        sonicStaking.grantRole(sonicStaking.DEFAULT_ADMIN_ROLE(), address(adminTimelock));
        sonicStaking.renounceRole(sonicStaking.DEFAULT_ADMIN_ROLE(), msg.sender);

        // Since these are the first deposits, the rate will be 1.
        // We burn 3 ether worth of $stS, 1 ether to address 1, 2 and 3
        // This ensures that the supply will never return to 0, safeguarding the protocol from precision
        // errors at very small wei values.
        sonicStaking.deposit{value: 3 ether}();
        sonicStaking.transfer(address(1), 1 ether);
        sonicStaking.transfer(address(2), 1 ether);
        sonicStaking.transfer(address(3), 1 ether);

        vm.stopBroadcast();
        return sonicStaking;
    }
}
