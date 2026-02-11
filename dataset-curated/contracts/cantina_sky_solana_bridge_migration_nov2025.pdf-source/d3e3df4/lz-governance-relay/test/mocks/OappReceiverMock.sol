// SPDX-License-Identifier: AGPL-3.0-or-later

// Copyright (C) 2025 Dai Foundation
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

import { MessageOrigin } from "lib/sky-oapp-oft/contracts/interfaces/IGovernanceOAppReceiver.sol";

contract OappReceiverMock {
    MessageOrigin public messageOrigin;

    function setMessageOrigin(uint32 _eid, bytes32 _caller) external {
        messageOrigin = MessageOrigin({
            srcEid    : _eid,
            srcSender : _caller
        });
    }
}
