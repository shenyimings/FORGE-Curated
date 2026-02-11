// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {ShareMath} from "../src/lib/ShareMath.sol";
import {Vault} from "../src/lib/Vault.sol";

contract ShareMathTest is Test {
    using ShareMath for uint256;
    using ShareMath for Vault.StakeReceipt;

    function setUp() public {}

    function test_assetToSharesClean() public {
        // 100 tokens of asset, 10 tokens per share, 18 decimals -> should be 10 shares
        uint256 assetAmount = 100 * (10 ** 18);
        uint256 assetPerShare = 10 * (10 ** 18);
        uint256 decimals = 18;

        uint256 shares = assetAmount.assetToShares(assetPerShare, decimals);

        assertEq(shares, 10 * (10 ** 18));
    }

    function test_assetToSharesDirty() public {
        //83 tokens of asset, 2.3 tokens per share, 18 decimals -> should be 36086956521739130434 shares
        uint256 assetAmount = 83 * (10 ** 18);
        uint256 assetPerShare = 2.3 * (10 ** 18);
        uint256 decimals = 18;

        uint256 shares = assetAmount.assetToShares(assetPerShare, decimals);
        assertEq(shares, 36086956521739130434);
    }

    function test_sharesToAssetClean() public {
        // 10 shares, 10 tokens per share, 18 decimals -> should be 100 tokens
        uint256 shares = 10 * (10 ** 18);
        uint256 assetPerShare = 10 * (10 ** 18);
        uint256 decimals = 18;

        uint256 assetAmount = shares.sharesToAsset(assetPerShare, decimals);

        assertEq(assetAmount, 100 * (10 ** 18));
    }

    function test_sharesToAssetDirty() public {
        // 36086956521739130434 shares, 2.3 tokens per share, 18 decimals -> should be ~83 tokens
        uint256 shares = 36086956521739130434;
        uint256 assetPerShare = 2.3 * (10 ** 18);
        uint256 decimals = 18;

        uint256 assetAmount = shares.sharesToAsset(assetPerShare, decimals);

        assertEq(assetAmount, 82999999999999999998);
    }

    function test_getSharesFromReceiptNoUnredeemed() public {
        // 100 tokens of asset, 10 tokens per share, 18 decimals -> should be 10 shares
        uint256 assetAmount = 100 * (10 ** 18);
        uint256 assetPerShare = 10 * (10 ** 18);
        uint256 decimals = 18;

        Vault.StakeReceipt memory stakeReceipt = Vault.StakeReceipt({
            round: 1,
            amount: uint104(assetAmount),
            unredeemedShares: 0
        });

        uint256 shares = stakeReceipt.getSharesFromReceipt(
            2,
            assetPerShare,
            decimals
        );

        assertEq(shares, 10 * (10 ** 18));
    }

    function test_getSharesFromReceiptSameRound() public {
        uint256 assetAmount = 100 * (10 ** 18);
        uint256 assetPerShare = 10 * (10 ** 18);
        uint256 decimals = 18;

        Vault.StakeReceipt memory stakeReceipt = Vault.StakeReceipt({
            round: 1,
            amount: uint104(assetAmount),
            unredeemedShares: 0
        });

        // same round so should be zero shares
        uint256 shares = stakeReceipt.getSharesFromReceipt(
            1,
            assetPerShare,
            decimals
        );

        assertEq(shares, 0);
    }

    function test_getSharesFromReceiptClean() public {
        // 100 tokens of asset, 10 tokens per share, 18 decimals -> should be 10 shares
        uint256 assetAmount = 100 * (10 ** 18);
        uint256 assetPerShare = 10 * (10 ** 18);
        uint256 decimals = 18;

        Vault.StakeReceipt memory stakeReceipt = Vault.StakeReceipt({
            round: 1,
            amount: uint104(assetAmount),
            unredeemedShares: 40 * (10 ** 18)
        });

        uint256 shares = stakeReceipt.getSharesFromReceipt(
            2,
            assetPerShare,
            decimals
        );

        assertEq(shares, 10 * (10 ** 18) + 40 * (10 ** 18));
    }

    function test_getSharesFromReceiptDirty() public {
        // 83 tokens of asset, 2.3 tokens per share, 18 decimals -> should be 36086956521739130434 shares
        uint256 assetAmount = 83 * (10 ** 18);
        uint256 assetPerShare = 2.3 * (10 ** 18);
        uint256 decimals = 18;

        Vault.StakeReceipt memory stakeReceipt = Vault.StakeReceipt({
            round: 1,
            amount: uint104(assetAmount),
            unredeemedShares: 0
        });

        uint256 shares = stakeReceipt.getSharesFromReceipt(
            2,
            assetPerShare,
            decimals
        );

        assertEq(shares, 36086956521739130434);
    }
}
