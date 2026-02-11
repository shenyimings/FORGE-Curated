// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@arbitrum/nitro-contracts-1.2.1/src/bridge/IInbox.sol";
import "@arbitrum/nitro-contracts-1.2.1/src/bridge/ISequencerInbox.sol";

/// @dev Modified from
///      https://github.com/ArbitrumFoundation/governance/blob/ce6e0d8a9925b3815d38ba17621c4b775e8129c7/src/gov-action-contracts/sequencer/SetSequencerInboxMaxTimeVariationAction.sol
contract SetSequencerInboxMaxTimeVariationAction {
    uint256 public immutable delayBlocks;
    uint256 public immutable futureBlocks;
    uint256 public immutable delaySeconds;
    uint256 public immutable futureSeconds;

    constructor(uint256 _delayBlocks, uint256 _futureBlocks, uint256 _delaySeconds, uint256 _futureSeconds) {
        delayBlocks = _delayBlocks;
        futureBlocks = _futureBlocks;
        delaySeconds = _delaySeconds;
        futureSeconds = _futureSeconds;
    }

    function perform(IInbox inbox) external {
        ISequencerInbox sequencerInbox = ISequencerInbox(address(inbox.bridge().sequencerInbox()));
        sequencerInbox.setMaxTimeVariation(
            ISequencerInbox.MaxTimeVariation({
                delayBlocks: delayBlocks,
                futureBlocks: futureBlocks,
                delaySeconds: delaySeconds,
                futureSeconds: futureSeconds
            })
        );
    }
}
