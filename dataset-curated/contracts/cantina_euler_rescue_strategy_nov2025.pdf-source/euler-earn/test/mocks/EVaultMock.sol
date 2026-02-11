// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.26;

import "../../lib/euler-vault-kit/src/EVault/EVault.sol";
import {Assets, Owed} from "../../lib/euler-vault-kit/src/EVault/shared/types/Types.sol";

import "forge-std/console.sol";

contract EVaultMock is EVault {
    constructor(Integrations memory integrations, DeployedModules memory modules) EVault(integrations, modules) {}

    function mockSetTotalSupply(uint112 newValue) external {
        vaultStorage.totalBorrows = Owed.wrap(uint112(0));
        vaultStorage.cash = Assets.wrap(newValue);
    }
}
