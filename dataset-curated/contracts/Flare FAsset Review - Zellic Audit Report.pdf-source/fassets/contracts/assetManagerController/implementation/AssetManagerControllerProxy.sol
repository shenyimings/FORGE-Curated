// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IGovernanceSettings} from "@flarenetwork/flare-periphery-contracts/flare/IGovernanceSettings.sol";
import {AssetManagerController} from "./AssetManagerController.sol";


contract AssetManagerControllerProxy is ERC1967Proxy {
    constructor(
        address _implementationAddress,
        IGovernanceSettings _governanceSettings,
        address _initialGovernance,
        address _addressUpdater
    )
        ERC1967Proxy(_implementationAddress,
            abi.encodeCall(
                AssetManagerController.initialize,
                (_governanceSettings, _initialGovernance, _addressUpdater)
            )
        )
    {
    }
}
