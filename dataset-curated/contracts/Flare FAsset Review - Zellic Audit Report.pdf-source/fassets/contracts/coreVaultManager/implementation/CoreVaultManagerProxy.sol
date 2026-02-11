// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IGovernanceSettings} from "@flarenetwork/flare-periphery-contracts/flare/IGovernanceSettings.sol";
import {CoreVaultManager} from "./CoreVaultManager.sol";


contract CoreVaultManagerProxy is ERC1967Proxy {
    constructor(
        address _implementationAddress,
        IGovernanceSettings _governanceSettings,
        address _initialGovernance,
        address _addressUpdater,
        address _assetManager,
        bytes32 _chainId,
        string memory _custodianAddress,
        string memory _coreVaultAddress,
        uint256 _nextSequenceNumber
    )
        ERC1967Proxy(_implementationAddress,
            abi.encodeCall(
                CoreVaultManager.initialize,
                (_governanceSettings, _initialGovernance, _addressUpdater,
                _assetManager, _chainId, _custodianAddress, _coreVaultAddress, _nextSequenceNumber)
            )
        )
    {
    }
}
