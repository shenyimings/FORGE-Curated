// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Steakhouse Financial
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import "./mocks/MockSwapper.sol";
import "./mocks/MockOracle.sol";

import {Box} from "../src/Box.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IBox} from "../src/interfaces/IBox.sol";
import {IOracle} from "../src/interfaces/IOracle.sol";
import {ISwapper} from "../src/interfaces/ISwapper.sol";
import {VaultV2} from "@vault-v2/src/VaultV2.sol";
import {MorphoVaultV1Adapter} from "@vault-v2/src/adapters/MorphoVaultV1Adapter.sol";
import "../src/libraries/Constants.sol";

import {IBoxAdapter} from "../src/interfaces/IBoxAdapter.sol";
import {IBoxAdapterFactory} from "../src/interfaces/IBoxAdapterFactory.sol";
import {BoxAdapterFactory} from "../src/factories/BoxAdapterFactory.sol";
import {BoxAdapterCachedFactory} from "../src/factories/BoxAdapterCachedFactory.sol";
import {BoxAdapter} from "../src/BoxAdapter.sol";
import {BoxAdapterCached} from "../src/BoxAdapterCached.sol";
import {EventsLib} from "../src/libraries/EventsLib.sol";
import {ErrorsLib} from "../src/libraries/ErrorsLib.sol";
import {VaultV2Lib} from "../src/periphery/VaultV2Lib.sol";
import {BoxLib} from "../src/periphery/BoxLib.sol";

import {IFunding} from "../src/interfaces/IFunding.sol";
import {FundingMorpho} from "../src/FundingMorpho.sol";
import {MarketParams, IMorpho} from "@morpho-blue/interfaces/IMorpho.sol";
import {FlashLoanMorpho} from "../src/periphery/FlashLoanMorpho.sol";

/**
 * @title Testing suite for leverage features of Box using Morpho on Base
 */
contract BoxLeverageMorphoBaseTest is Test {
    using BoxLib for Box;
    Box box;
    Box boxEth;
    address owner = address(0x1);
    address curator = address(0x2);
    address guardian = address(0x3);
    address allocator = address(0x4);
    address user = address(0x5);

    IERC20 usdc = IERC20(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913);

    IERC20 ptusr25sep = IERC20(0xa6F0A4D18B6f6DdD408936e81b7b3A8BEFA18e77);
    IOracle ptusr25sepOracle = IOracle(0x6AdeD60f115bD6244ff4be46f84149bA758D9085);

    IERC20 weth = IERC20(0x4200000000000000000000000000000000000006);
    IERC20 wsteth = IERC20(0xc1CBa3fCea344f92D9239c08C0568f6F2F0ee452);
    IOracle wstethOracle94 = IOracle(0x4A11590e5326138B514E08A9B52202D42077Ca65); // vs WETH
    IOracle wstethOracle96 = IOracle(0xaE10cbdAa587646246c8253E4532A002EE4fa7A4); // vs WETH

    ISwapper swapper = ISwapper(0x5C9dA86ECF5B35C8BF700a31a51d8a63fA53d1f6);

    IMorpho morpho = IMorpho(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb);
    address irm = 0x46415998764C29aB2a25CbeA6254146D50D22687;

    FundingMorpho fundingModule;
    MarketParams marketParams;
    bytes facilityData;

    FundingMorpho fundingModuleEth;
    MarketParams marketParamsEth1;
    bytes facilityDataEth1;

    MarketParams marketParamsEth2;
    bytes facilityDataEth2;

    /// @notice Will setup Peaty Base investing in bbqUSDC, box1 (stUSD) and box (PTs)
    function setUp() public {
        // Fork base on a  Sept 4th, 2025
        uint256 forkId = vm.createFork(vm.rpcUrl("base"), 35116463);
        vm.selectFork(forkId);

        // Creating Box USDC which will invest in PT-USR-25SEP
        string memory name = "Box USDC";
        string memory symbol = "BOX_USDC";
        uint256 maxSlippage = 0.01 ether; // 1%
        uint256 slippageEpochDuration = 7 days;
        uint256 shutdownSlippageDuration = 10 days;
        box = new Box(
            address(usdc),
            owner,
            curator,
            name,
            symbol,
            maxSlippage,
            slippageEpochDuration,
            shutdownSlippageDuration,
            MAX_SHUTDOWN_WARMUP
        );

        // Allow box 2 to invest in PT-USR-25SEP
        vm.startPrank(curator);
        box.setGuardianInstant(guardian);
        box.addTokenInstant(ptusr25sep, ptusr25sepOracle);
        box.setIsAllocator(address(allocator), true);
        box.addFeederInstant(address(this));

        fundingModule = new FundingMorpho(address(box), address(morpho), 99e16);
        marketParams = MarketParams(address(usdc), address(ptusr25sep), address(ptusr25sepOracle), irm, 915000000000000000);
        // And the funding facility
        facilityData = fundingModule.encodeFacilityData(marketParams);
        box.addFundingInstant(fundingModule);
        box.addFundingDebtInstant(fundingModule, usdc);
        box.addFundingCollateralInstant(fundingModule, ptusr25sep);
        box.addFundingFacilityInstant(fundingModule, facilityData);

        // Creating Box ETH which will invest in wstETH
        name = "Box ETH";
        symbol = "BOX_ETH";
        maxSlippage = 0.01 ether; // 1%
        slippageEpochDuration = 7 days;
        shutdownSlippageDuration = 10 days;
        boxEth = new Box(
            address(weth),
            owner,
            curator,
            name,
            symbol,
            maxSlippage,
            slippageEpochDuration,
            shutdownSlippageDuration,
            MAX_SHUTDOWN_WARMUP
        );

        // Allow box 2 to invest in PT-USR-25SEP
        vm.startPrank(curator);
        boxEth.setGuardianInstant(guardian);
        boxEth.addTokenInstant(wsteth, wstethOracle94);
        boxEth.setIsAllocator(address(allocator), true);
        boxEth.addFeederInstant(address(this));

        fundingModuleEth = new FundingMorpho(address(boxEth), address(morpho), 99e16);
        marketParamsEth1 = MarketParams(address(weth), address(wsteth), address(wstethOracle94), irm, 945000000000000000);
        // And the funding facility
        facilityDataEth1 = fundingModuleEth.encodeFacilityData(marketParamsEth1);
        boxEth.addFundingInstant(fundingModuleEth);
        boxEth.addFundingCollateralInstant(fundingModuleEth, wsteth);
        boxEth.addFundingDebtInstant(fundingModuleEth, weth);
        boxEth.addFundingFacilityInstant(fundingModuleEth, facilityDataEth1);

        marketParamsEth2 = MarketParams(address(weth), address(wsteth), address(wstethOracle96), irm, 965000000000000000);
        // And the funding facility
        facilityDataEth2 = fundingModuleEth.encodeFacilityData(marketParamsEth2);
        boxEth.addFundingFacilityInstant(fundingModuleEth, facilityDataEth2);

        vm.stopPrank();
    }

    /////////////////////////////
    /// Setup checks
    /////////////////////////////

    function testSetup() public view {
        assertEq(box.fundingsLength(), 1, "There is one source of funding");
        IFunding funding = box.fundings(0);
        assertEq(funding.facilitiesLength(), 1, "There is one funding facility");
        assertEq(funding.collateralTokensLength(), 1, "There is one funding collateral");
        assertEq(funding.debtTokensLength(), 1, "There is one funding loan token");

        assertEq(address(funding), address(fundingModule), "fundingModule is correct");
        assertEq(address(funding.debtTokens(0)), address(usdc), "Loan token is USDC");
        assertEq(address(funding.collateralTokens(0)), address(ptusr25sep), "Collateral token is ptusr25sep");
        assertEq(funding.facilities(0), facilityData, "facilityData is correct");

        bytes memory facility = funding.facilities(0);

        MarketParams memory marketParams2 = fundingModuleEth.decodeFacilityData(facility);
        assertEq(marketParams2.loanToken, marketParams.loanToken, "Same loan token");
        assertEq(marketParams2.collateralToken, marketParams.collateralToken, "Same collateral token");
        assertEq(marketParams2.oracle, marketParams.oracle, "Same oracle");
        assertEq(marketParams2.irm, marketParams.irm, "Same irm");
        assertEq(marketParams2.lltv, marketParams.lltv, "Same lltv");
    }

    /////////////////////////////
    /// Access control
    /////////////////////////////

    function testLeverageAccess() public {
        address[] memory testAddresses = new address[](4);
        testAddresses[0] = owner;
        testAddresses[1] = curator;
        testAddresses[2] = guardian;
        testAddresses[3] = user;

        FlashLoanMorpho flashloanProvider = new FlashLoanMorpho(address(morpho));

        for (uint256 i = 0; i < testAddresses.length; i++) {
            vm.startPrank(testAddresses[i]);

            vm.expectRevert(ErrorsLib.OnlyAllocators.selector);
            box.pledge(fundingModule, facilityData, ptusr25sep, 0);

            vm.expectRevert(ErrorsLib.OnlyAllocatorsOrWinddown.selector);
            box.depledge(fundingModule, facilityData, ptusr25sep, 0);

            vm.expectRevert(ErrorsLib.OnlyAllocators.selector);
            box.borrow(fundingModule, facilityData, usdc, 0);

            vm.expectRevert(ErrorsLib.OnlyAllocatorsOrWinddown.selector);
            box.repay(fundingModule, facilityData, usdc, 0);

            vm.expectRevert(ErrorsLib.OnlyAllocatorsOrWinddown.selector);
            box.flash(usdc, 1, "");

            vm.expectRevert(ErrorsLib.OnlyAllocators.selector);
            flashloanProvider.leverage(box, fundingModule, facilityData, swapper, "", ptusr25sep, usdc, 1);

            // TODO maybe thise one should be allowed for shutdown as well?
            vm.expectRevert(ErrorsLib.OnlyAllocators.selector);
            flashloanProvider.deleverage(box, fundingModule, facilityData, swapper, "", ptusr25sep, 1, usdc, 1);

            vm.expectRevert(ErrorsLib.OnlyAllocators.selector);
            flashloanProvider.refinance(box, fundingModule, facilityData, fundingModule, facilityData, ptusr25sep, 1, usdc, 1);

            vm.stopPrank();
        }
    }

    function testRemoveFundingModule() public {
        uint256 USDC_1000 = 1000 * 10 ** 6;
        uint256 USDC_500 = 500 * 10 ** 6;

        // Setup
        vm.prank(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb); // Morpho Blue
        usdc.transfer(address(this), USDC_1000); // Transfer 1000 USDC to this contract
        vm.prank(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb); // Morpho Blue
        usdc.transfer(address(box), 1); // Transfer 1 to the box contarct to repay the debt later
        usdc.approve(address(box), USDC_1000);
        box.deposit(USDC_1000, address(this)); // Deposit 1000 USDC

        vm.startPrank(allocator);
        box.allocate(ptusr25sep, USDC_1000, swapper, "");
        uint256 ptBalance = ptusr25sep.balanceOf(address(box));
        box.pledge(fundingModule, facilityData, ptusr25sep, ptBalance);
        box.borrow(fundingModule, facilityData, usdc, USDC_500);
        vm.stopPrank();

        // Test starts here
        vm.startPrank(curator);
        vm.expectRevert(ErrorsLib.CannotRemove.selector);
        box.removeFunding(fundingModule);
        vm.expectRevert(ErrorsLib.CannotRemove.selector);
        box.removeFundingFacility(fundingModule, facilityData);
        vm.expectRevert(ErrorsLib.CannotRemove.selector);
        box.removeFundingCollateral(fundingModule, ptusr25sep);
        vm.expectRevert(ErrorsLib.CannotRemove.selector);
        box.removeFundingDebt(fundingModule, usdc);
        vm.stopPrank();

        vm.prank(allocator);
        box.repay(fundingModule, facilityData, usdc, USDC_500 + 1);
        assertEq(fundingModule.debtBalance(facilityData, usdc), 0, "No more debt");

        vm.prank(curator);
        vm.expectRevert(ErrorsLib.CannotRemove.selector);
        box.removeFundingCollateral(fundingModule, ptusr25sep);

        vm.prank(allocator);
        box.depledge(fundingModule, facilityData, ptusr25sep, ptBalance);

        vm.startPrank(curator);
        // Can remove facility now, need to start from it because it's Morpho
        box.removeFundingFacility(fundingModule, facilityData);

        // Can't remove twice
        vm.expectRevert(ErrorsLib.NotWhitelisted.selector);
        box.removeFundingFacility(fundingModule, facilityData);

        // Can remove debt USDC now
        box.removeFundingDebt(fundingModule, usdc);

        // Can't remove twice
        vm.expectRevert(ErrorsLib.NotWhitelisted.selector);
        box.removeFundingDebt(fundingModule, usdc);

        vm.expectRevert(ErrorsLib.CannotRemove.selector);
        box.removeFunding(fundingModule);

        // We can remove collateral as no balance
        box.removeFundingCollateral(fundingModule, ptusr25sep);

        // Can't remove twice
        vm.expectRevert(ErrorsLib.NotWhitelisted.selector);
        box.removeFundingCollateral(fundingModule, ptusr25sep);

        // Can remove funding module now as there are no debt or collateral tokens
        box.removeFunding(fundingModule);

        // Can't remove twice
        vm.expectRevert(ErrorsLib.NotWhitelisted.selector);
        box.removeFunding(fundingModule);

        assertEq(box.fundingsLength(), 0, "There is no more source of funding");

        vm.stopPrank();
    }

    /////////////////////////////
    /// SCENARIOS
    /////////////////////////////

    function testBoxLeverage() public {
        console2.log("\n=== Starting testBoxLeverage ===");
        uint256 USDC_1000 = 1000 * 10 ** 6;

        // Get some USDC
        console2.log("\n1. Setting up initial USDC funding");
        vm.prank(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb); // Morpho Blue
        usdc.transfer(address(this), USDC_1000); // Transfer 1000 USDC to this contract

        usdc.approve(address(box), USDC_1000);
        box.deposit(USDC_1000, address(this)); // Deposit 1000 USDC
        console2.log("- Deposited:", USDC_1000 / 1e6, "USDC to Box");

        vm.startPrank(allocator);

        console2.log("\n2. Allocating USDC to PT-USR-25SEP");
        box.allocate(ptusr25sep, USDC_1000, swapper, "");
        uint256 ptBalance = ptusr25sep.balanceOf(address(box));

        uint256 totalAssets = box.totalAssets();
        console2.log("- PT balance received:", ptBalance / 1e18, "PT tokens");
        console2.log("- Total assets value:", totalAssets / 1e6, "USDC");

        assertEq(usdc.balanceOf(address(box)), 0, "No more USDC in the Box");
        assertEq(ptBalance, 1005863679192785855851, "ptusr25sep in the Box");
        assertEq(totalAssets, 999828627, "totalAssets in the Box after ptusr25sep allocation");

        box.pledge(fundingModule, facilityData, ptusr25sep, ptBalance);

        assertEq(ptusr25sep.balanceOf(address(box)), 0, "No more ptusr25sep in the Box");
        assertEq(fundingModule.collateralBalance(facilityData, ptusr25sep), ptBalance, "Collateral is correct");
        assertEq(box.totalAssets(), totalAssets, "totalAssets in the Box after ptusr25sep collateral supply");

        // Record NAV before borrowing
        uint256 navBeforeBorrow = box.totalAssets();
        console2.log("\n4. Borrowing USDC against PT collateral");
        console2.log("- NAV before borrow:", navBeforeBorrow / 1e6, "USDC");

        box.borrow(fundingModule, facilityData, usdc, 500 * 10 ** 6);
        console2.log("- Borrowed:", 500, "USDC");

        assertEq(usdc.balanceOf(address(box)), 500 * 10 ** 6, "500 USDC in the Box");

        // Check NAV after borrowing
        uint256 navAfterBorrow = box.totalAssets();
        console2.log("- NAV after borrow:", navAfterBorrow / 1e6, "USDC");
        int256 navChange = int256(navAfterBorrow) - int256(navBeforeBorrow);
        if (navChange >= 0) {
            console2.log("- NAV change: +", uint256(navChange), "units");
        } else {
            console2.log("- NAV change: -", uint256(-navChange), "units");
        }
        assertApproxEqRel(navAfterBorrow, navBeforeBorrow, 0.001e18, "NAV should remain approximately constant after borrowing");

        // Get some USDC to cover rounding
        console2.log("\n5. Repaying debt and withdrawing collateral");
        vm.stopPrank();
        vm.prank(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb); // Morpho Blue
        usdc.transfer(address(box), 1);
        vm.startPrank(allocator);

        box.repay(fundingModule, facilityData, usdc, type(uint256).max);

        box.depledge(fundingModule, facilityData, ptusr25sep, ptBalance);
        assertEq(ptusr25sep.balanceOf(address(box)), 1005863679192785855851, "ptusr25sep are back in the Box");

        console2.log("\n[PASS] Test completed successfully");
        vm.stopPrank();
    }

    function testBoxWind() public {
        console2.log("\n=== Starting testBoxWind (Looping Test) ===");
        uint256 USDC_1000 = 1000 * 10 ** 6;
        uint256 USDC_500 = 500 * 10 ** 6;

        // TODO: We shouldn't have to do this
        vm.prank(curator);
        box.setIsAllocator(address(box), true);

        // Get some USDC in Box
        console2.log("\n1. Setting up initial USDC funding");
        vm.prank(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb); // Morpho Blue
        usdc.transfer(address(this), USDC_1000); // Transfer 1000 USDC to this contract
        usdc.approve(address(box), USDC_1000);
        box.deposit(USDC_1000, address(this)); // Deposit 1000 USDC
        console2.log("- Deposited:", USDC_1000 / 1e6, "USDC to Box");

        vm.startPrank(allocator);

        console2.log("\n2. Allocating USDC to PT-USR-25SEP");
        box.allocate(ptusr25sep, USDC_1000, swapper, "");
        uint256 ptBalance = ptusr25sep.balanceOf(address(box));
        console2.log("- PT balance received:", ptBalance / 1e18, "PT tokens");

        assertEq(usdc.balanceOf(address(box)), 0, "No more USDC in the Box");
        assertEq(ptBalance, 1005863679192785855851, "ptusr25sep in the Box");

        console2.log("\n3. Supplying PT as collateral");
        box.pledge(fundingModule, facilityData, ptusr25sep, ptBalance);
        console2.log("- Initial collateral supplied:", ptBalance / 1e18, "PT tokens");

        assertEq(ptusr25sep.balanceOf(address(box)), 0, "No more ptusr25sep in the Box");
        assertEq(fundingModule.collateralBalance(ptusr25sep), ptBalance, "Collateral is correct");

        console2.log("\n4. Setting up flashloan provider");
        FlashLoanMorpho flashloanProvider = new FlashLoanMorpho(address(morpho));

        vm.stopPrank();
        vm.prank(curator);
        box.setIsAllocator(address(flashloanProvider), true);
        vm.startPrank(allocator);

        // Record NAV before wind operation
        uint256 navBeforeWind = box.totalAssets();
        console2.log("\n5. Executing wind operation (leverage loop)");
        console2.log("- NAV before wind:", navBeforeWind / 1e6, "USDC");

        flashloanProvider.leverage(box, fundingModule, facilityData, swapper, "", ptusr25sep, usdc, USDC_500);
        console2.log("- Wind operation completed with", USDC_500 / 1e6, "USDC borrowed");

        assertEq(fundingModule.debtBalance(usdc), USDC_500 + 1, "Debt is correct");
        assertEq(fundingModule.collateralBalance(ptusr25sep), 1508804269763505704594, "Collateral after wind is correct");

        console2.log("- New collateral amount:", fundingModule.collateralBalance(ptusr25sep) / 1e18, "PT tokens");
        console2.log("- Debt amount:", fundingModule.debtBalance(usdc) / 1e6, "USDC");

        // Check NAV after wind
        uint256 navAfterWind = box.totalAssets();
        console2.log("- NAV after wind:", navAfterWind / 1e6, "USDC");
        int256 navChangeWind = int256(navAfterWind) - int256(navBeforeWind);
        if (navChangeWind >= 0) {
            console2.log("- NAV change from wind: +", uint256(navChangeWind), "units");
        } else {
            console2.log("- NAV change from wind: -", uint256(-navChangeWind), "units");
        }
        assertApproxEqRel(navAfterWind, navBeforeWind, 0.01e18, "NAV should remain approximately constant after wind");

        console2.log("\n6. Executing unwind operation (deleverage)");
        flashloanProvider.deleverage(
            box,
            fundingModule,
            facilityData,
            swapper,
            "",
            ptusr25sep,
            fundingModule.collateralBalance(ptusr25sep),
            usdc,
            type(uint256).max
        );
        console2.log("- Unwind operation completed");

        assertEq(fundingModule.debtBalance(usdc), 0, "Debt is fully repaid");
        assertEq(fundingModule.collateralBalance(ptusr25sep), 0, "No collateral left on Morpho");
        assertEq(ptusr25sep.balanceOf(address(box)), 0, "No ptusr25sep are in the Box");
        assertEq(usdc.balanceOf(address(box)), 999371412, "USDC is back in the Box");

        // Check NAV after unwind
        uint256 navAfterUnwind = box.totalAssets();
        console2.log("- NAV after unwind:", navAfterUnwind / 1e6, "USDC");
        console2.log("- Final USDC balance:", usdc.balanceOf(address(box)) / 1e6, "USDC");
        int256 navChangeFinal = int256(navAfterUnwind) - int256(navBeforeWind);
        if (navChangeFinal >= 0) {
            console2.log("- NAV change from original: +", uint256(navChangeFinal), "units");
        } else {
            console2.log("- NAV change from original: -", uint256(-navChangeFinal), "units");
        }
        assertApproxEqRel(navAfterUnwind, navBeforeWind, 0.01e18, "NAV should return to approximately original value after unwind");

        console2.log("\n[PASS] Test completed successfully");
        vm.stopPrank();
    }

    function testShift() public {
        console2.log("\n=== Starting testShift (Market Migration Test) ===");
        vm.prank(curator);
        boxEth.setIsAllocator(address(boxEth), true);

        // Get some WETH in Box
        console2.log("\n1. Setting up initial WETH funding");
        vm.prank(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb); // Morpho Blue
        weth.transfer(address(this), 10 ether);
        weth.approve(address(boxEth), 10 ether);
        boxEth.deposit(10 ether, address(this));
        console2.log("- Deposited: 10 WETH to Box");

        vm.startPrank(allocator);

        // Swap WETH to wstETH
        console2.log("\n2. Swapping WETH to wstETH");
        boxEth.allocate(wsteth, 10 ether, swapper, "");

        uint256 wstEthBalance = wsteth.balanceOf(address(boxEth));
        console2.log("- Received:", wstEthBalance / 1e18, "wstETH");
        // With 10 ETH, we should get ~10x more wstETH than the original 1 ETH test
        assertApproxEqAbs(wstEthBalance, 8254886504705994620, 1e17, "wstETH in the Box");

        // Supply wsteth collateral to first market
        console2.log("\n3. Supplying collateral to Market 1 (94% LLTV)");
        boxEth.pledge(fundingModuleEth, facilityDataEth1, wsteth, wstEthBalance);
        console2.log("- Supplied:", wstEthBalance / 1e18, "wstETH to Market 1");
        assertEq(fundingModuleEth.collateralBalance(facilityDataEth1, wsteth), wstEthBalance);
        assertEq(fundingModuleEth.collateralBalance(facilityDataEth2, wsteth), 0 ether);
        assertEq(fundingModuleEth.ltv(facilityDataEth1), 0 ether);

        // Prepare flashloan facility
        console2.log("\n4. Setting up flashloan provider");
        FlashLoanMorpho flashloanProvider = new FlashLoanMorpho(address(morpho));
        vm.stopPrank();
        vm.prank(curator);
        boxEth.setIsAllocator(address(flashloanProvider), true);
        vm.startPrank(allocator);

        // Record NAV before leveraging
        uint256 navBeforeLeverage = boxEth.totalAssets();
        console2.log("\n5. Leveraging position on Market 1");
        console2.log("- NAV before leverage:", navBeforeLeverage / 1e18, "WETH");

        // Leverage on the first market
        flashloanProvider.leverage(boxEth, fundingModuleEth, facilityDataEth1, swapper, "", wsteth, weth, 5 ether);
        console2.log("- Leveraged with 5 WETH borrowed");

        console2.log("- Market 1 collateral:", fundingModuleEth.collateralBalance(facilityDataEth1, wsteth) / 1e18, "wstETH");
        console2.log("- Market 1 debt:", fundingModuleEth.debtBalance(facilityDataEth1, weth) / 1e18, "WETH");
        console2.log("- Market 1 LTV:", (fundingModuleEth.ltv(facilityDataEth1) * 100) / 1e18, "%");

        // Approximate values since we're using 10x scale
        assertApproxEqRel(
            fundingModuleEth.collateralBalance(facilityDataEth1, wsteth),
            12382329159449028340,
            0.01e18,
            "Market 1 collateral"
        );
        assertEq(fundingModuleEth.collateralBalance(facilityDataEth2, wsteth), 0);
        assertApproxEqRel(fundingModuleEth.debtBalance(facilityDataEth1, weth), 5000000000000000010, 0.01e18, "Market 1 debt");
        assertEq(fundingModuleEth.debtBalance(facilityDataEth2, weth), 0 ether);
        assertApproxEqRel(fundingModuleEth.ltv(facilityDataEth1), 332938470795156227, 0.01e18, "Market 1 LTV");

        // Check NAV after leverage
        uint256 navAfterLeverage = boxEth.totalAssets();
        console2.log("- NAV after leverage:", navAfterLeverage / 1e18, "WETH");
        int256 navChangeLeverage = int256(navAfterLeverage) - int256(navBeforeLeverage);
        if (navChangeLeverage >= 0) {
            console2.log("- NAV change from leverage: +", uint256(navChangeLeverage), "units");
        } else {
            console2.log("- NAV change from leverage: -", uint256(-navChangeLeverage), "units");
        }
        assertApproxEqRel(navAfterLeverage, navBeforeLeverage, 0.01e18, "NAV should remain approximately constant after leverage");

        // Shift all the position to the second market
        console2.log("\n6. Shifting position from Market 1 to Market 2 (96% LLTV)");
        flashloanProvider.refinance(
            boxEth,
            fundingModuleEth,
            facilityDataEth1,
            fundingModuleEth,
            facilityDataEth2,
            wsteth,
            type(uint256).max,
            weth,
            type(uint256).max
        );
        console2.log("- Position shifted to Market 2");

        console2.log("- Market 1 collateral:", fundingModuleEth.collateralBalance(facilityDataEth1, wsteth) / 1e18, "wstETH");
        console2.log("- Market 1 debt:", fundingModuleEth.debtBalance(facilityDataEth1, weth) / 1e18, "WETH");
        console2.log("- Market 2 collateral:", fundingModuleEth.collateralBalance(facilityDataEth2, wsteth) / 1e18, "wstETH");
        console2.log("- Market 2 debt:", fundingModuleEth.debtBalance(facilityDataEth2, weth) / 1e18, "WETH");
        console2.log("- Market 2 LTV:", (fundingModuleEth.ltv(facilityDataEth2) * 100) / 1e18, "%");

        assertEq(fundingModuleEth.collateralBalance(facilityDataEth1, wsteth), 0, "No more market 1 collateral");
        assertApproxEqRel(
            fundingModuleEth.collateralBalance(facilityDataEth2, wsteth),
            12382329159449028340,
            0.01e18,
            "Market 2 collateral"
        );
        assertEq(fundingModuleEth.debtBalance(facilityDataEth1, weth), 0 ether, "No more market 1 debt");
        assertApproxEqRel(fundingModuleEth.debtBalance(facilityDataEth2, weth), 5000000000000000020, 0.01e18, "Market 2 debt");
        assertEq(fundingModuleEth.ltv(facilityDataEth1), 0 ether, "Market 1 LTV should be 0");
        assertApproxEqRel(fundingModuleEth.ltv(facilityDataEth2), 332938470795156228, 0.01e18, "Market 2 LTV");

        // Check NAV after shift
        uint256 navAfterShift = boxEth.totalAssets();
        console2.log("- NAV after shift:", navAfterShift / 1e18, "WETH");
        int256 navChangeShift = int256(navAfterShift) - int256(navAfterLeverage);
        if (navChangeShift >= 0) {
            console2.log("- NAV change from shift: +", uint256(navChangeShift), "units");
        } else {
            console2.log("- NAV change from shift: -", uint256(-navChangeShift), "units");
        }
        assertApproxEqRel(navAfterShift, navAfterLeverage, 0.001e18, "NAV should remain approximately constant after shift");

        console2.log("\n[PASS] Test completed successfully");
        vm.stopPrank();
    }

    function testMaxLeverageWstETH() public {
        console2.log("\n=== Starting Maximum Leverage Test ===");

        vm.prank(curator);
        boxEth.setIsAllocator(address(boxEth), true);

        console2.log("\n1. Initial funding setup");
        vm.prank(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb);
        weth.transfer(address(this), 20 ether);
        weth.approve(address(boxEth), 20 ether);
        boxEth.deposit(20 ether, address(this));
        console2.log("- Deposited: 20 WETH to Box");

        vm.startPrank(allocator);

        console2.log("\n2. Converting WETH to wstETH");
        boxEth.allocate(wsteth, 20 ether, swapper, "");
        uint256 initialWstEthBalance = wsteth.balanceOf(address(boxEth));
        console2.log("- Initial wstETH balance:", initialWstEthBalance / 1e18, "wstETH");

        console2.log("\n3. Pledging initial collateral");
        boxEth.pledge(fundingModuleEth, facilityDataEth2, wsteth, initialWstEthBalance);
        console2.log("- Pledged:", initialWstEthBalance / 1e18, "wstETH as collateral");

        FlashLoanMorpho flashloanProvider = new FlashLoanMorpho(address(morpho));
        vm.stopPrank();
        vm.prank(curator);
        boxEth.setIsAllocator(address(flashloanProvider), true);

        MockSwapper mockSwapper = new MockSwapper();
        MockOracle wethOracle = new MockOracle(1e36);
        mockSwapper.setOracle(weth, wethOracle);
        mockSwapper.setOracle(wsteth, wstethOracle96);
        deal(address(weth), address(mockSwapper), 1000000 ether);
        deal(address(wsteth), address(mockSwapper), 1000000 ether);
        ISwapper testSwapper = ISwapper(address(mockSwapper));

        vm.startPrank(allocator);

        uint256 navBefore = boxEth.totalAssets();
        uint256 maxFlashLoan = 110 ether;
        console2.log("\n4. Executing maximum leverage");
        console2.log("- NAV before leverage:", navBefore / 1e18, "WETH");
        console2.log("- Flash loan amount:", maxFlashLoan / 1e18, "WETH");

        flashloanProvider.leverage(boxEth, fundingModuleEth, facilityDataEth2, testSwapper, "", wsteth, weth, maxFlashLoan);
        console2.log("- Leverage operation completed");

        uint256 finalCollateralBalance = fundingModuleEth.collateralBalance(facilityDataEth2, wsteth);
        uint256 wstethPrice = wstethOracle96.price();
        uint256 finalCollateralValue = (finalCollateralBalance * wstethPrice) / ORACLE_PRECISION;
        uint256 finalDebt = fundingModuleEth.debtBalance(facilityDataEth2, weth);
        uint256 finalLTV = (finalDebt * 1e18) / finalCollateralValue;
        uint256 navAfter = boxEth.totalAssets();

        console2.log("\n5. Final position");
        console2.log("- Final collateral:", finalCollateralBalance / 1e18, "wstETH");
        console2.log("- Final debt:", finalDebt / 1e18, "WETH");
        console2.log("- Final LTV:", finalLTV / 1e16, "bps");
        console2.log("- NAV after leverage:", navAfter / 1e18, "WETH");

        assertTrue(finalLTV > 840000000000000000, "LTV > 84%");
        assertTrue(finalLTV < 965000000000000000, "LTV < LLTV");
        assertTrue(finalCollateralBalance > initialWstEthBalance * 2, "Collateral > 2x");
        assertApproxEqRel(navAfter, navBefore, 0.02e18, "NAV preserved");

        vm.stopPrank();
    }
}
