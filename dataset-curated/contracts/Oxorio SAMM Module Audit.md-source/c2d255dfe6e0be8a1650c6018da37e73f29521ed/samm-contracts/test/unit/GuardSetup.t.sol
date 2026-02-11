// SPDX-License-Identifier: GPL-3
pragma solidity 0.8.23;

import {Test} from "forge-std/Test.sol";
import {IModuleGuard, ModuleGuard} from "../../src/ModuleGuard.sol";
import {IModuleGuardErrors} from "../../src/interfaces/IModuleGuardErrors.sol";
import {Setup} from "./Setup.sol";
import {IMinimalSafeModuleManager} from "../../src/Safe/interfaces/IMinimalSafeModuleManager.sol";
import {ISAMM} from "../../src/SAMM.sol";
import {ArrHelper} from "../helpers/ArrHelper.sol";

contract GuardTest is Test, Setup {
    function test_singletonSetupWillRevert() external {
        vm.expectRevert(IModuleGuardErrors.ModuleGuard__alreadyInitialized.selector);
        guardSingleton.setup(address(123));
    }

    // Simply check that setup was ok
    function test_safeIsInitializedCorrectly() external {
        assertEq(guard.getSafe(), address(safe), "GuardSetup failed! Safe address does not match the default one");
    }

    // TODO: module guards support is required in safe
    function test_safeIsSetCorrectly() external enableModuleForSafe(safe, sam) {
        setModuleGuard(address(safe), address(guard));
    }

    // TODO: module guards support is required in safe
    // function test_guardIsNotAllowedTx() external enableModuleForSafe(safe, sam) {
    //     setModuleGuard(address(safe), address(guard));
    //     // setTxAllowed(address(safe), address(guard), address(sam), address(sam), 0xe75235b8, true);
    //     ISAMM.Proof memory proof = defaultCorrectProof();

    //     (bool result) = sam.executeTransaction(
    //         address(sam), 0, DEFAULT_CALLDATA, IMinimalSafeModuleManager.Operation.Call, ArrHelper._proofArr(proof), DEFAULT_DEADLINE
    //     );

    //     assertTrue(result);
    // }

    function setModuleGuard(address safeContract, address module) internal {
        bytes memory cd = abi.encodeCall(IMinimalSafeModuleManager.setModuleGuard, (module));
        bool success = sendTxToSafe(
            safeContract, address(this), safeContract, 0, cd, IMinimalSafeModuleManager.Operation.Call, 1e5
        );
        assertTrue(success);
    }

    function setTxAllowed(
        address safeContract,
        address guardContract,
        address module,
        address to,
        bytes4 selector,
        bool isAllowed
    ) internal {
        bytes memory cd = abi.encodeCall(IModuleGuard.setTxAllowed, (module, to, selector, isAllowed));
        bool success = sendTxToSafe(
            safeContract, address(this), guardContract, 0, cd, IMinimalSafeModuleManager.Operation.Call, 1e5
        );
        assertTrue(success);
    }
}
