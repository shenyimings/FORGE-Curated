// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Governed} from "../implementation/Governed.sol";
import {IGovernanceSettings} from "@flarenetwork/flare-periphery-contracts/flare/IGovernanceSettings.sol";
import {GovernedBase} from "../implementation/GovernedBase.sol";

/**
 * @title Governed mock contract
 * @notice A contract to expose the Governed contract for unit testing.
 **/
contract GovernedMock is Governed {

    constructor(IGovernanceSettings _governanceSettings, address _initialGovernance)
        Governed(_governanceSettings, _initialGovernance)
    {
        /* empty block */
    }

    function initialize(IGovernanceSettings _governanceSettings, address _initialGovernance) public {
        GovernedBase.initialise(_governanceSettings, _initialGovernance);
    }
}
