// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Steakhouse Financial
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";

import {Box} from "../src/Box.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IOracle} from "../src/interfaces/IOracle.sol";
import {ISwapper} from "../src/interfaces/ISwapper.sol";
import {BoxLib} from "../src/periphery/BoxLib.sol";
import {ErrorsLib} from "../src/libraries/ErrorsLib.sol";

import {IFunding} from "../src/interfaces/IFunding.sol";
import {FundingAave, IPool} from "../src/FundingAave.sol";
import {FlashLoanAave, IPoolAddressesProviderAave} from "../src/periphery/FlashLoanAave.sol";
import {IBox} from "../src/interfaces/IBox.sol";
import "./mocks/MockSwapper.sol";
import "./mocks/MockOracle.sol";
import "../src/libraries/Constants.sol";

/// @notice Minimal Aave v3 Addresses Provider to obtain the Pool
interface IPoolAddressesProvider {
    function getPool() external view returns (address);
}

/**
 * @title Testing suite for leverage features of Box using Aave on Mainnet
 */
contract BoxLeverageAaveMainnetTest is Test {
    using BoxLib for Box;

    address owner = address(0x1);
    address curator = address(0x2);
    address guardian = address(0x3);
    address allocator = address(0x4);
    address user = address(0x5);

    // Mainnet addresses
    address constant PROVIDER = 0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e; // Aave v3 PoolAddressesProvider (Mainnet)
    IERC20 usdc = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48); // Mainnet USDC
    IERC20 ptSusde25Sep = IERC20(0x9F56094C450763769BA0EA9Fe2876070c0fD5F77); // PT-sUSDe-25SEP2025
    IERC20 usde = IERC20(0x4c9EDD5852cd905f086C759E8383e09bff1E68B3); // USDe
    IOracle ptSusdeOracle = IOracle(0x5139aa359F7F7FdE869305e8C7AD001B28E1C99a); // Oracle for PT-sUSDe-25SEP2025

    ISwapper swapper = ISwapper(0x5C9dA86ECF5B35C8BF700a31a51d8a63fA53d1f6); // Same swapper as Base

    IPool pool;

    function setUp() public {
        // Fork mainnet from specific block
        uint256 forkId = vm.createFork(vm.rpcUrl("mainnet"), 23294087);
        vm.selectFork(forkId);

        // Get Aave pool
        pool = IPool(IPoolAddressesProvider(PROVIDER).getPool());
    }

    function testBorrowUSDCAgainstPTsUSDe() public {
        // Deploy Box for USDC
        Box box = new Box(address(usdc), owner, curator, "Box USDC", "BOX_USDC", 0.01 ether, 7 days, 10 days, MAX_SHUTDOWN_WARMUP);

        // Configure Box
        vm.startPrank(curator);
        box.setGuardianInstant(guardian);
        box.addTokenInstant(ptSusde25Sep, ptSusdeOracle);
        box.setIsAllocator(allocator, true);
        box.addFeederInstant(address(this));

        // Use e-mode 17 for borrowing stablecoins (including USDC)
        uint8 eModeCategory = 17;
        FundingAave fundingModule = new FundingAave(address(box), pool, eModeCategory);
        bytes memory facilityData = "";
        box.addFundingInstant(fundingModule);
        box.addFundingFacilityInstant(fundingModule, facilityData);
        box.addFundingCollateralInstant(fundingModule, ptSusde25Sep);
        box.addFundingDebtInstant(fundingModule, usdc);
        vm.stopPrank();

        // Supply 1000 PT tokens
        uint256 ptAmount = 1000 ether;
        deal(address(ptSusde25Sep), address(box), ptAmount);

        // Fund Box with initial USDC
        deal(address(usdc), address(this), 1000e6);
        usdc.approve(address(box), 1000e6);
        box.deposit(1000e6, address(this));

        vm.startPrank(allocator);

        // Supply PT as collateral
        box.pledge(fundingModule, facilityData, ptSusde25Sep, ptAmount);
        console2.log("Supplied", ptAmount / 1e18, "PT-sUSDe as collateral");

        // Borrow at 80% LTV
        (uint256 totalCollateral, , , , , ) = pool.getUserAccountData(address(fundingModule));
        uint256 targetBorrowAmount = (totalCollateral * 80) / 100 / 100;
        uint256 navBefore = box.totalAssets();
        console2.log("NAV before borrow:", navBefore / 1e6, "USDC");

        box.borrow(fundingModule, facilityData, usdc, targetBorrowAmount);
        console2.log("Borrowed", targetBorrowAmount / 1e6, "USDC at 80% LTV");

        // Verify e-mode and LTV
        assertEq(pool.getUserEMode(address(fundingModule)), eModeCategory, "E-mode not set correctly");

        uint256 finalLTV = fundingModule.ltv(facilityData);
        uint256 navAfter = box.totalAssets();
        console2.log("NAV after borrow:", navAfter / 1e6, "USDC");
        console2.log("Final LTV:", (finalLTV * 100) / 1e18, "%, E-mode:", pool.getUserEMode(address(fundingModule)));

        // Verify NAV stability
        assertApproxEqRel(navAfter, navBefore, 0.001e18, "NAV should remain constant");

        // Verify e-mode enabled higher LTV than standard mode
        assertGt(finalLTV, 0.7e18, "E-mode should enable >70% LTV");

        // Clean up
        deal(address(usdc), address(box), usdc.balanceOf(address(box)) + targetBorrowAmount + 100e6);
        box.repay(fundingModule, facilityData, usdc, type(uint256).max);
        box.depledge(fundingModule, facilityData, ptSusde25Sep, ptAmount);
        vm.stopPrank();
    }

    function testBorrowUSDeAgainstPTsUSDe() public {
        // Deploy Box for USDe
        Box box = new Box(address(usde), owner, curator, "Box USDe", "BOX_USDe", 0.01 ether, 7 days, 10 days, MAX_SHUTDOWN_WARMUP);

        // Configure Box
        vm.startPrank(curator);
        box.setGuardianInstant(guardian);
        // Create properly scaled oracle for USDe base asset
        // ptSusdeOracle is for USDC (6 decimals), we need it for USDe (18 decimals)
        // Scale factor = 10^(target_decimals - source_decimals) = 10^(36+18-18 - (36+6-18)) = 10^12
        uint256 originalPrice = ptSusdeOracle.price();
        uint256 scaledPrice = originalPrice * 1e12;
        MockOracle ptSusdeUSDe_Oracle = new MockOracle(scaledPrice);
        box.addTokenInstant(ptSusde25Sep, IOracle(address(ptSusdeUSDe_Oracle)));
        box.setIsAllocator(allocator, true);
        box.addFeederInstant(address(this));

        // Use e-mode 18 for borrowing USDe (better max LTV)
        uint8 eModeCategory = 18;
        FundingAave fundingModule = new FundingAave(address(box), pool, eModeCategory);
        bytes memory facilityData = "";
        box.addFundingInstant(fundingModule);
        box.addFundingFacilityInstant(fundingModule, facilityData);
        box.addFundingCollateralInstant(fundingModule, ptSusde25Sep);
        box.addFundingDebtInstant(fundingModule, usde);
        vm.stopPrank();

        // Supply 1000 PT tokens
        uint256 ptAmount = 1000 ether;
        deal(address(ptSusde25Sep), address(box), ptAmount);

        // Fund Box with initial USDe
        deal(address(usde), address(this), 1000e18);
        usde.approve(address(box), 1000e18);
        box.deposit(1000e18, address(this));

        vm.startPrank(allocator);

        // Supply PT as collateral
        box.pledge(fundingModule, facilityData, ptSusde25Sep, ptAmount);
        console2.log("Supplied", ptAmount / 1e18, "PT-sUSDe as collateral");

        // Borrow at 80% LTV
        (uint256 totalCollateral, , , , , ) = pool.getUserAccountData(address(fundingModule));
        uint256 targetBorrowAmount = ((totalCollateral * 80) / 100) * 1e10;
        uint256 navBefore = box.totalAssets();
        console2.log("NAV before borrow:", navBefore / 1e18, "USDe");

        box.borrow(fundingModule, facilityData, usde, targetBorrowAmount);
        console2.log("Borrowed", targetBorrowAmount / 1e18, "USDe at 80% LTV");

        // Verify e-mode and LTV
        assertEq(pool.getUserEMode(address(fundingModule)), eModeCategory, "E-mode not set correctly");

        uint256 finalLTV = fundingModule.ltv(facilityData);
        uint256 navAfter = box.totalAssets();
        console2.log("NAV after borrow:", navAfter / 1e18, "USDe");
        console2.log("Final LTV:", (finalLTV * 100) / 1e18, "%, E-mode:", pool.getUserEMode(address(fundingModule)));

        // Verify NAV stability
        assertApproxEqRel(navAfter, navBefore, 0.001e18, "NAV should remain constant");

        // Verify e-mode enabled higher LTV than standard mode
        assertGt(finalLTV, 0.7e18, "E-mode should enable >70% LTV");

        // Clean up
        vm.stopPrank();
        // TODO: this work even without this line
        //deal(address(usde), address(box), usde.balanceOf(address(box)) + targetBorrowAmount + 100e18);
        vm.startPrank(allocator);
        box.repay(fundingModule, facilityData, usde, type(uint256).max);
        box.depledge(fundingModule, facilityData, ptSusde25Sep, ptAmount);
        vm.stopPrank();
    }

    function testLeverageAccess() public {
        // Simple box setup for access control testing
        Box box = new Box(address(usdc), owner, curator, "Test Box", "TBOX", 0.01 ether, 7 days, 10 days, MAX_SHUTDOWN_WARMUP);

        vm.prank(curator);
        box.setIsAllocator(allocator, true);

        FundingAave fundingModule = new FundingAave(address(box), pool, 0);
        bytes memory facilityData = "";

        address[] memory testAddresses = new address[](4);
        testAddresses[0] = owner;
        testAddresses[1] = curator;
        testAddresses[2] = guardian;
        testAddresses[3] = user;

        for (uint256 i = 0; i < testAddresses.length; i++) {
            vm.startPrank(testAddresses[i]);

            vm.expectRevert(ErrorsLib.OnlyAllocators.selector);
            box.pledge(fundingModule, facilityData, usdc, 0);

            vm.expectRevert(ErrorsLib.OnlyAllocatorsOrWinddown.selector);
            box.depledge(fundingModule, facilityData, usdc, 0);

            vm.expectRevert(ErrorsLib.OnlyAllocators.selector);
            box.borrow(fundingModule, facilityData, usdc, 0);

            vm.expectRevert(ErrorsLib.OnlyAllocatorsOrWinddown.selector);
            box.repay(fundingModule, facilityData, usdc, 0);

            vm.stopPrank();
        }
    }

    function testTwoAdaptersDifferentEModes() public {
        // Deploy Box for USDC
        Box box = new Box(
            address(usdc),
            owner,
            curator,
            "Box Multi Collateral",
            "BOX_MC",
            0.01 ether,
            7 days,
            10 days,
            MAX_SHUTDOWN_WARMUP
        );

        // sUSDe - using e-mode 2 for borrowing stablecoins
        IERC20 sUsde = IERC20(0x9D39A5DE30e57443BfF2A8307A4256c8797A3497);
        IOracle sUsdeOracle = IOracle(0x873CD44b860DEDFe139f93e12A4AcCa0926Ffb87); // Oracle for sUSDe

        // Configure Box
        vm.startPrank(curator);
        box.setGuardianInstant(guardian);
        box.addTokenInstant(ptSusde25Sep, ptSusdeOracle);
        box.addTokenInstant(sUsde, sUsdeOracle);
        box.setIsAllocator(allocator, true);
        box.addFeederInstant(address(this));

        // Create two separate FundingAave adapters
        // Configure funding for PT-sUSDe with e-mode 17
        FundingAave fundingModulePTsUSDe = new FundingAave(address(box), pool, 17);
        // Configure funding for sUSDe with e-mode 2
        FundingAave fundingModuleSUSDe = new FundingAave(address(box), pool, 2);

        bytes memory facilityDataPTsUSDe = "";
        box.addFundingInstant(fundingModulePTsUSDe);
        box.addFundingFacilityInstant(fundingModulePTsUSDe, facilityDataPTsUSDe);
        box.addFundingCollateralInstant(fundingModulePTsUSDe, ptSusde25Sep);
        box.addFundingDebtInstant(fundingModulePTsUSDe, usdc);

        bytes memory facilityDataSUSDe = "";
        box.addFundingInstant(fundingModuleSUSDe);
        box.addFundingFacilityInstant(fundingModuleSUSDe, facilityDataSUSDe);
        box.addFundingCollateralInstant(fundingModuleSUSDe, sUsde);
        box.addFundingDebtInstant(fundingModuleSUSDe, usdc);
        vm.stopPrank();

        // Supply collaterals
        uint256 ptSusdeAmount = 1000 ether;
        uint256 sUsdeAmount = 1500 ether;
        deal(address(ptSusde25Sep), address(box), ptSusdeAmount);
        deal(address(sUsde), address(box), sUsdeAmount);

        // Fund Box with initial USDC
        deal(address(usdc), address(this), 1000e6);
        usdc.approve(address(box), 1000e6);
        box.deposit(1000e6, address(this));

        uint256 navBefore = box.totalAssets();
        console2.log("NAV before operations:", navBefore / 1e6, "USDC");

        vm.startPrank(allocator);

        // Supply collaterals
        box.pledge(fundingModulePTsUSDe, facilityDataPTsUSDe, ptSusde25Sep, ptSusdeAmount);
        console2.log("Supplied", ptSusdeAmount / 1e18, "PT-sUSDe for e-mode 17");

        box.pledge(fundingModuleSUSDe, facilityDataSUSDe, sUsde, sUsdeAmount);
        console2.log("Supplied", sUsdeAmount / 1e18, "sUSDe for e-mode 2");

        // Borrow with different e-modes
        uint256 borrowAmount1 = 500e6;
        uint256 borrowAmount2 = 300e6;

        box.borrow(fundingModulePTsUSDe, facilityDataPTsUSDe, usdc, borrowAmount1);
        console2.log("Borrowed", borrowAmount1 / 1e6, "USDC with e-mode 17");

        box.borrow(fundingModuleSUSDe, facilityDataSUSDe, usdc, borrowAmount2);
        console2.log("Borrowed", borrowAmount2 / 1e6, "USDC with e-mode 2");

        // Verify final state
        uint256 finalLTV1 = fundingModulePTsUSDe.ltv(facilityDataPTsUSDe);
        uint256 finalLTV2 = fundingModuleSUSDe.ltv(facilityDataSUSDe);
        uint256 finalEMode1 = pool.getUserEMode(address(fundingModulePTsUSDe));
        uint256 finalEMode2 = pool.getUserEMode(address(fundingModuleSUSDe));
        uint256 navAfter = box.totalAssets();
        console2.log("NAV after operations:", navAfter / 1e6, "USDC");
        console2.log("PT-sUSDe adapter - LTV:", (finalLTV1 * 100) / 1e18, "%, E-mode:", finalEMode1);
        console2.log("sUSDe adapter - LTV:", (finalLTV2 * 100) / 1e18, "%, E-mode:", finalEMode2);

        // Verify NAV stability
        assertApproxEqRel(navAfter, navBefore, 0.001e18, "NAV should remain constant");

        // Verify different e-modes are set correctly for each adapter
        assertEq(finalEMode1, 17, "PT-sUSDe adapter should use e-mode 17");
        assertEq(finalEMode2, 2, "sUSDe adapter should use e-mode 2");

        vm.stopPrank();
    }

    function testCombinedLTVWithTwoBorrows() public {
        // Deploy Box that can handle both USDC and USDe
        Box box = new Box(address(usdc), owner, curator, "Box Multi", "BOX_MULTI", 0.01 ether, 7 days, 10 days, MAX_SHUTDOWN_WARMUP);

        // Configure Box
        vm.startPrank(curator);
        box.setGuardianInstant(guardian);
        box.addTokenInstant(ptSusde25Sep, ptSusdeOracle);
        // Add USDe as a token since we'll be borrowing it
        // Create mock oracle for USDe: 1 USD = 1 USDe, price = 10^(36 + usdc_decimals - usde_decimals)
        MockOracle usdeOracle = new MockOracle(10 ** (36 + 6 - 18)); // 10^24 for USDC(6) to USDe(18)
        box.addTokenInstant(usde, IOracle(address(usdeOracle)));
        box.setIsAllocator(allocator, true);
        box.addFeederInstant(address(this));

        // Use e-mode 17 for borrowing stablecoins (allows both USDC and USDe)
        uint8 eModeCategory = 17;
        FundingAave fundingModule = new FundingAave(address(box), pool, eModeCategory);
        bytes memory facilityData = "";
        box.addFundingInstant(fundingModule);
        box.addFundingFacilityInstant(fundingModule, facilityData);
        box.addFundingCollateralInstant(fundingModule, ptSusde25Sep);
        box.addFundingDebtInstant(fundingModule, usdc);
        box.addFundingDebtInstant(fundingModule, usde);
        vm.stopPrank();

        // Supply 2000 PT tokens total (1000 for each step)
        uint256 ptAmount = 1000 ether;
        deal(address(ptSusde25Sep), address(box), ptAmount * 2);

        // Fund Box with initial assets
        deal(address(usdc), address(this), 1000e6);
        usdc.approve(address(box), 1000e6);
        box.deposit(1000e6, address(this));

        vm.startPrank(allocator);

        uint256 navBefore = box.totalAssets();
        console2.log("NAV before operations:", navBefore / 1e6, "USDC");

        // Step 1: Supply collateral and borrow USDC at 60% LTV
        box.pledge(fundingModule, facilityData, ptSusde25Sep, ptAmount);
        console2.log("Step 1: Supplied", ptAmount / 1e18, "PT-sUSDe");

        (uint256 collateralValue1, , , , , ) = pool.getUserAccountData(address(fundingModule));
        uint256 usdcBorrowAmount = (collateralValue1 * 60) / 100 / 100;
        box.borrow(fundingModule, facilityData, usdc, usdcBorrowAmount);
        console2.log("Step 1: Borrowed", usdcBorrowAmount / 1e6, "USDC at 60% LTV");

        // Step 2: Supply more collateral and borrow USDe at 80% LTV
        (uint256 collateralAfterUSDC, , , , , ) = pool.getUserAccountData(address(fundingModule));
        box.pledge(fundingModule, facilityData, ptSusde25Sep, ptAmount);
        console2.log("Step 2: Supplied", ptAmount / 1e18, "more PT-sUSDe");

        (uint256 collateralValue2, , , , , ) = pool.getUserAccountData(address(fundingModule));
        uint256 newCollateralValue = collateralValue2 - collateralAfterUSDC;

        uint256 usdeBorrowAmount = ((newCollateralValue * 80) / 100) * 1e10;
        box.borrow(fundingModule, facilityData, usde, usdeBorrowAmount);
        console2.log("Step 2: Borrowed", usdeBorrowAmount / 1e18, "USDe at 80% LTV");

        // Verify combined position
        uint256 finalLTV = fundingModule.ltv(facilityData);
        uint256 navAfter = box.totalAssets();
        console2.log("NAV after operations:", navAfter / 1e6, "USDC");
        console2.log("Combined LTV:", (finalLTV * 100) / 1e18, "% (expected ~70%)");

        // Verify NAV stability
        assertApproxEqRel(navAfter, navBefore, 0.001e18, "NAV should remain constant");

        // Verify combined LTV from two different debt types
        assertApproxEqAbs(finalLTV, 0.7e18, 0.005e18, "Combined LTV should be ~70%");

        // Clean up
        vm.stopPrank();
        deal(address(usdc), address(box), usdc.balanceOf(address(box)) + usdcBorrowAmount + 100e6);
        deal(address(usde), address(box), usde.balanceOf(address(box)) + usdeBorrowAmount + 100e18);
        vm.startPrank(allocator);
        box.repay(fundingModule, facilityData, usdc, type(uint256).max);
        box.repay(fundingModule, facilityData, usde, type(uint256).max);
        box.depledge(fundingModule, facilityData, ptSusde25Sep, ptAmount * 2);
        vm.stopPrank();
    }

    // ========== FLASH LOAN TESTS ==========

    function testAaveFlashLoanLeverage() public {
        console2.log("\n=== Aave Flash Loan Leverage Test ===");

        // Deploy Box for USDC
        Box box = new Box(address(usdc), owner, curator, "Flash Box", "FBOX", 0.01 ether, 7 days, 10 days, MAX_SHUTDOWN_WARMUP);

        // Configure Box
        vm.startPrank(curator);
        box.setGuardianInstant(guardian);
        box.addTokenInstant(ptSusde25Sep, ptSusdeOracle);
        box.setIsAllocator(allocator, true);
        box.addFeederInstant(address(this));

        // Setup funding module with e-mode 17
        FundingAave fundingModule = new FundingAave(address(box), pool, 17);
        bytes memory facilityData = "";
        box.addFundingInstant(fundingModule);
        box.addFundingFacilityInstant(fundingModule, facilityData);
        box.addFundingCollateralInstant(fundingModule, ptSusde25Sep);
        box.addFundingDebtInstant(fundingModule, usdc);

        // Create and authorize flash loan provider
        FlashLoanAave flashloanProvider = new FlashLoanAave(IPoolAddressesProviderAave(PROVIDER));
        box.setIsAllocator(address(flashloanProvider), true);

        // Pre-fund the flash loan provider with a small amount to cover premiums
        deal(address(usdc), address(flashloanProvider), 50e6); // 50 USDC for premiums

        vm.stopPrank();

        // Fund Box with initial USDC and provide some initial collateral
        deal(address(usdc), address(this), 1000e6);
        usdc.approve(address(box), 1000e6);
        box.deposit(1000e6, address(this));

        // Provide initial PT collateral to establish position
        uint256 initialPTAmount = 800e18; // 800 PT tokens
        deal(address(ptSusde25Sep), address(box), initialPTAmount);

        console2.log("\n1. Initial setup");
        console2.log("- Deposited: 1000 USDC to Box");
        console2.log("- Initial NAV:", box.totalAssets() / 1e6, "USDC");

        vm.startPrank(allocator);

        // First establish initial collateral position
        box.pledge(fundingModule, facilityData, ptSusde25Sep, initialPTAmount);
        console2.log("- Initial collateral:", initialPTAmount / 1e18, "PT-sUSDe");

        uint256 navBefore = box.totalAssets();
        uint256 leverageAmount = 500e6; // Flash loan 500 USDC for additional leverage

        // Setup MockSwapper for testing
        MockSwapper mockSwapper = new MockSwapper();
        MockOracle usdcOracle = new MockOracle(1e36); // 1 USDC = 1 USD (36 decimals)
        mockSwapper.setOracle(usdc, usdcOracle);
        mockSwapper.setOracle(ptSusde25Sep, ptSusdeOracle);
        deal(address(usdc), address(mockSwapper), 1000000e6);
        deal(address(ptSusde25Sep), address(mockSwapper), 1000000e18);
        ISwapper testSwapper = ISwapper(address(mockSwapper));

        console2.log("\n2. Executing Aave flash loan leverage");
        console2.log("- Flash loan amount:", leverageAmount / 1e6, "USDC");

        flashloanProvider.leverage(box, fundingModule, facilityData, testSwapper, "", ptSusde25Sep, usdc, leverageAmount);
        console2.log("- Flash loan leverage completed");

        uint256 finalCollateral = fundingModule.collateralBalance(facilityData, ptSusde25Sep);
        uint256 finalDebt = fundingModule.debtBalance(facilityData, usdc);
        uint256 finalLTV = fundingModule.ltv(facilityData);
        uint256 navAfter = box.totalAssets();

        console2.log("\n3. Final position");
        console2.log("- Final collateral:", finalCollateral / 1e18, "PT-sUSDe");
        console2.log("- Final debt:", finalDebt / 1e6, "USDC");
        console2.log("- Final LTV:", (finalLTV * 100) / 1e18, "%");
        console2.log("- NAV after:", navAfter / 1e6, "USDC");

        // Verify leverage worked
        assertGt(finalCollateral, 0, "Should have collateral");
        assertGt(finalDebt, 0, "Should have debt");
        assertGt(finalLTV, 0.3e18, "Should have leverage > 30%");
        assertApproxEqRel(navAfter, navBefore, 0.02e18, "NAV preserved");

        vm.stopPrank();
    }

    function testAaveFlashLoanDeleverage() public {
        console2.log("\n=== Aave Flash Loan Deleverage Test ===");

        // Deploy Box for USDC
        Box box = new Box(address(usdc), owner, curator, "Flash Box", "FBOX", 0.01 ether, 7 days, 10 days, MAX_SHUTDOWN_WARMUP);

        // Configure Box (similar to leverage test)
        vm.startPrank(curator);
        box.setGuardianInstant(guardian);
        box.addTokenInstant(ptSusde25Sep, ptSusdeOracle);
        box.setIsAllocator(allocator, true);
        box.addFeederInstant(address(this));

        FundingAave fundingModule = new FundingAave(address(box), pool, 17);
        bytes memory facilityData = "";
        box.addFundingInstant(fundingModule);
        box.addFundingFacilityInstant(fundingModule, facilityData);
        box.addFundingCollateralInstant(fundingModule, ptSusde25Sep);
        box.addFundingDebtInstant(fundingModule, usdc);

        FlashLoanAave flashloanProvider = new FlashLoanAave(IPoolAddressesProviderAave(PROVIDER));
        box.setIsAllocator(address(flashloanProvider), true);

        // Pre-fund the flash loan provider with a small amount to cover premiums
        deal(address(usdc), address(flashloanProvider), 50e6); // 50 USDC for premiums

        vm.stopPrank();

        // Fund and create initial leveraged position
        deal(address(usdc), address(this), 1000e6);
        usdc.approve(address(box), 1000e6);
        box.deposit(1000e6, address(this));

        // Provide initial PT collateral to establish position
        uint256 initialPTAmount = 800e18; // 800 PT tokens
        deal(address(ptSusde25Sep), address(box), initialPTAmount);

        vm.startPrank(allocator);

        // First establish initial collateral position
        box.pledge(fundingModule, facilityData, ptSusde25Sep, initialPTAmount);
        console2.log("- Setup initial collateral:", initialPTAmount / 1e18, "PT-sUSDe");

        // Setup MockSwapper for testing
        MockSwapper mockSwapper = new MockSwapper();
        MockOracle usdcOracle = new MockOracle(1e36); // 1 USDC = 1 USD
        mockSwapper.setOracle(usdc, usdcOracle);
        mockSwapper.setOracle(ptSusde25Sep, ptSusdeOracle);
        deal(address(usdc), address(mockSwapper), 1000000e6);
        deal(address(ptSusde25Sep), address(mockSwapper), 1000000e18);
        ISwapper testSwapper = ISwapper(address(mockSwapper));

        // Create leveraged position first
        uint256 leverageAmount = 300e6;
        flashloanProvider.leverage(box, fundingModule, facilityData, testSwapper, "", ptSusde25Sep, usdc, leverageAmount);

        uint256 initialCollateral = fundingModule.collateralBalance(facilityData, ptSusde25Sep);
        uint256 initialDebt = fundingModule.debtBalance(facilityData, usdc);
        console2.log("\n1. Initial leveraged position");
        console2.log("- Initial collateral:", initialCollateral / 1e18, "PT-sUSDe");
        console2.log("- Initial debt:", initialDebt / 1e6, "USDC");

        uint256 navBefore = box.totalAssets();
        console2.log("- NAV before deleverage:", navBefore / 1e6, "USDC");

        // Now deleverage by repaying half the debt
        uint256 deleverageAmount = initialDebt / 2;
        uint256 collateralToWithdraw = initialCollateral / 2;

        console2.log("\n2. Executing deleverage");
        console2.log("- Repaying:", deleverageAmount / 1e6, "USDC debt");
        console2.log("- Withdrawing:", collateralToWithdraw / 1e18, "PT-sUSDe");

        flashloanProvider.deleverage(
            box,
            fundingModule,
            facilityData,
            testSwapper,
            "",
            ptSusde25Sep,
            collateralToWithdraw,
            usdc,
            deleverageAmount
        );
        console2.log("- Deleverage operation completed");

        uint256 finalCollateral = fundingModule.collateralBalance(facilityData, ptSusde25Sep);
        uint256 finalDebt = fundingModule.debtBalance(facilityData, usdc);
        uint256 finalLTV = fundingModule.ltv(facilityData);
        uint256 navAfter = box.totalAssets();

        console2.log("\n3. Final position");
        console2.log("- Final collateral:", finalCollateral / 1e18, "PT-sUSDe");
        console2.log("- Final debt:", finalDebt / 1e6, "USDC");
        console2.log("- Final LTV:", (finalLTV * 100) / 1e18, "%");
        console2.log("- NAV after:", navAfter / 1e6, "USDC");

        // Verify deleverage worked
        assertLt(finalCollateral, initialCollateral, "Collateral reduced");
        assertLt(finalDebt, initialDebt, "Debt reduced");
        assertApproxEqRel(navAfter, navBefore, 0.02e18, "NAV preserved");

        vm.stopPrank();
    }

    function testAaveFlashLoanAccessControl() public {
        Box box = new Box(address(usdc), owner, curator, "Test Box", "TBOX", 0.01 ether, 7 days, 10 days, MAX_SHUTDOWN_WARMUP);

        vm.prank(curator);
        box.setIsAllocator(allocator, true);

        FundingAave fundingModule = new FundingAave(address(box), pool, 0);
        bytes memory facilityData = "";
        FlashLoanAave flashloanProvider = new FlashLoanAave(IPoolAddressesProviderAave(PROVIDER));

        // Setup MockSwapper for testing
        MockSwapper mockSwapper = new MockSwapper();
        ISwapper testSwapper = ISwapper(address(mockSwapper));

        // Test that non-allocators cannot call flash loan operations
        vm.expectRevert(ErrorsLib.OnlyAllocators.selector);
        flashloanProvider.leverage(box, fundingModule, facilityData, testSwapper, "", ptSusde25Sep, usdc, 100e6);

        vm.expectRevert(ErrorsLib.OnlyAllocators.selector);
        flashloanProvider.deleverage(box, fundingModule, facilityData, testSwapper, "", ptSusde25Sep, 100e18, usdc, 100e6);

        vm.expectRevert(ErrorsLib.OnlyAllocators.selector);
        flashloanProvider.refinance(box, fundingModule, facilityData, fundingModule, facilityData, ptSusde25Sep, 100e18, usdc, 100e6);
    }

    function testMaxLeveragePTsUSDe() public {
        Box box = new Box(address(usdc), owner, curator, "Max Leverage Box", "MAXBOX", 0.01 ether, 7 days, 10 days, MAX_SHUTDOWN_WARMUP);

        vm.startPrank(curator);
        box.setGuardianInstant(guardian);
        box.addTokenInstant(ptSusde25Sep, ptSusdeOracle);
        box.setIsAllocator(allocator, true);
        box.addFeederInstant(address(this));

        FundingAave fundingModule = new FundingAave(address(box), pool, 17);
        bytes memory facilityData = "";
        box.addFundingInstant(fundingModule);
        box.addFundingFacilityInstant(fundingModule, facilityData);
        box.addFundingCollateralInstant(fundingModule, ptSusde25Sep);
        box.addFundingDebtInstant(fundingModule, usdc);

        FlashLoanAave flashloanProvider = new FlashLoanAave(IPoolAddressesProviderAave(PROVIDER));
        box.setIsAllocator(address(flashloanProvider), true);
        deal(address(usdc), address(flashloanProvider), 500e6);
        vm.stopPrank();

        deal(address(usdc), address(this), 5000e6);
        usdc.approve(address(box), 5000e6);
        box.deposit(5000e6, address(this));

        uint256 initialPTAmount = 1000e18;
        deal(address(ptSusde25Sep), address(box), initialPTAmount);

        vm.startPrank(allocator);
        box.pledge(fundingModule, facilityData, ptSusde25Sep, initialPTAmount);
        uint256 navBefore = box.totalAssets();

        MockSwapper mockSwapper = new MockSwapper();
        MockOracle usdcOracle = new MockOracle(1e36);
        mockSwapper.setOracle(usdc, usdcOracle);
        mockSwapper.setOracle(ptSusde25Sep, ptSusdeOracle);
        deal(address(usdc), address(mockSwapper), 10000000e6);
        deal(address(ptSusde25Sep), address(mockSwapper), 10000000e18);
        ISwapper testSwapper = ISwapper(address(mockSwapper));

        uint256 maxFlashLoan = 8000e6;
        console2.log("Flash loan:", maxFlashLoan / 1e6, "USDC");

        flashloanProvider.leverage(box, fundingModule, facilityData, testSwapper, "", ptSusde25Sep, usdc, maxFlashLoan);
        uint256 finalCollateral = fundingModule.collateralBalance(facilityData, ptSusde25Sep);
        uint256 finalDebt = fundingModule.debtBalance(facilityData, usdc);
        uint256 finalLTV = fundingModule.ltv(facilityData);
        uint256 navAfter = box.totalAssets();

        console2.log("Final collateral:", finalCollateral / 1e18, "PT-sUSDe");
        console2.log("Final debt:", finalDebt / 1e6, "USDC");
        console2.log("Final LTV:", (finalLTV * 100) / 1e18, "%");

        assertTrue(finalLTV > 85e16, "LTV > 85%");
        assertTrue(finalLTV < 92e16, "LTV < liquidation threshold");
        assertApproxEqRel(navAfter, navBefore, 0.02e18, "NAV preserved");

        vm.stopPrank();
    }

    function testAaveOverRepayment() public {
        Box box = new Box(address(usdc), owner, curator, "Box", "BOX", 0.01 ether, 1 days, 7 days, 1 days);

        vm.startPrank(curator);
        box.setIsAllocator(allocator, true);
        box.addFeederInstant(address(this));
        vm.stopPrank();

        FundingAave fundingModule = new FundingAave(address(box), pool, 0);

        vm.startPrank(curator);
        box.addFundingInstant(fundingModule);
        box.addFundingFacilityInstant(fundingModule, bytes(""));
        box.addFundingDebtInstant(fundingModule, usdc);
        box.addFundingCollateralInstant(fundingModule, usdc);
        vm.stopPrank();

        deal(address(usdc), address(this), 1_000_000e6);
        usdc.approve(address(box), type(uint256).max);
        box.deposit(1_000_000e6, address(this));

        vm.startPrank(allocator);
        box.pledge(fundingModule, bytes(""), usdc, 10_000e6);
        box.borrow(fundingModule, bytes(""), usdc, 100e6);
        vm.stopPrank();

        vm.prank(curator);
        box.shutdown();
        vm.warp(block.timestamp + 2 days);

        uint256 boxBalance = usdc.balanceOf(address(box));
        box.repay(fundingModule, bytes(""), usdc, boxBalance);

        assertEq(usdc.balanceOf(address(fundingModule)), 0, "No funds stuck");
        assertEq(fundingModule.debtBalance(bytes(""), usdc), 0, "Debt repaid");
        assertGt(usdc.balanceOf(address(box)), boxBalance - 200e6, "Box keeps funds");
    }

    function testSkimNonDebtToken() public {
        vm.createSelectFork(vm.rpcUrl("mainnet"), 21000000);

        Box box = new Box(address(usdc), owner, curator, "Box", "BOX", 0.01 ether, 1 days, 7 days, 1 days);

        vm.startPrank(curator);
        box.setIsAllocator(allocator, true);
        vm.stopPrank();

        FundingAave fundingModule = new FundingAave(address(box), pool, 0);

        vm.startPrank(curator);
        box.addFundingInstant(fundingModule);
        box.addFundingFacilityInstant(fundingModule, bytes(""));
        vm.stopPrank();

        // Send some random token to the funding module
        IERC20 randomToken = usde;
        deal(address(randomToken), address(fundingModule), 100e18);

        uint256 balanceBefore = randomToken.balanceOf(address(box));

        vm.prank(allocator);
        box.skimFunding(fundingModule, randomToken);

        assertEq(randomToken.balanceOf(address(fundingModule)), 0, "Token skimmed");
        assertEq(randomToken.balanceOf(address(box)), balanceBefore + 100e18, "Box received token");
    }

    function testSkimTokenWithPositionFails() public {
        vm.createSelectFork(vm.rpcUrl("mainnet"), 21000000);

        Box box = new Box(address(usdc), owner, curator, "Box", "BOX", 0.01 ether, 1 days, 7 days, 1 days);

        vm.startPrank(curator);
        box.setIsAllocator(allocator, true);
        box.addFeederInstant(address(this));
        vm.stopPrank();

        FundingAave fundingModule = new FundingAave(address(box), pool, 0);

        vm.startPrank(curator);
        box.addFundingInstant(fundingModule);
        box.addFundingFacilityInstant(fundingModule, bytes(""));
        box.addFundingDebtInstant(fundingModule, usdc);
        box.addFundingCollateralInstant(fundingModule, usdc);
        vm.stopPrank();

        deal(address(usdc), address(this), 1_000_000e6);
        usdc.approve(address(box), type(uint256).max);
        box.deposit(1_000_000e6, address(this));

        vm.startPrank(allocator);
        box.pledge(fundingModule, bytes(""), usdc, 10_000e6);
        vm.stopPrank();

        // Get the aToken address for USDC collateral
        (, , , , , , , , address aTokenAddress, , , , , , ) = pool.getReserveData(address(usdc));
        IERC20 aToken = IERC20(aTokenAddress);

        // Try to skim the aToken - should fail because it changes NAV
        uint256 aTokenBalance = aToken.balanceOf(address(fundingModule));
        assertGt(aTokenBalance, 0, "Should have aToken balance");

        vm.prank(allocator);
        vm.expectRevert(abi.encodeWithSelector(ErrorsLib.SkimChangedNav.selector));
        box.skimFunding(fundingModule, aToken);
    }
}
