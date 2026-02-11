// SPDX-FileCopyrightText: © 2025 Dai Foundation <www.daifoundation.org>
// SPDX-License-Identifier: AGPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

pragma solidity ^0.8.22;

import { ScriptTools } from "dss-test/ScriptTools.sol";

import { L1GovernanceRelay } from "src/L1GovernanceRelay.sol";
import { L2GovernanceRelay } from "src/L2GovernanceRelay.sol";

library GovernanceRelayDeploy {

    function deployL1(
        address deployer,
        address owner
    ) internal returns (address payable l1GovernanceRelay) {
        l1GovernanceRelay = payable(address(new L1GovernanceRelay()));
        ScriptTools.switchOwner(l1GovernanceRelay, deployer, owner);
    }

    // We assume an L2 spell is not mandatory. Spell teams are assumed to review the deployment and do sanity checks.
    function deployL2(
        uint32 l1Eid,
        address l2Oapp,
        address l1GovernanceRelay
    ) internal returns (address l2GovernanceRelay) {
        l2GovernanceRelay = address(new L2GovernanceRelay(l1Eid, l2Oapp, l1GovernanceRelay));
    }
}
