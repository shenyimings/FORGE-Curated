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

interface ISAMMErrors {
    error SAMM__alreadyInitialized();
    error SAMM__safeIsZero();
    error SAMM__rootIsZero();
    error SAMM__thresholdIsZero();
    error SAMM__emptyRelayer();
    error SAMM__notEnoughProofs(uint256 amountOfGivenProofs, uint256 threshold);
    error SAMM__commitAlreadyUsed(uint256 usedCommitIndex);
    error SAMM__proofVerificationFailed(uint256 failedProofIndex);
    error SAMM__notSafe();
    error SAMM__deadlineIsPast();
    error SAMM__dkimRegistryIsZero();
    error SAMM__DKIMPublicKeyVerificationFailed(uint256 commitIndex);
    error SAMM__toIsWrong();
    error SAMM__noChanges();
    error SAMM__txIsNotAllowed();
    error SAMM__allowanceIsNotEnough();
    error SAMM__longRelayer();
}
