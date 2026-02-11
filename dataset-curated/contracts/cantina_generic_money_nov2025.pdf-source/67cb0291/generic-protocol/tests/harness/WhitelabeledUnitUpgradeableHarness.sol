// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { WhitelabeledUnitUpgradeable, IERC20 } from "../../src/unit/whitelabeled/WhitelabeledUnitUpgradeable.sol";

contract WhitelabeledUnitUpgradeableHarness is WhitelabeledUnitUpgradeable {
    function exposed_initializableStorageSlot() external pure returns (bytes32) {
        return _initializableStorageSlot();
    }

    function exposed_getInitializedVersion() external view returns (uint64) {
        return _getInitializedVersion();
    }

    function workaround_initialize(
        string memory name_,
        string memory symbol_,
        IERC20 unitToken_
    )
        external
        initializer
    {
        __WhitelabeledUnit_init(name_, symbol_, unitToken_);
    }
}
