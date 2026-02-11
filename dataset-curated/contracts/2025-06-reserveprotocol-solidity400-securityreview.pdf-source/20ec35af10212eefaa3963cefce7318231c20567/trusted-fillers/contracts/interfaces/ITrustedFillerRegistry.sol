// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { IBaseTrustedFiller } from "./IBaseTrustedFiller.sol";

interface ITrustedFillerRegistry {
    error TrustedFillerRegistry__InvalidCaller();
    error TrustedFillerRegistry__InvalidRoleRegistry();
    error TrustedFillerRegistry__InvalidFiller();

    event TrustedFillerCreated(address creator, IBaseTrustedFiller filler);
    event TrustedFillerAdded(IBaseTrustedFiller filler);
    event TrustedFillerDeprecated(IBaseTrustedFiller filler);

    function addTrustedFiller(IBaseTrustedFiller _filler) external;

    function deprecateTrustedFiller(IBaseTrustedFiller _filler) external;

    function createTrustedFiller(
        address senderSource,
        address trustedFiller,
        bytes32 deploymentSalt
    ) external returns (IBaseTrustedFiller trustedFillerInstance);

    function isAllowed(address _filler) external view returns (bool);
}
