// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.22;

import { BoringVault } from "./../../src/base/BoringVault.sol";
import { EthPerWstEthRateProvider } from "./../../src/oracles/EthPerWstEthRateProvider.sol";
import { ETH_PER_STETH_CHAINLINK, WSTETH_ADDRESS } from "@ion-protocol/Constants.sol";
import { IonPoolSharedSetup } from "./IonPoolSharedSetup.sol";
import { ERC20 } from "@solmate/tokens/ERC20.sol";
import { FixedPointMathLib } from "@solmate/utils/FixedPointMathLib.sol";

import { console2 } from "forge-std/console2.sol";

contract IonPoolTellerTest is IonPoolSharedSetup {
    using FixedPointMathLib for uint256;

    EthPerWstEthRateProvider ethPerWstEthRateProvider;

    function setUp() public override {
        super.setUp();

        WETH.approve(address(boringVault), type(uint256).max);
        WSTETH.approve(address(boringVault), type(uint256).max);
        EETH.approve(address(boringVault), type(uint256).max);
        USDC.approve(address(boringVault), type(uint256).max);
        WEETH.approve(address(boringVault), type(uint256).max);

        vm.startPrank(TELLER_OWNER);
        teller.addAsset(WETH);
        teller.addAsset(WSTETH);
        teller.addAsset(EETH);
        teller.addAsset(USDC);
        teller.addAsset(WEETH);
        teller.setDepositCap(type(uint256).max);
        vm.stopPrank();

        // Setup accountant

        ethPerWstEthRateProvider =
            new EthPerWstEthRateProvider(address(ETH_PER_STETH_CHAINLINK), address(WSTETH_ADDRESS), 1 days);
        bool isPeggedToBase = false;

        vm.prank(ACCOUNTANT_OWNER);
        accountant.setRateProviderData(
            ERC20(address(WSTETH_ADDRESS)), isPeggedToBase, address(ethPerWstEthRateProvider)
        );

        // Add rate provider data for other assets
        vm.startPrank(ACCOUNTANT_OWNER);

        // EETH - pegged to base (1:1 with WETH)
        accountant.setRateProviderData(
            EETH,
            true, // isPeggedToBase = true
            address(0) // No rate provider needed for pegged assets
        );

        // USDC - assuming pegged to base for testing (or provide actual rate provider)
        accountant.setRateProviderData(
            USDC,
            true, // isPeggedToBase = true (treating as 1:1 for test)
            address(0) // No rate provider needed
        );

        // WEETH - non-pegged, needs rate provider
        // You need to either deploy a WEETH rate provider or import existing one
        accountant.setRateProviderData(
            WEETH,
            false, // isPeggedToBase = false
            address(WEETH_RATE_PROVIDER) // Use the actual WEETH rate provider from IonPoolSharedSetup
        );

        vm.stopPrank();
    }

    function test_Deposit_BaseAsset() public {
        uint256 depositAmt = 100 ether;
        uint256 minimumMint = 100 ether;

        // base / deposit asset
        uint256 exchangeRate = accountant.getRateInQuoteSafe(WETH);

        uint256 shares = depositAmt.mulDivDown(1e18, exchangeRate);

        // mint amount = deposit amount * exchangeRate
        deal(address(WETH), address(this), depositAmt);
        teller.deposit(WETH, depositAmt, minimumMint);

        assertEq(exchangeRate, 1e18, "base asset exchange rate must be pegged");
        assertEq(boringVault.balanceOf(address(this)), shares, "shares minted");
        assertEq(WETH.balanceOf(address(this)), 0, "WSTETH transferred from user");
        assertEq(WETH.balanceOf(address(boringVault)), depositAmt, "WSTETH transferred to vault");
    }

    function test_Deposit_NewAsset() public {
        uint256 depositAmt = 100 ether;
        uint256 minimumMint = 100 ether;

        // Calculate expected shares using the NEW precise method
        uint256 assetRate = ethPerWstEthRateProvider.getRate(); // 1168351507043552686
        uint256 expectedShares = depositAmt.mulDivDown(assetRate, 1e18); // 116835150704355268600

        deal(address(WSTETH), address(this), depositAmt);
        teller.deposit(WSTETH, depositAmt, minimumMint);

        assertEq(boringVault.balanceOf(address(this)), expectedShares, "shares minted");
        assertEq(WSTETH.balanceOf(address(this)), 0, "WSTETH transferred from user");
        assertEq(WSTETH.balanceOf(address(boringVault)), depositAmt, "WSTETH transferred to vault");
    }
}
