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

import { IManagerBase, NttManager } from "lib/sky-ntt-migration/evm/src/NttManager/NttManager.sol";

interface ChainlogLike {
    function getAddress(bytes32) external view returns (address);
}

library MigrationDeploy {
    ChainlogLike constant LOG = ChainlogLike(0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F);

    function deployMigration() internal returns (address nttManagerImpV2) {
        // constructor params chosen identical to NttManager Implementation V1 @ 0x37c618755832ef5ca44FA88BF1CCdCe46f30b479
        nttManagerImpV2 = address(new NttManager({ 
            _token: LOG.getAddress("USDS"),
            _mode: IManagerBase.Mode.LOCKING,
            _chainId: 2,
            _rateLimitDuration: 86400,
            _skipRateLimiting: false
        }));
    }
}
