// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import {EulerSwapTestBase, IEulerSwap} from "./EulerSwapTestBase.t.sol";
import {CtxLib} from "../src/libraries/CtxLib.sol";

contract CtxTest is EulerSwapTestBase {
    function setUp() public virtual override {
        super.setUp();
    }

    function test_staticCtxStorage() public pure {
        assertEq(CtxLib.CtxStorageLocation, keccak256("eulerSwap.storage"));
    }

    function test_staticParamSize() public view {
        IEulerSwap.Params memory params = getEulerSwapParams(1e18, 1e18, 1e18, 1e18, 0.4e18, 0.85e18, 0, 0, address(0));
        assertEq(abi.encode(params).length, 384);
    }
}
