// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IGovernanceSettings} from "@flarenetwork/flare-periphery-contracts/flare/IGovernanceSettings.sol";
import {FtsoV2PriceStore} from "./FtsoV2PriceStore.sol";


contract FtsoV2PriceStoreProxy is ERC1967Proxy {
    constructor(
        address _implementationAddress,
        IGovernanceSettings _governanceSettings,
        address _initialGovernance,
        address _addressUpdater,
        uint64 _firstVotingRoundStartTs,
        uint8 _votingEpochDurationSeconds,
        uint8 _ftsoProtocolId
    )
        ERC1967Proxy(_implementationAddress,
            abi.encodeCall(FtsoV2PriceStore.initialize, (
                _governanceSettings, _initialGovernance, _addressUpdater,
                _firstVotingRoundStartTs, _votingEpochDurationSeconds, _ftsoProtocolId))
        )
    {
    }
}
