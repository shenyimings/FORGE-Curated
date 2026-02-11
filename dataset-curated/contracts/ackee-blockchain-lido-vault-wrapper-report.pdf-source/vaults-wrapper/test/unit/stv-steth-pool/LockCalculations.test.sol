// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Test} from "forge-std/Test.sol";

import {SetupStvStETHPool} from "./SetupStvStETHPool.sol";

contract LockCalculationsTest is Test, SetupStvStETHPool {
    function setUp() public override {
        super.setUp();
        pool.depositETH{value: 10 ether}(address(this), address(0));
    }

    function test_CalcAssetsToLockForStethShares_Zero() public view {
        assertEq(pool.calcAssetsToLockForStethShares(0), 0);
    }

    function test_CalcStvToLockForStethShares_Zero() public view {
        assertEq(pool.calcStvToLockForStethShares(0), 0);
    }

    function test_CalcStethSharesToMintForStv_Zero() public view {
        assertEq(pool.calcStethSharesToMintForStv(0), 0);
    }

    function test_CalcStethSharesToMintForAssets_Zero() public view {
        assertEq(pool.calcStethSharesToMintForAssets(0), 0);
    }

    function test_CalcAssetsToLockForStethShares_Calculation() public view {
        uint256 shares = 1e18;

        uint256 steth = steth.getPooledEthBySharesRoundUp(shares); // rounds up
        uint256 expectedAssets = Math.mulDiv(
            steth,
            pool.TOTAL_BASIS_POINTS(),
            pool.TOTAL_BASIS_POINTS() - pool.poolReserveRatioBP(),
            Math.Rounding.Ceil // rounds up
        );

        assertEq(pool.calcAssetsToLockForStethShares(shares), expectedAssets);
    }

    function test_CalcStvToLockForStethShares_Calculation() public view {
        uint256 shares = 1e18;

        uint256 steth = steth.getPooledEthBySharesRoundUp(shares); // rounds up
        uint256 expectedAssets = Math.mulDiv(
            steth,
            pool.TOTAL_BASIS_POINTS(),
            pool.TOTAL_BASIS_POINTS() - pool.poolReserveRatioBP(),
            Math.Rounding.Ceil // rounds up
        );
        uint256 expectedStv = Math.mulDiv(
            expectedAssets,
            pool.totalSupply(),
            pool.totalAssets(),
            Math.Rounding.Ceil // rounds up
        );

        assertEq(pool.calcStvToLockForStethShares(shares), expectedStv);
    }

    function test_CalcStethSharesToMintForStv_Calculation() public view {
        uint256 stv = 1e27;

        uint256 assets = Math.mulDiv(stv, pool.totalAssets(), pool.totalSupply(), Math.Rounding.Floor);
        uint256 maxStethToMint = Math.mulDiv(
            assets,
            pool.TOTAL_BASIS_POINTS() - pool.poolReserveRatioBP(),
            pool.TOTAL_BASIS_POINTS(),
            Math.Rounding.Floor // rounds down
        );
        uint256 expectedStethShares = steth.getSharesByPooledEth(maxStethToMint); // rounds down

        assertEq(pool.calcStethSharesToMintForStv(stv), expectedStethShares);
    }

    function test_CalcStethSharesToMintForAssets_Calculation() public view {
        uint256 assets = 1e18;

        uint256 maxStethToMint = Math.mulDiv(
            assets,
            pool.TOTAL_BASIS_POINTS() - pool.poolReserveRatioBP(),
            pool.TOTAL_BASIS_POINTS(),
            Math.Rounding.Floor // rounds down
        );
        uint256 expectedStethShares = steth.getSharesByPooledEth(maxStethToMint); // rounds down

        assertEq(pool.calcStethSharesToMintForAssets(assets), expectedStethShares);
    }
}
