// SPDX-License-Identifier: GPL-3
pragma solidity 0.8.23;

interface IModuleGuardGetters {
    function getSafe() external view returns (address safe);
}
