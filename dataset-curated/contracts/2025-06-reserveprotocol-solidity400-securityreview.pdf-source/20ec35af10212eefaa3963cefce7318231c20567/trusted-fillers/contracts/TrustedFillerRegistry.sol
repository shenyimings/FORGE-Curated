// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { Clones } from "@openzeppelin/contracts/proxy/Clones.sol";

import { IRoleRegistry } from "./interfaces/IRoleRegistry.sol";

import { ITrustedFillerRegistry } from "./interfaces/ITrustedFillerRegistry.sol";
import { IBaseTrustedFiller } from "./interfaces/IBaseTrustedFiller.sol";

/**
 * @title TrustedFillerRegistry
 * @author akshatmittal, julianmrodri, pmckelvy1, tbrent
 * @notice Registry for Trusted Fillers
 */
contract TrustedFillerRegistry is ITrustedFillerRegistry {
    IRoleRegistry public immutable roleRegistry;

    mapping(address filler => bool allowed) private trustedFillers;

    constructor(address _roleRegistry) {
        require(_roleRegistry != address(0), TrustedFillerRegistry__InvalidRoleRegistry());

        roleRegistry = IRoleRegistry(_roleRegistry);
    }

    function addTrustedFiller(IBaseTrustedFiller _filler) external {
        require(roleRegistry.isOwner(msg.sender), TrustedFillerRegistry__InvalidCaller());
        require(address(_filler) != address(0), TrustedFillerRegistry__InvalidFiller());

        trustedFillers[address(_filler)] = true;

        emit TrustedFillerAdded(_filler);
    }

    function deprecateTrustedFiller(IBaseTrustedFiller _filler) external {
        require(roleRegistry.isOwnerOrEmergencyCouncil(msg.sender), TrustedFillerRegistry__InvalidCaller());
        require(address(_filler) != address(0), TrustedFillerRegistry__InvalidFiller());

        trustedFillers[address(_filler)] = false;

        emit TrustedFillerDeprecated(_filler);
    }

    function createTrustedFiller(
        address senderSource,
        address trustedFiller,
        bytes32 deploymentSalt
    ) external returns (IBaseTrustedFiller trustedFillerInstance) {
        require(trustedFillers[trustedFiller], TrustedFillerRegistry__InvalidFiller());

        bytes32 protectedSalt = keccak256(abi.encodePacked(msg.sender, senderSource, deploymentSalt));

        trustedFillerInstance = IBaseTrustedFiller(Clones.cloneDeterministic(trustedFiller, protectedSalt));

        emit TrustedFillerCreated(msg.sender, trustedFillerInstance);
    }

    function isAllowed(address _filler) external view returns (bool) {
        return trustedFillers[_filler];
    }
}
