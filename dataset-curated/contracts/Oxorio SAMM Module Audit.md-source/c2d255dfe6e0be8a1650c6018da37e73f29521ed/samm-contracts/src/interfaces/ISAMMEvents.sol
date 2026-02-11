// SPDX-License-Identifier: GPL-3
/**
 *     Safe Anonymization Mail Module
 *     Copyright (C) 2024 OXORIO-FZCO
 *
 *     This program is free software: you can redistribute it and/or modify
 *     it under the terms of the GNU General Public License as published by
 *     the Free Software Foundation, either version 3 of the License, or
 *     (at your option) any later version.
 *
 *     This program is distributed in the hope that it will be useful,
 *     but WITHOUT ANY WARRANTY; without even the implied warranty of
 *     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *     GNU General Public License for more details.
 *
 *     You should have received a copy of the GNU General Public License
 *     along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */
pragma solidity 0.8.23;

interface ISAMMEvents {
    event Setup(
        address indexed initiator,
        address indexed safe,
        uint256 initialSetupRoot,
        uint64 threshold,
        string relayer,
        address dkimRegistry
    );
    event ThresholdIsChanged(uint64 threshold);
    event MembersRootIsChanged(uint256 newRoot);
    event DKIMRegistryIsChanged(address dkimRegistry);
    event RelayerIsChanged(string relayer);
    event AllowanceChanged(bytes32 indexed txId, uint256 amount);
    event TxAllowanceChanged(bytes32 indexed txId, uint256 amount, bool isAllowed);
}
