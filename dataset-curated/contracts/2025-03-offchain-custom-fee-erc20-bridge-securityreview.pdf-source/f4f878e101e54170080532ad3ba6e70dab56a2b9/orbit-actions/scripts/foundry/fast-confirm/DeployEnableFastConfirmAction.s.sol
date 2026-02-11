// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import {DeploymentHelpersScript} from "../helper/DeploymentHelpers.s.sol";
import {EnableFastConfirmAction} from "../../../contracts/parent-chain/fast-confirm/EnableFastConfirmAction.sol";

/**
 * @title DeployEnableFastConfirmActionScript
 * @notice This script deploys action that's used to enable fast confirmation
 */
contract DeployEnableFastConfirmAction is DeploymentHelpersScript {
    address public immutable GNOSIS_SAFE_PROXY_FACTORY = 0xC22834581EbC8527d974F8a1c97E1bEA4EF910BC;
    address public immutable GNOSIS_SAFE_1_3_0 = 0xfb1bffC9d739B8D520DaF37dF666da4C687191EA;
    address public immutable GNOSIS_COMPATIBILITY_FALLBACK_HANDLER = 0x017062a1dE2FE6b99BE3d9d37841FeD19F573804;

    function run() public {
        vm.startBroadcast();

        // deploy action
        new EnableFastConfirmAction({
            gnosisSafeProxyFactory: GNOSIS_SAFE_PROXY_FACTORY,
            gnosisSafe1_3_0: GNOSIS_SAFE_1_3_0,
            gnosisCompatibilityFallbackHandler: GNOSIS_COMPATIBILITY_FALLBACK_HANDLER
        });

        vm.stopBroadcast();
    }
}
