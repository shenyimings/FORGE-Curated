// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import {PoolBase} from "src/amm/base/PoolBase.sol";
import {TestModifiers} from "test/util/TestModifiers.sol";
import {TestConstants, TBCInputOption} from "test/util/TestConstants.sol";
/**
 * @title Test Common Foundry Setup Pure Abstract Functions
 */
abstract contract TestCommonSetupAbs is TestConstants, TestModifiers {
    function _deployFactory() internal virtual;
    function _getFactoryAddress() internal virtual returns (address);
    function _deployPool(address, address, uint16, uint256, TBCInputOption) internal virtual returns (PoolBase);
    function _getMaxXTokenSupply() internal virtual returns (uint);
}
