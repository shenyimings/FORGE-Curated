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

pragma solidity ^0.8.21;

import { MCD, DssInstance } from "dss-test/MCD.sol";
import { MigrationInstance, MigrationConfig, MigrationInit } from "deploy/MigrationInit.sol";
import { LockstakeInstance } from "lib/lockstake/deploy/LockstakeInstance.sol";
import { LockstakeConfig } from "lib/lockstake/deploy/LockstakeInit.sol";

// Note: this contract is just for testnet deployments or local testing.
// In production initMigration will be called directly from the real spell.
contract MockSpell {

    address immutable public newChief;
    address immutable public newVoteDelegateFactory;
    address immutable public newMkrSky;
    address immutable public skyOsm;
    address immutable public lsskyUsdsFarm;

    // LockstakeInstance
    address immutable public lssky;
    address immutable public engine;
    address immutable public clipper;
    address immutable public clipperCalc;
    address immutable public migrator;

    address constant public LOG = 0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F;
    uint256 constant public WAD = 10**18;

    constructor(
        address newChief_,
        address newVoteDelegateFactory_,
        address newMkrSky_,
        address skyOsm_,
        address lsskyUsdsFarm_,
        LockstakeInstance memory lockstakeInstance_
    ) {
        newChief               = newChief_;
        newVoteDelegateFactory = newVoteDelegateFactory_;
        newMkrSky              = newMkrSky_;
        skyOsm                 = skyOsm_;
        lsskyUsdsFarm          = lsskyUsdsFarm_;

        lssky       = lockstakeInstance_.lssky;
        engine      = lockstakeInstance_.engine;
        clipper     = lockstakeInstance_.clipper;
        clipperCalc = lockstakeInstance_.clipperCalc;
        migrator    = lockstakeInstance_.migrator;
    }

    function execute() external {
        DssInstance memory dss = MCD.loadFromChainlog(LOG);

        address[] memory farms = new address[](1);
        farms[0] = lsskyUsdsFarm;

        MigrationInit.initMigration(
            dss,
            MigrationInstance({
                chief               : newChief,
                voteDelegateFactory : newVoteDelegateFactory,
                mkrSky              : newMkrSky,
                skyOsm              : skyOsm,
                lsskyUsdsFarm       : lsskyUsdsFarm,
                lockstakeInstance   : LockstakeInstance({
                    lssky       : lssky,
                    engine      : engine,
                    clipper     : clipper,
                    clipperCalc : clipperCalc,
                    migrator    : migrator
                })
            }),
            MigrationConfig({ // Note: values are just for testing
                maxYays: 5,
                launchThreshold: 80_000 * 10**18 * 24_000,
                liftCooldown: 10,
                skyOracle: 0x9f7Ce792d0ee09a6ce89eC2B9B236A44B0aCf73e,
                rewardsDuration: 5 days,
                lockstakeConfig: LockstakeConfig({
                    ilk : "LSEV2-A",
                    farms: farms,
                    fee: 0,
                    maxLine: 50_000_000 * 10**45,
                    gap: 50_000_000 * 10**45,
                    ttl: 1 days,
                    dust: 50,
                    duty: 100000001 * 10**27 / 100000000,
                    mat: 1.25 * 10**27,
                    buf: 1.25 * 10**27, // 25% Initial price buffer
                    tail: 3600, // 1 hour before reset
                    cusp: 0.2 * 10**27, // 80% drop before reset
                    chip: 2 * WAD / 100,
                    tip: 3,
                    stopped: 0,
                    chop: 1 ether,
                    hole: 10_000 * 10**45,
                    tau: 100,
                    cut: 0,
                    step: 0,
                    lineMom: true,
                    tolerance: 0.5 * 10**27,
                    name: "LOCKSTAKE",
                    symbol: "LSSKY"
                })
            })
        );
    }
}
