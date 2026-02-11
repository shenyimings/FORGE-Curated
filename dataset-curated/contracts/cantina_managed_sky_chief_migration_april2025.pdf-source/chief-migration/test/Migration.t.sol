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

import "forge-std/Script.sol";
import "dss-test/DssTest.sol";

import { MigrationInstance, MigrationDeploy } from "deploy/MigrationDeploy.sol";
import { MockSpell } from "test/mocks/MockSpell.sol";
import { MockDssExecSpell } from "test/mocks/MockDssExecSpell.sol";
import { LockstakeInstance } from "lib/lockstake/deploy/LockstakeInstance.sol";
import { LockstakeEngine } from "lib/lockstake/src/LockstakeEngine.sol";
import { LockstakeMigrator } from "lib/lockstake/src/LockstakeMigrator.sol";
import { VoteDelegateFactory } from "lib/vote-delegate/src/VoteDelegateFactory.sol";
import { VoteDelegate } from "lib/vote-delegate/src/VoteDelegate.sol";
import { Chief } from "lib/chief/src/Chief.sol";
import { MkrSky } from "lib/sky/src/MkrSky.sol";
import { StakingRewards } from "lib/endgame-toolkit/src/synthetix/StakingRewards.sol";

interface ChainlogLike {
    function getAddress(bytes32) external view returns (address);
}

interface TokenLike {
    function balanceOf(address) external view returns (uint256);
    function approve(address, uint256) external;
}

interface VatLike {
    function sin(address) external view returns (uint256);
    function dai(address) external view returns (uint256);
    function urns(bytes32, address) external view returns (uint256, uint256);
}

interface VowLike {
    function Sin() external view returns (uint256);
    function Ash() external view returns (uint256);
    function bump() external view returns (uint256);
    function hump() external view returns (uint256);
    function sump() external view returns (uint256);
    function flap() external returns (uint256);
    function flop() external returns (uint256);
    function heal(uint256) external;
}

interface OracleLike {
    function kiss(address who) external;
}

interface SplitterLike {
    function farm() external view returns (address);
    function hop() external view returns (uint256);
    function burn() external view returns (uint256);
    function file(bytes32, uint256) external;
}

interface OsmLike {
    function src() external view returns (address);
    function read() external view returns (uint256);
    function poke() external;
    function kiss(address) external;
}

interface PauseProxyLike {
    function exec(address, bytes memory) external;
}

interface AuthedLike {
    function authority() external view returns (address);
}

interface OldMkrSkyLike {
    function mkrToSky(address, uint256) external;
    function skyToMkr(address, uint256) external;
}

interface FlapperLike {
    function pip() external view returns (address);
    function file(bytes32, uint256) external;
}

interface SpotterLike {
    function poke(bytes32) external;
    function file(bytes32, bytes32, uint256) external;
}

interface DogLike {
    function bark(bytes32, address, address) external returns (uint256);
}

interface ClipperLike {
    function kicks() external view returns (uint256);
}

interface EsmLike {
    function min() external view returns (uint256);
}
interface SpellLike {
    function schedule() external;
    function cast() external;
}

contract MigrationTest is DssTest, Script {
    using stdStorage for StdStorage;
    using stdJson for string;
    using ScriptTools for string;

    string dependencies;

    ChainlogLike constant public chainlog = ChainlogLike(0xdA0Ab1e0017DEbCd72Be8599041a2aa3bA7e740F);
    address constant public skyOracle = 0x9f7Ce792d0ee09a6ce89eC2B9B236A44B0aCf73e; // https://chroniclelabs.org/dashboard/oracle/SKY/USD?blockchain=ETH

    address public vow;
    address public splitterStopSpell;
    address public pause;
    address public pauseProxy;

    VatLike public vat;
    SplitterLike public splitter;
    FlapperLike public flapper;
    VoteDelegateFactory public voteDelegateFactory;
    SpotterLike public spotter;
    TokenLike public mkr;
    TokenLike public sky;
    TokenLike public usds;
    DogLike   public dog;
    EsmLike   public esm;
    MockSpell public spell;
    MigrationInstance public migrationInstance;

    string internal ARTIFACTS_0_5_12_DIR = "0-5-12";

    function _get_code_0_5_12(string memory what) internal view returns (bytes memory code) {
        code = vm.getCode(string(abi.encodePacked(ARTIFACTS_0_5_12_DIR, "/", what)));
    }

    // When true we deploy and simulate the spell as part of the test.
    // Otherwise we assume that was already done (which is suitable for a shared testnet/fork)
    bool DEPLOY_AND_CAST_IN_TEST;

    function setUp() public {
        DEPLOY_AND_CAST_IN_TEST = vm.envOr("DEPLOY_AND_CAST_IN_TEST", true);

        vm.createSelectFork(vm.envString("ETH_RPC_URL"));

        vat               = VatLike(chainlog.getAddress("MCD_VAT"));
        vow               = chainlog.getAddress("MCD_VOW");
        sky               = TokenLike(chainlog.getAddress("SKY"));
        usds              = TokenLike(chainlog.getAddress("USDS"));
        splitter          = SplitterLike(chainlog.getAddress("MCD_SPLIT"));
        splitterStopSpell = chainlog.getAddress("EMSP_SPLITTER_STOP");
        spotter           = SpotterLike(chainlog.getAddress("MCD_SPOT"));
        dog               = DogLike(chainlog.getAddress("MCD_DOG"));
        esm               = EsmLike(chainlog.getAddress("MCD_ESM"));
        flapper           = FlapperLike(chainlog.getAddress("MCD_FLAP"));
        pause             = chainlog.getAddress("MCD_PAUSE");
        pauseProxy        = chainlog.getAddress("MCD_PAUSE_PROXY");

        if (DEPLOY_AND_CAST_IN_TEST) {
            mkr = TokenLike(chainlog.getAddress("MCD_GOV"));

            migrationInstance = MigrationDeploy.deployMigration({
                deployer          : address(this),
                launchThreshold   : 80_000 * 10 ** 18 * 24_000,
                maxYays           : 5,
                liftCooldown      : 10,
                osmCode           : _get_code_0_5_12("osm.sol:OSM"),
                oracle            : skyOracle,
                lockstakeIlk      : "LSEV2-A",
                lockstakeCalcSig  : bytes4(abi.encodeWithSignature("newLinearDecrease(address)"))
            });

            spell = new MockSpell({
                newChief_               : migrationInstance.chief,
                newVoteDelegateFactory_ : migrationInstance.voteDelegateFactory,
                newMkrSky_              : migrationInstance.mkrSky,
                skyOsm_                 : migrationInstance.skyOsm,
                lsskyUsdsFarm_          : migrationInstance.lsskyUsdsFarm,
                lockstakeInstance_      : migrationInstance.lockstakeInstance
            });
        } else {
            mkr = TokenLike(chainlog.getAddress("MKR"));

            dependencies = ScriptTools.loadDependencies("deployed"); // loads from FOUNDRY_SCRIPT_DEPS
            migrationInstance = MigrationInstance({
                chief               : dependencies.readAddress(".chief"),
                voteDelegateFactory : dependencies.readAddress(".voteDelegateFactory"),
                mkrSky              : dependencies.readAddress(".mkrSky"),
                skyOsm              : dependencies.readAddress(".skyOsm"),
                lsskyUsdsFarm       : dependencies.readAddress(".lsskyUsdsFarm"),
                lockstakeInstance   : LockstakeInstance({
                    lssky       : dependencies.readAddress(".lssky"),
                    engine      : dependencies.readAddress(".engine"),
                    clipper     : dependencies.readAddress(".clipper"),
                    clipperCalc : dependencies.readAddress(".clipperCalc"),
                    migrator    : dependencies.readAddress(".migrator")
                })
            });
        }

        deal(address(mkr), address(this), 100_000 * 10**18);
        deal(address(sky), address(this), 100_000 * 24_000 * 10**18, true);

        stdstore.target(skyOracle).sig("wards(address)").with_key(address(this)).depth(0).checked_write(uint256(1));
        OracleLike(skyOracle).kiss(address(flapper));
        OracleLike(skyOracle).kiss(migrationInstance.skyOsm);
        stdstore.target(skyOracle).sig("wards(address)").with_key(address(this)).depth(0).checked_write(uint256(0));

        vm.warp(block.timestamp + 1 hours);
        OsmLike(migrationInstance.skyOsm).poke();
        vm.warp(block.timestamp + 1 hours);
        OsmLike(migrationInstance.skyOsm).poke();

        if (!DEPLOY_AND_CAST_IN_TEST) {
            // spell poking was already done before the OSM had a price, so need to poke for engine borrowing
            spotter.poke("LSEV2-A");
        }
    }

    function _execSpell() internal {
        vm.prank(pause); PauseProxyLike(pauseProxy).exec(address(spell), abi.encodeCall(MockSpell.execute, ()));
    }

    function _prepareFlapping() internal {
        vm.warp(block.timestamp + splitter.hop());

        // create additional surplus if needed
        if (vat.dai(vow) < vat.sin(vow) + VowLike(vow).bump() + VowLike(vow).hump()) {
            stdstore.target(address(vat)).sig("dai(address)").with_key(vow).depth(0).checked_write(
                vat.sin(vow) + VowLike(vow).bump() + VowLike(vow).hump()
            );
        }

        // heal if needed
        if (vat.sin(vow) > VowLike(vow).Sin() + VowLike(vow).Ash()) {
            VowLike(vow).heal(vat.sin(vow) - VowLike(vow).Sin() - VowLike(vow).Ash());
        }
    }

    function _prepareFlopping() internal {
        stdstore.target(address(vat)).sig("dai(address)").with_key(vow).depth(0).checked_write(uint256(0));
        stdstore.target(address(vat)).sig("sin(address)").with_key(vow).depth(0).checked_write(uint256(200_000 * 1e45));
        stdstore.target(vow).sig("Sin()").checked_write(uint256(0));
        stdstore.target(vow).sig("Ash()").checked_write(uint256(0));
    }

    function testChiefMigration() public {
        if (DEPLOY_AND_CAST_IN_TEST) {
            address oldChief = chainlog.getAddress("MCD_ADM");
            assertNotEq(oldChief, migrationInstance.chief);
            assertEq(AuthedLike(pause).authority(), oldChief);
            assertNotEq(Chief(oldChief).hat(), address(0));
            assertEq(Chief(oldChief).live(), 1);

            assertEq(AuthedLike(chainlog.getAddress("SPLITTER_MOM")).authority(), oldChief);
            assertEq(AuthedLike(chainlog.getAddress("OSM_MOM")).authority(), oldChief);
            assertEq(AuthedLike(chainlog.getAddress("CLIPPER_MOM")).authority(), oldChief);
            assertEq(AuthedLike(chainlog.getAddress("DIRECT_MOM")).authority(), oldChief);
            assertEq(AuthedLike(chainlog.getAddress("STARKNET_ESCROW_MOM")).authority(), oldChief);
            assertEq(AuthedLike(chainlog.getAddress("LINE_MOM")).authority(), oldChief);
            assertEq(AuthedLike(chainlog.getAddress("LITE_PSM_MOM")).authority(), oldChief);

            _execSpell();
        }

        address newChief = chainlog.getAddress("MCD_ADM");
        assertEq(newChief, migrationInstance.chief);
        assertEq(AuthedLike(pause).authority(), newChief);
        assertEq(Chief(newChief).hat(), address(0));
        assertEq(Chief(newChief).live(), 0);

        assertEq(AuthedLike(chainlog.getAddress("SPLITTER_MOM")).authority(), newChief);
        assertEq(AuthedLike(chainlog.getAddress("OSM_MOM")).authority(), newChief);
        assertEq(AuthedLike(chainlog.getAddress("CLIPPER_MOM")).authority(), newChief);
        assertEq(AuthedLike(chainlog.getAddress("DIRECT_MOM")).authority(), newChief);
        assertEq(AuthedLike(chainlog.getAddress("STARKNET_ESCROW_MOM")).authority(), newChief);
        assertEq(AuthedLike(chainlog.getAddress("LINE_MOM")).authority(), newChief);
        assertEq(AuthedLike(chainlog.getAddress("LITE_PSM_MOM")).authority(), newChief);

        sky.approve(address(newChief), 80_000 * 10 ** 18 * 24_000);
        Chief(newChief).lock(80_000 * 10 ** 18 * 24_000);

        address testSpell = address(new MockDssExecSpell());
        address[] memory slate = new address[](1);

        // Mom can't operate since chief is not live
        slate[0] = splitterStopSpell;
        Chief(newChief).vote(slate);
        Chief(newChief).lift(splitterStopSpell);
        vm.expectRevert("SplitterMom/not-authorized");
        SpellLike(splitterStopSpell).schedule();

        // Also test spell can't schedule since chief is not live
        slate[0] = testSpell;
        Chief(newChief).vote(slate);
        Chief(newChief).lift(testSpell);
        vm.expectRevert("ds-auth-unauthorized");
        SpellLike(testSpell).schedule();

        // Launch chief
        slate[0] = address(0);
        Chief(newChief).vote(slate);
        Chief(newChief).lift(address(0));
        Chief(newChief).launch();

        assertEq(Chief(newChief).live(), 1);

        // Mom can't operate since the calling spell is not the hat
        vm.expectRevert("SplitterMom/not-authorized");
        SpellLike(splitterStopSpell).schedule();

        // Also test spell can't schedule since not the hat
        vm.expectRevert("ds-auth-unauthorized");
        SpellLike(testSpell).schedule();

        // Vote in the mom-triggering-spell
        slate[0] = splitterStopSpell;
        Chief(newChief).vote(slate);
        Chief(newChief).lift(splitterStopSpell);

        // Mom can operate
        assertLe(splitter.hop(), type(uint256).max);
        SpellLike(splitterStopSpell).schedule();
        assertEq(splitter.hop(), type(uint256).max);

        // Vote in the test spell
        slate[0] = testSpell;
        Chief(newChief).vote(slate);
        Chief(newChief).lift(testSpell);

        // Test spell can schedule
        SpellLike(testSpell).schedule();

        // Test spell can't cast before gov delay has passed
        vm.expectRevert("ds-pause-premature-exec");
        SpellLike(testSpell).cast();

        // Test spell can cast after gov delay has passed
        vm.warp(MockDssExecSpell(testSpell).eta());
        SpellLike(testSpell).cast();
    }

    function testVoteDelegateFactory() public {
        if (DEPLOY_AND_CAST_IN_TEST) {
            address oldFactory = chainlog.getAddress("VOTE_DELEGATE_FACTORY");
            assertNotEq(oldFactory, migrationInstance.voteDelegateFactory);
            assertNotEq(chainlog.getAddress("VOTE_DELEGATE_FACTORY_LEGACY"), oldFactory);

            _execSpell();

            assertEq(chainlog.getAddress("VOTE_DELEGATE_FACTORY_LEGACY"), oldFactory);
        }

        address newChief = chainlog.getAddress("MCD_ADM");
        address newFactory = chainlog.getAddress("VOTE_DELEGATE_FACTORY");

        assertEq(newFactory, migrationInstance.voteDelegateFactory);

        address voter = address(123);
        vm.prank(voter); VoteDelegate voteDelegate = VoteDelegate(VoteDelegateFactory(newFactory).create());

        uint256 initialSKY = sky.balanceOf(newChief);

        address delegator = address(456);
        deal(address(sky), delegator, 10_000 ether);
        vm.prank(delegator); sky.approve(address(voteDelegate), type(uint256).max);

        vm.prank(delegator); voteDelegate.lock(10_000 ether);
        assertEq(sky.balanceOf(delegator), 0);
        assertEq(sky.balanceOf(newChief), initialSKY + 10_000 ether);
        assertEq(voteDelegate.stake(delegator), 10_000 ether);

        vm.prank(delegator); voteDelegate.free(10_000 ether); // note that we can free in the same block now
        assertEq(sky.balanceOf(delegator), 10_000 ether);
        assertEq(sky.balanceOf(newChief), initialSKY);
        assertEq(voteDelegate.stake(delegator), 0);
    }

    function testConverters() public {
        address oldMkrSky;
        if (DEPLOY_AND_CAST_IN_TEST) {
            oldMkrSky = chainlog.getAddress("MKR_SKY");
            vm.expectRevert("dss-chain-log/invalid-key");
            chainlog.getAddress("MKR_SKY_LEGACY");

            // before the migration old converter can swap both ways
            mkr.approve(oldMkrSky, 100 * 10**18);
            OldMkrSkyLike(oldMkrSky).mkrToSky(address(this), 100 * 10**18);
            sky.approve(oldMkrSky, 10);
            OldMkrSkyLike(oldMkrSky).skyToMkr(address(this), 10);

            _execSpell();
        } else {
            oldMkrSky = chainlog.getAddress("MKR_SKY_LEGACY");
        }

        address newMkrSky = chainlog.getAddress("MKR_SKY");
        assertEq(newMkrSky, migrationInstance.mkrSky);
        assertNotEq(oldMkrSky, newMkrSky);
        assertEq(chainlog.getAddress("MKR_SKY_LEGACY"), oldMkrSky); // does not revert

        // after the migration old converter can swap only mkr=>sky
        mkr.approve(oldMkrSky, 100 * 10**18);
        OldMkrSkyLike(oldMkrSky).mkrToSky(address(this), 100 * 10**18);
        sky.approve(oldMkrSky, 10);
        vm.expectRevert();
        OldMkrSkyLike(oldMkrSky).skyToMkr(address(this), 10);

        // after the migration new converter can swap mkr=>sky
        mkr.approve(newMkrSky, 100 * 10**18);
        MkrSky(newMkrSky).mkrToSky(address(this), 100 * 10**18);

        assertEq(MkrSky(newMkrSky).fee(), 0);
        assertEq(MkrSky(newMkrSky).take(), 0);
    }

    function testSplitToFlapper() public {
        if (DEPLOY_AND_CAST_IN_TEST) {
           address flapSkyOracle = chainlog.getAddress("FLAP_SKY_ORACLE");
           assertEq(flapper.pip(), flapSkyOracle);
           assertNotEq(flapSkyOracle, skyOracle);

           _execSpell();
        }

        _prepareFlapping();

        assertEq(flapper.pip(), skyOracle);
        assertEq(chainlog.getAddress("FLAP_SKY_ORACLE"), skyOracle);

        vm.prank(pauseProxy); splitter.file("burn", 1e18);
        VowLike(vow).flap();
    }

    function testOsm() public {
        if (DEPLOY_AND_CAST_IN_TEST) {
            vm.expectRevert("dss-chain-log/invalid-key"); // does not exist
            chainlog.getAddress("PIP_SKY");

            _execSpell();
        }

        address pipSky = chainlog.getAddress("PIP_SKY"); // does not revert
        assertEq(pipSky, migrationInstance.skyOsm);
        assertEq(OsmLike(pipSky).src(), skyOracle);

        vm.prank(pauseProxy); OsmLike(pipSky).kiss(address(this));
        assertGt(OsmLike(pipSky).read(), 0);
    }

    function testSplitToFarm() public {
        if (DEPLOY_AND_CAST_IN_TEST) {
            assertNotEq(splitter.farm(), migrationInstance.lsskyUsdsFarm);

            vm.expectRevert("dss-chain-log/invalid-key"); // does not exist
            chainlog.getAddress("REWARDS_LSMKR_USDS_LEGACY");

            address oldRewards = chainlog.getAddress("REWARDS_LSMKR_USDS");

            _execSpell();

            assertEq(chainlog.getAddress("REWARDS_LSMKR_USDS_LEGACY"), oldRewards);
            vm.expectRevert("dss-chain-log/invalid-key"); // does not exist
            chainlog.getAddress("REWARDS_LSMKR_USDS");
        }

        _prepareFlapping();

        address splitterFarm = splitter.farm();
        assertEq(splitterFarm, migrationInstance.lsskyUsdsFarm);
        assertEq(splitterFarm, chainlog.getAddress("REWARDS_LSSKY_USDS"));

        assertEq(StakingRewards(splitterFarm).rewardsDistribution(), address(splitter));
        assertEq(StakingRewards(splitterFarm).rewardsDuration(), 5 days);

        vm.prank(pauseProxy); splitter.file("burn", 0);
        VowLike(vow).flap();
    }

    function testLockstakeLockFree() public {
        if (DEPLOY_AND_CAST_IN_TEST) {
            _execSpell();
        }

        LockstakeEngine newEngine = LockstakeEngine(chainlog.getAddress("LOCKSTAKE_ENGINE"));
        VoteDelegateFactory newFactory = VoteDelegateFactory(chainlog.getAddress("VOTE_DELEGATE_FACTORY"));
        StakingRewards farm = StakingRewards(ChainlogLike(chainlog).getAddress("REWARDS_LSSKY_USDS"));

        address voter = address(123);
        vm.prank(voter); address voteDelegate = newFactory.create();

        newEngine.open(0);

        newEngine.selectVoteDelegate(address(this), 0, voteDelegate);
        newEngine.selectFarm(address(this), 0, address(farm), 0);

        sky.approve(address(newEngine), 1_000 * 24_000 * 10**18);
        newEngine.lock(address(this), 0, 1_000 * 24_000 * 10**18, 5);

        assertEq(newEngine.free(address(this), 0, address(this), 400 * 24_000 * 10**18), 400 * 24_000 * 10**18);
    }

    function testLockstakeDrawWipe() public {
        if (DEPLOY_AND_CAST_IN_TEST) {
            _execSpell();
        }

        LockstakeEngine newEngine = LockstakeEngine(chainlog.getAddress("LOCKSTAKE_ENGINE"));

        newEngine.open(0);
        sky.approve(address(newEngine), 1_000 * 24_000 * 10**18);
        newEngine.lock(address(this), 0, 1_000 * 24_000 * 10**18, 5);

        newEngine.draw(address(this), 0, address(this), 15_000 * 10**18);

        usds.approve(address(newEngine), 10_000 * 10**18);
        newEngine.wipe(address(this), 0, 10_000 * 10**18);
    }

    function testLockstakeGetReward() public {
        if (DEPLOY_AND_CAST_IN_TEST) {
            _execSpell();
        }

        _prepareFlapping();

        vm.prank(pauseProxy); splitter.file("burn", 0);
        VowLike(vow).flap();

        LockstakeEngine newEngine = LockstakeEngine(chainlog.getAddress("LOCKSTAKE_ENGINE"));
        StakingRewards farm = StakingRewards(ChainlogLike(chainlog).getAddress("REWARDS_LSSKY_USDS"));
        newEngine.open(0);

        newEngine.selectFarm(address(this), 0, address(farm), 0);

        sky.approve(address(newEngine), 1_000 * 24_000 * 10**18);
        newEngine.lock(address(this), 0, 1_000 * 24_000 * 10**18, 5);

        vm.warp(block.timestamp + 10 hours);

        uint256 usdsBefore = usds.balanceOf(address(123));
        newEngine.getReward(address(this), 0, address(farm), address(123));
        assertGt(usds.balanceOf(address(123)), usdsBefore);
    }

    function _urnSetUp() internal returns (address urn) {
        LockstakeEngine newEngine = LockstakeEngine(chainlog.getAddress("LOCKSTAKE_ENGINE"));
        VoteDelegateFactory newFactory = VoteDelegateFactory(chainlog.getAddress("VOTE_DELEGATE_FACTORY"));
        StakingRewards farm = StakingRewards(ChainlogLike(chainlog).getAddress("REWARDS_LSSKY_USDS"));

        address voter = address(123);
        vm.prank(voter); address voteDelegate = newFactory.create();

        urn = newEngine.open(0);
        newEngine.selectVoteDelegate(address(this), 0, voteDelegate);
        newEngine.selectFarm(address(this), 0, address(farm), 0);
        sky.approve(address(newEngine), 1_000 * 24_000 * 10**18);
        newEngine.lock(address(this), 0, 1_000 * 24_000 * 10**18, 5);
        newEngine.draw(address(this), 0, address(this), 500_000 * 10**18);
    }

    function _forceLiquidation(address urn) internal {
        ClipperLike clip = ClipperLike(ChainlogLike(chainlog).getAddress("LOCKSTAKE_CLIP"));
        LockstakeEngine newEngine = LockstakeEngine(chainlog.getAddress("LOCKSTAKE_ENGINE"));

        vm.prank(pauseProxy); spotter.file("LSEV2-A", "mat", 500 * 3 * 10**27); // make unsafe
        spotter.poke("LSEV2-A");

        assertEq(clip.kicks(), 0);
        assertEq(newEngine.urnAuctions(urn), 0);
        dog.bark("LSEV2-A", address(urn), address(this));
        assertEq(clip.kicks(), 1);
        assertEq(newEngine.urnAuctions(urn), 1);
    }

    function testLockstakeLiquidation() public {
        if (DEPLOY_AND_CAST_IN_TEST) {
            _execSpell();
        }

        address urn = _urnSetUp();
        _forceLiquidation(urn);
    }

    function testLockstakeMigration() public {
        LockstakeMigrator migrator = LockstakeMigrator(migrationInstance.lockstakeInstance.migrator);
        LockstakeEngine oldEngine = LockstakeEngine(address(migrator.oldEngine()));
        LockstakeEngine newEngine = LockstakeEngine(address(migrator.newEngine()));

        bytes32 oldIlk = oldEngine.ilk();
        address owner = 0xf65475e74C1Ed6d004d5240b06E3088724dFDA5d;
        address oldUrnAddr = oldEngine.ownerUrns(owner, 4); // has debt on block 22082132
        (, uint256 art) = vat.urns(oldIlk, oldUrnAddr);
        assertGt(art, 0);

        vm.startPrank(owner);
        newEngine.open(0);
        oldEngine.hope(owner, 4, address(migrator));
        newEngine.hope(owner, 0, address(migrator));
        vm.stopPrank();

        // we test the scenario where everything apart from the migrate call is done before the cast
        if (DEPLOY_AND_CAST_IN_TEST) {
            _execSpell();
        }

        vm.prank(owner); migrator.migrate(owner, 4, owner, 0, 5);
    }

    function testFlopsTurnedOff() public {
        if (DEPLOY_AND_CAST_IN_TEST) {
            _prepareFlopping();
            VowLike(vow).flop();

            _execSpell();
        }

        assertEq(VowLike(vow).sump(), type(uint256).max);

        _prepareFlopping();
        vm.expectRevert("Vow/insufficient-debt");
        VowLike(vow).flop();
    }

    function testEsmTurnedOff() public {
        if (DEPLOY_AND_CAST_IN_TEST) {
            assertLt(esm.min(), type(uint256).max);
            _execSpell();
        }
        assertEq(esm.min(), type(uint256).max);
    }

    function testGovChainlogActions() public {
        if (DEPLOY_AND_CAST_IN_TEST) {
            assertEq(chainlog.getAddress("MCD_GOV"), address(mkr));
            vm.expectRevert("dss-chain-log/invalid-key"); // does not exist
            chainlog.getAddress("MKR");

            chainlog.getAddress("MCD_GOV_ACTIONS"); // does not revert

            assertEq(chainlog.getAddress("GOV_GUARD"), AuthedLike(address(mkr)).authority());
            vm.expectRevert("dss-chain-log/invalid-key"); // does not exist
            chainlog.getAddress("MKR_GUARD");

            _execSpell();
        }

        assertEq(chainlog.getAddress("MCD_GOV"), address(sky));
        assertEq(chainlog.getAddress("MKR"), address(mkr));

        vm.expectRevert("dss-chain-log/invalid-key"); // does not exist
        chainlog.getAddress("MCD_GOV_ACTIONS");

        vm.expectRevert("dss-chain-log/invalid-key"); // does not exist
        chainlog.getAddress("GOV_GUARD");
        assertEq(chainlog.getAddress("MKR_GUARD"), AuthedLike(address(mkr)).authority());
    }
}
