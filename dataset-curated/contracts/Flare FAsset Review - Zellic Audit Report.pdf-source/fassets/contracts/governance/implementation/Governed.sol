// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { GovernedBase } from "./GovernedBase.sol";
import { IGovernanceSettings } from "@flarenetwork/flare-periphery-contracts/flare/IGovernanceSettings.sol";


/**
 * @title Governed
 * @dev For deployed, governed contracts, enforce non-zero addresses at create time.
 **/
abstract contract Governed is GovernedBase {
    constructor(IGovernanceSettings _governanceSettings, address _initialGovernance) {
        initialise(_governanceSettings, _initialGovernance);
    }
}
