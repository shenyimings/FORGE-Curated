// SPDX-License-Identifier: GPL-3
pragma solidity 0.8.23;

interface IModuleGuardErrors {
    error ModuleGuard__alreadyInitialized();
    error ModuleGuard__txIsNotAllowed();
    error ModuleGuard__allowanceIsNotEnough();
    error ModuleGuard__safeIsZero();
    error ModuleGuard__notSafe();
    error ModuleGuard__toIsWrong();
    error ModuleGuard__moduleIsWrong();
    error ModuleGuard__noChanges();
}
