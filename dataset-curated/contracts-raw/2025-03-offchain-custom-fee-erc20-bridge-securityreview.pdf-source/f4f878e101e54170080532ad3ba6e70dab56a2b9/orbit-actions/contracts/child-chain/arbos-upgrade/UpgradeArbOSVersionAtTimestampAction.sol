// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.16;

import "@arbitrum/nitro-contracts-1.2.1/src/precompiles/ArbOwner.sol";

/// @dev    Modified from
///         https://github.com/ArbitrumFoundation/governance/blob/a5375eea133e1b88df2116ed510ab2e3c07293d3/src/gov-action-contracts/arbos-upgrade/UpgradeArbOSVersionAction.sol
contract UpgradeArbOSVersionAtTimestampAction {
    uint64 public immutable newArbOSVersion;
    uint64 public immutable upgradeTimestamp;

    constructor(uint64 _newArbOSVersion, uint64 _upgradeTimestamp) {
        newArbOSVersion = _newArbOSVersion;
        upgradeTimestamp = _upgradeTimestamp;
    }

    function perform() external {
        ArbOwner arbOwner = ArbOwner(0x0000000000000000000000000000000000000070);
        arbOwner.scheduleArbOSUpgrade({newVersion: newArbOSVersion, timestamp: upgradeTimestamp});
    }
}
