// SPDX-License-Identifier: GPL-3
pragma solidity 0.8.23;

interface IModuleGuardEvents {
    event Setup(address indexed initiator, address indexed safe);
    event AllowanceChanged(address indexed module, address indexed to, uint256 amount);
    event TxAllowanceChanged(address indexed module, address indexed to, bytes4 selector, bool isAllowed);
}
