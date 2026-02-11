// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2024 Fireblocks <support@fireblocks.com>
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
pragma solidity 0.8.20;

import { ERC2771Forwarder } from "@openzeppelin/contracts-v5/metatx/ERC2771Forwarder.sol";

/**
 * @title Trusted Forwarder
 * @author Fireblocks
 * @notice This contract is used to forward transactions to a contract that uses the ERC2771 context. It is used to
 * enable gasless transactions. This contract is based on the OpenZeppelin ERC2771Forwarder contract.
 */
contract TrustedForwarder is ERC2771Forwarder {
	/// functions

	/**
	 * @notice This function acts as the constructor of the contract.
	 * @param name The name of the contract.
	 */
	constructor(string memory name) ERC2771Forwarder(name) {}
}
