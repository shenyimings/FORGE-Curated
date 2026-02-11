// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.21;

import "forge-std/Script.sol";

import { ScriptTools } from "dss-test/ScriptTools.sol";

import { MigrationInstance, MigrationDeploy } from "deploy/MigrationDeploy.sol";
import { MockSpell } from "test/mocks/MockSpell.sol";

contract DeployScript is Script {

    using ScriptTools for string;

    address constant SKY_ORACLE = 0x9f7Ce792d0ee09a6ce89eC2B9B236A44B0aCf73e; // https://chroniclelabs.org/dashboard/oracle/SKY/USD?blockchain=ETH

    string ARTIFACTS_0_5_12_DIR = "0-5-12";

    function _get_code_0_5_12(string memory what) internal view returns (bytes memory code) {
        code = vm.getCode(string(abi.encodePacked(ARTIFACTS_0_5_12_DIR, "/", what)));
    }

    function run() external {

        vm.startBroadcast();

        (,address deployerAddress, ) = vm.readCallers();

        MigrationInstance memory migrationInstance = MigrationDeploy.deployMigration({
            deployer          : deployerAddress,
            maxYays           : 5,
            launchThreshold   : 80_000 * 10 ** 18 * 24_000,
            liftCooldown      : 10,
            osmCode           : _get_code_0_5_12("osm.sol:OSM"),
            oracle            : SKY_ORACLE,
            lockstakeIlk      : "LSEV2-A",
            lockstakeCalcSig  : bytes4(abi.encodeWithSignature("newLinearDecrease(address)"))
        });
        ScriptTools.exportContract("deployed", "chief", migrationInstance.chief);
        ScriptTools.exportContract("deployed", "voteDelegateFactory", migrationInstance.voteDelegateFactory);
        ScriptTools.exportContract("deployed", "mkrSky", migrationInstance.mkrSky);
        ScriptTools.exportContract("deployed", "skyOsm", migrationInstance.skyOsm);
        ScriptTools.exportContract("deployed", "lsskyUsdsFarm", migrationInstance.lsskyUsdsFarm);
        ScriptTools.exportContract("deployed", "lssky", migrationInstance.lockstakeInstance.lssky);
        ScriptTools.exportContract("deployed", "engine", migrationInstance.lockstakeInstance.engine);
        ScriptTools.exportContract("deployed", "clipper", migrationInstance.lockstakeInstance.clipper);
        ScriptTools.exportContract("deployed", "clipperCalc", migrationInstance.lockstakeInstance.clipperCalc);
        ScriptTools.exportContract("deployed", "migrator", migrationInstance.lockstakeInstance.migrator);

        MockSpell spell = new MockSpell({
            newChief_               : migrationInstance.chief,
            newVoteDelegateFactory_ : migrationInstance.voteDelegateFactory,
            newMkrSky_              : migrationInstance.mkrSky,
            skyOsm_                 : migrationInstance.skyOsm,
            lsskyUsdsFarm_          : migrationInstance.lsskyUsdsFarm,
            lockstakeInstance_      : migrationInstance.lockstakeInstance
        });
        ScriptTools.exportContract("deployed", "spell", address(spell));
    }
}
