// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {SetupStvStETHPool} from "./SetupStvStETHPool.sol";
import {Test} from "forge-std/Test.sol";
import {StvStETHPool} from "src/StvStETHPool.sol";

contract DepositAndMintTest is Test, SetupStvStETHPool {
    // Steth

    function test_DepositAndMintShares_DepositIncreasesStvBalance() public {
        uint256 balanceBefore = pool.balanceOf(address(this));
        pool.depositETHAndMintStethShares{value: 1 ether}(address(0), 0);
        uint256 balanceAfter = pool.balanceOf(address(this));

        assertGt(balanceAfter, balanceBefore, "stv balance increased");
    }

    function test_DepositAndMintShares_DepositWithMintingIncreasesWstethBalance() public {
        uint256 balanceBefore = steth.balanceOf(address(this));
        pool.depositETHAndMintStethShares{value: 2 ether}(address(0), 1e18);
        uint256 balanceAfter = steth.balanceOf(address(this));

        assertGt(balanceAfter, balanceBefore, "stETH balance increased");
    }

    function test_DepositAndMintShares_NoMintRequested() public {
        uint256 depositAmount = 3 ether;
        uint256 expectedStv = pool.previewDeposit(depositAmount);

        uint256 balanceBefore = pool.balanceOf(address(this));
        uint256 userSharesBefore = pool.mintedStethSharesOf(address(this));

        pool.depositETHAndMintStethShares{value: depositAmount}(address(0), 0);

        assertEq(pool.balanceOf(address(this)), balanceBefore + expectedStv, "stv minted");
        assertEq(pool.mintedStethSharesOf(address(this)), userSharesBefore, "no shares minted for user");
    }

    function test_DepositAndMintShares_Minting() public {
        uint256 depositAmount = 10 ether;
        uint256 expectedStv = pool.previewDeposit(depositAmount);
        uint256 maxMintable = pool.remainingMintingCapacitySharesOf(address(this), depositAmount);
        uint256 stethSharesToMint = maxMintable / 2;

        uint256 userSharesBefore = pool.mintedStethSharesOf(address(this));
        uint256 balanceBefore = pool.balanceOf(address(this));

        pool.depositETHAndMintStethShares{value: depositAmount}(address(0), stethSharesToMint);

        assertGt(stethSharesToMint, 0);
        assertEq(pool.balanceOf(address(this)), balanceBefore + expectedStv, "stv minted");
        assertEq(pool.mintedStethSharesOf(address(this)), userSharesBefore + stethSharesToMint, "user shares minted");
    }

    function test_DepositAndMintShares_RevertWhenInsufficientMintingCapacity() public {
        uint256 depositAmount = 5 ether;
        uint256 mintedStv = pool.previewDeposit(depositAmount);
        uint256 sharesToMint = pool.calcStethSharesToMintForStv(mintedStv) + 1;
        assertGt(sharesToMint, 0);

        vm.expectRevert(StvStETHPool.InsufficientMintingCapacity.selector);
        pool.depositETHAndMintStethShares{value: depositAmount}(address(0), sharesToMint);
    }

    function test_DepositAndMintShares_MintingForPreviousDepositedAssets() public {
        // 1. Deposit without minting
        uint256 firstDeposit = 5 ether;
        pool.depositETHAndMintStethShares{value: firstDeposit}(address(0), 0);

        // 2. Deposit again and mint steth up to total deposited assets in one tx
        // Should PASS for since all previously deposited assets are still unlocked
        uint256 secondDeposit = 7 ether;
        uint256 mintable = pool.remainingMintingCapacitySharesOf(address(this), secondDeposit);
        assertEq(
            mintable,
            pool.calcStethSharesToMintForAssets(5 ether + 7 ether),
            "mintable should match total deposited assets"
        );

        uint256 expectedStv = pool.previewDeposit(secondDeposit);
        uint256 balanceBefore = pool.balanceOf(address(this));

        pool.depositETHAndMintStethShares{value: secondDeposit}(address(0), mintable);

        assertEq(pool.balanceOf(address(this)), balanceBefore + expectedStv, "stv minted");
        assertEq(pool.mintedStethSharesOf(address(this)), mintable, "shares minted");

        uint256 remainingAfter = pool.remainingMintingCapacitySharesOf(address(this), 0);
        assertEq(remainingAfter, 0, "residual capacity too high");
    }

    // Wsteth

    function test_DepositAndMintWsteth_DepositIncreasesStvBalance() public {
        uint256 balanceBefore = pool.balanceOf(address(this));
        pool.depositETHAndMintWsteth{value: 1 ether}(address(0), 0);
        uint256 balanceAfter = pool.balanceOf(address(this));

        assertGt(balanceAfter, balanceBefore, "stv balance increased");
    }

    function test_DepositAndMintWsteth_DepositWithMintingIncreasesWstethBalance() public {
        uint256 balanceBefore = wsteth.balanceOf(address(this));
        pool.depositETHAndMintWsteth{value: 2 ether}(address(0), 1e18);
        uint256 balanceAfter = wsteth.balanceOf(address(this));

        assertGt(balanceAfter, balanceBefore, "wstETH balance increased");
    }

    function test_DepositAndMintWsteth_NoMintRequested() public {
        uint256 depositAmount = 2 ether;
        uint256 expectedStv = pool.previewDeposit(depositAmount);

        uint256 balanceBefore = pool.balanceOf(address(this));
        uint256 wstethBefore = wsteth.balanceOf(address(this));

        pool.depositETHAndMintWsteth{value: depositAmount}(address(0), 0);

        assertEq(pool.balanceOf(address(this)), balanceBefore + expectedStv, "stv minted");
        assertEq(wsteth.balanceOf(address(this)), wstethBefore, "no wstETH minted");
    }

    function test_DepositAndMintWsteth_Minting() public {
        uint256 depositAmount = 9 ether;
        uint256 expectedStv = pool.previewDeposit(depositAmount);
        uint256 maxMintable = pool.remainingMintingCapacitySharesOf(address(this), depositAmount);
        uint256 wstethToMint = maxMintable / 2;

        uint256 userSharesBefore = pool.mintedStethSharesOf(address(this));
        uint256 balanceBefore = pool.balanceOf(address(this));
        uint256 wstethBefore = wsteth.balanceOf(address(this));

        pool.depositETHAndMintWsteth{value: depositAmount}(address(0), wstethToMint);

        assertGt(wstethToMint, 0);
        assertEq(pool.balanceOf(address(this)), balanceBefore + expectedStv, "stv minted");
        assertEq(wsteth.balanceOf(address(this)), wstethBefore + wstethToMint, "wstETH minted");
        assertEq(pool.mintedStethSharesOf(address(this)), userSharesBefore + wstethToMint, "user shares minted");
    }

    function test_DepositAndMintWsteth_RevertWhenInsufficientMintingCapacity() public {
        uint256 depositAmount = 4 ether;
        uint256 mintedStv = pool.previewDeposit(depositAmount);
        uint256 wstethToMint = pool.calcStethSharesToMintForStv(mintedStv) + 1;
        assertGt(wstethToMint, 0);

        vm.expectRevert(StvStETHPool.InsufficientMintingCapacity.selector);
        pool.depositETHAndMintWsteth{value: depositAmount}(address(0), wstethToMint);
    }

    function test_DepositAndMintWsteth_MintingForPreviousDepositedAssets_PassForDirectDeposits() public {
        // 1. Deposit without minting
        uint256 firstDeposit = 5 ether;
        pool.depositETHAndMintWsteth{value: firstDeposit}(address(0), 0);

        // 2. Deposit again and mint wsteth up to total deposited assets in one tx
        // Should PASS for since all previously deposited assets are still unlocked
        uint256 secondDeposit = 7 ether;
        uint256 mintable = pool.remainingMintingCapacitySharesOf(address(this), secondDeposit);
        assertEq(
            mintable,
            pool.calcStethSharesToMintForAssets(5 ether + 7 ether),
            "mintable should match total deposited assets"
        );

        uint256 expectedStv = pool.previewDeposit(secondDeposit);
        uint256 balanceBefore = pool.balanceOf(address(this));

        pool.depositETHAndMintWsteth{value: secondDeposit}(address(0), mintable);

        assertEq(pool.balanceOf(address(this)), balanceBefore + expectedStv, "stv minted");
        assertEq(pool.mintedStethSharesOf(address(this)), mintable, "shares minted");

        uint256 remainingAfter = pool.remainingMintingCapacitySharesOf(address(this), 0);
        assertEq(remainingAfter, 0, "residual capacity too high");
    }
}
