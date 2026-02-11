// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.26;

import {IAugustusRegistry} from "src/interfaces/periphery/IAugustusRegistry.sol";

/// @dev This implementation is copied from the original version implemented by Morpho
/// https://github.com/morpho-org/bundler3/blob/4887f33299ba6e60b54a51237b16e7392dceeb97/src/mocks/AugustusRegistryMock.sol
contract MockAugustusRegistry is IAugustusRegistry {
    mapping(address => bool) valids;

    function setValid(address account, bool isValid) external {
        valids[account] = isValid;
    }

    function isValidAugustus(address account) external view returns (bool) {
        return valids[account];
    }
}
