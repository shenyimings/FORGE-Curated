// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./history/BlueprintV1.sol";

contract BlueprintV1 is Initializable, UUPSUpgradeable, OwnableUpgradeable, Blueprint {
    function initialize() public reinitializer(1) {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        VERSION = "1.0.0";
        factor = 10000;
        totalProposalRequest = 0;
        totalDeploymentRequest = 0;
    }

    // The _authorizeUpgrade function is required by the UUPSUpgradeable contract
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
