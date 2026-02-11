// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { Test } from "forge-std/Test.sol";

import { tryGetAssetDecimals, IERC20, IERC20Metadata } from "../../../src/utils/tryGetAssetDecimals.sol";

contract TryGetAssetDecimalsTest is Test {
    address asset = makeAddr("asset");

    function testFuzz_shouldReturnDecimals(uint8 decimals) public {
        vm.mockCall(asset, abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(decimals));

        (bool ok, uint8 returnedDecimals) = tryGetAssetDecimals(IERC20(asset));
        assertTrue(ok);
        assertEq(returnedDecimals, decimals);
    }

    function test_shouldReturnFalse_whenDecimalsReverts() public {
        vm.mockCallRevert(asset, abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode("some err"));

        (bool ok, uint8 returnedDecimals) = tryGetAssetDecimals(IERC20(asset));
        assertFalse(ok);
        assertEq(returnedDecimals, 0);
    }

    function test_shouldReturnFalse_whenDecimalsReturnsTooFewBytes() public {
        vm.mockCall(asset, abi.encodeWithSelector(IERC20Metadata.decimals.selector), "");

        (bool ok, uint8 returnedDecimals) = tryGetAssetDecimals(IERC20(asset));
        assertFalse(ok);
        assertEq(returnedDecimals, 0);
    }

    function testFuzz_shouldReturnFalse_whenDecimalsTooBig(uint256 decimals) public {
        decimals = bound(decimals, uint256(type(uint8).max) + 1, type(uint256).max);
        vm.mockCall(asset, abi.encodeWithSelector(IERC20Metadata.decimals.selector), abi.encode(decimals));

        (bool ok, uint8 returnedDecimals) = tryGetAssetDecimals(IERC20(asset));
        assertFalse(ok);
        assertEq(returnedDecimals, 0);
    }
}
