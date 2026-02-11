// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";

import { ITrustedFillerRegistry } from "../../contracts/interfaces/ITrustedFillerRegistry.sol";
import { IBaseTrustedFiller } from "../../contracts/interfaces/IBaseTrustedFiller.sol";

/**
 * @title MockFillerRegistry
 * @author akshatmittal, julianmrodri, pmckelvy1, tbrent
 * @notice Mock Registry for Trusted Fillers
 * @dev NOT FOR PRODUCTION USE
 */
contract MockFillerRegistry is ITrustedFillerRegistry {
    function addTrustedFiller(IBaseTrustedFiller _filler) external {}

    function deprecateTrustedFiller(IBaseTrustedFiller _filler) external {}

    function createTrustedFiller(
        address senderSource,
        address trustedFiller,
        bytes32 deploymentSalt
    ) external returns (IBaseTrustedFiller trustedFillerInstance) {
        trustedFillerInstance = IBaseTrustedFiller(
            Clones.cloneDeterministic(
                trustedFiller,
                keccak256(abi.encodePacked(msg.sender, senderSource, deploymentSalt))
            )
        );
    }

    function isAllowed(address) external pure returns (bool) {
        return true;
    }
}
