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

import { ScriptTools } from "dss-test/ScriptTools.sol";
import { Chief } from "lib/chief/src/Chief.sol";
import { VoteDelegateFactory } from "lib/vote-delegate/src/VoteDelegateFactory.sol";
import { SkyDeploy } from "lib/sky/deploy/SkyDeploy.sol";
import { LockstakeDeploy } from "lib/lockstake/deploy/LockstakeDeploy.sol";
import { StakingRewardsDeploy, StakingRewardsDeployParams } from "lib/endgame-toolkit/script/dependencies/StakingRewardsDeploy.sol";
import { MigrationInstance } from "deploy/MigrationInstance.sol";

interface ChainlogLike {
    function getAddress(bytes32) external view returns (address);
}

interface MkrSkyLike {
    function rate() external view returns (uint256);
}

library MigrationDeploy {
    ChainlogLike constant chainlog = ChainlogLike(0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F);

    function deployBytecode(bytes memory code, bytes memory args) internal returns (address addr) {
        bytes memory bytecode = abi.encodePacked(code, args);
        assembly { addr := create(0, add(bytecode, 0x20), mload(bytecode)) }
        require(addr != address(0), "MigrationDeploy/deployment-failed");
    }

    function deployMigration(
        address      deployer,
        uint256      maxYays,
        uint256      launchThreshold,
        uint256      liftCooldown,
        bytes memory osmCode, // passed as code (w/o ctr args) since built with an older compiler
        address      oracle,
        bytes32      lockstakeIlk,
        bytes4       lockstakeCalcSig
    ) internal returns (MigrationInstance memory inst) {
        inst.chief = address(new Chief({
            gov_             : chainlog.getAddress("SKY"),
            maxYays_         : maxYays,
            launchThreshold_ : launchThreshold,
            liftCooldown_    : liftCooldown
        }));

        inst.voteDelegateFactory = address(new VoteDelegateFactory({
            _chief   : inst.chief,
            _polling : VoteDelegateFactory(chainlog.getAddress("VOTE_DELEGATE_FACTORY")).polling()
        }));

        inst.mkrSky = SkyDeploy.deployMkrSky({
            deployer : deployer,
            owner    : chainlog.getAddress("MCD_PAUSE_PROXY"),
            mkr      : chainlog.getAddress("MCD_GOV"),
            sky      : chainlog.getAddress("SKY"),
            rate     : MkrSkyLike(chainlog.getAddress("MKR_SKY")).rate()
        });

        inst.skyOsm = deployBytecode(osmCode,  abi.encode(oracle));
        ScriptTools.switchOwner(inst.skyOsm, deployer, chainlog.getAddress("MCD_PAUSE_PROXY"));

        inst.lockstakeInstance = LockstakeDeploy.deployLockstake({
            deployer            : deployer,
            owner               : chainlog.getAddress("MCD_PAUSE_PROXY"),
            voteDelegateFactory : inst.voteDelegateFactory,
            ilk                 : lockstakeIlk,
            fee                 : 0,
            calcSig             : lockstakeCalcSig,
            mkrSky              : inst.mkrSky
        });

        inst.lsskyUsdsFarm = StakingRewardsDeploy.deploy(StakingRewardsDeployParams({
            owner        : chainlog.getAddress("MCD_PAUSE_PROXY"),
            stakingToken : inst.lockstakeInstance.lssky,
            rewardsToken : chainlog.getAddress("USDS")
        }));
    }
}
