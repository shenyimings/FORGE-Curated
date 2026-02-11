// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { FraxOFTAdapterUpgradeable } from "contracts/FraxOFTAdapterUpgradeable.sol";

/**
 * @title FraxOFTAdapterUpgradeableStorageGap
 * @dev This contract adds storage gaps to maintain the storage layout of FraxOFTUpgradeable after it is upgraded to
    * FraxOFTAdapterUpgradeable.
 */
contract FraxOFTAdapterUpgradeableStorageGap is FraxOFTAdapterUpgradeable {

    uint256[50] private __gap;

    constructor(
        address _token,
        address _lzEndpoint
    ) FraxOFTAdapterUpgradeable(_token, _lzEndpoint) {}

}
