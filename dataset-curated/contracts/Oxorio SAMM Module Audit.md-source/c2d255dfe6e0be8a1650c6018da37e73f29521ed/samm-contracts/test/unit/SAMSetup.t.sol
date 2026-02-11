// SPDX-License-Identifier: GPL-3
pragma solidity 0.8.23;

import {Setup, Test, SAMM} from "./Setup.sol";
import {ISAMMErrors, ISAMM} from "../../src/interfaces/ISAMM.sol";

contract SAMExecuteTxTest is Test, Setup {
    function test_singletonSetupWillRevert() external {
        vm.expectRevert(ISAMMErrors.SAMM__alreadyInitialized.selector);
        samSingleton.setup(
            address(1),
            DEFAULT_ROOT,
            DEFAULT_THRESHOLD,
            DEFAULT_RELAYER,
            address(dkimRegistry),
            new ISAMM.TxAllowance[](0)
        );
    }

    // Simply check that setup was ok
    function test_rootIsInitializedCorrectly() external {
        assertEq(sam.getMembersRoot(), DEFAULT_ROOT, "Setup failed! Root does not match the default one");
    }

    function test_impossibleToSetupMultiplyTimes() external {
        vm.expectRevert(ISAMMErrors.SAMM__alreadyInitialized.selector);
        sam.setup(
            address(1),
            DEFAULT_ROOT,
            DEFAULT_THRESHOLD,
            DEFAULT_RELAYER,
            address(dkimRegistry),
            new ISAMM.TxAllowance[](0)
        );
    }

    function test_setupWithZeroThresholdWillRevert() external {
        bytes memory initData = abi.encodeCall(
            SAMM.setup,
            (address(safe), DEFAULT_ROOT, 0, DEFAULT_RELAYER, address(dkimRegistry), new ISAMM.TxAllowance[](0))
        );
        vm.expectRevert(); // Since factory will revert with 0 data
        createSAM(initData, 12317);
    }

    function test_setupWithZeroRootWillRevert() external {
        bytes memory initData = abi.encodeCall(
            SAMM.setup,
            (address(safe), 0, DEFAULT_THRESHOLD, DEFAULT_RELAYER, address(dkimRegistry), new ISAMM.TxAllowance[](0))
        );
        vm.expectRevert(); // Since factory will revert with 0 data
        createSAM(initData, 12317);
    }

    function test_setupWithZeroSafeWillRevert() external {
        bytes memory initData = abi.encodeCall(
            SAMM.setup,
            (
                address(0),
                DEFAULT_ROOT,
                DEFAULT_THRESHOLD,
                DEFAULT_RELAYER,
                address(dkimRegistry),
                new ISAMM.TxAllowance[](0)
            )
        );
        vm.expectRevert(); // Since factory will revert with 0 data
        createSAM(initData, 12317);
    }
}
