// SPDX-License-Identifier: GPL-2.0-or-later
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
import {FundingMorpho} from "../src/FundingMorpho.sol";
import {IMorpho, MarketParams, Id} from "@morpho-blue/interfaces/IMorpho.sol";
import {IBox} from "../src/interfaces/IBox.sol";
import "../src/libraries/Constants.sol";

/// @notice Minimal Aave v3 Addresses Provider to obtain the Pool
interface IPoolAddressesProvider {
    function getPool() external view returns (address);
}

/**
 * @title Testing suite for cross-protocol leverage using both Aave and Morpho on Mainnet
 */
contract BoxLeverageMainnetTest is Test {
    using BoxLib for Box;

    address owner = address(0x1);
    address curator = address(0x2);
    address guardian = address(0x3);
    address allocator = address(0x4);
    address user = address(0x5);

    // Mainnet addresses
    address constant AAVE_PROVIDER = 0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e; // Aave v3 PoolAddressesProvider (Mainnet)
    address constant MORPHO_ADDRESS = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb; // Morpho Blue (Mainnet)

    IERC20 usdc = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48); // Mainnet USDC
    IERC20 ptSusde25Sep = IERC20(0x9F56094C450763769BA0EA9Fe2876070c0fD5F77); // PT-sUSDe-25SEP2025
    IOracle ptSusdeOracle = IOracle(0x5139aa359F7F7FdE869305e8C7AD001B28E1C99a); // Oracle for PT-sUSDe-25SEP2025

    ISwapper swapper = ISwapper(0x5C9dA86ECF5B35C8BF700a31a51d8a63fA53d1f6); // Same swapper as Base

    IPool aavePool;
    IMorpho morpho;

    // Morpho market ID provided by user
    bytes32 constant MORPHO_MARKET_ID = 0x3e37bd6e02277f15f93cd7534ce039e60d19d9298f4d1bc6a3a4f7bf64de0a1c;

    function setUp() public {
        // Fork mainnet from specific block
        uint256 forkId = vm.createFork(vm.rpcUrl("mainnet"), 23294087);
        vm.selectFork(forkId);

        // Get protocol instances
        aavePool = IPool(IPoolAddressesProvider(AAVE_PROVIDER).getPool());
        morpho = IMorpho(MORPHO_ADDRESS);
    }

    function testCrossProtocolBorrowing() public {
        // Deploy Box for USDC
        Box box = new Box(
            address(usdc),
            owner,
            curator,
            "Cross Protocol Box",
            "XPROT_BOX",
            0.01 ether,
            7 days,
            10 days,
            MAX_SHUTDOWN_WARMUP
        );

        // Configure Box
        vm.startPrank(curator);
        box.setGuardianInstant(guardian);
        box.addTokenInstant(ptSusde25Sep, ptSusdeOracle);
        box.setIsAllocator(allocator, true);
        box.addFeederInstant(address(this));

        // Setup Aave adapter with e-mode 17 for stablecoins
        uint8 eModeCategory = 17;
        FundingAave aaveModule = new FundingAave(address(box), aavePool, eModeCategory);
        bytes memory aaveFacilityData = ""; // No extra data needed for Aave
        box.addFundingInstant(aaveModule);
        box.addFundingCollateralInstant(aaveModule, ptSusde25Sep);
        box.addFundingDebtInstant(aaveModule, usdc);
        box.addFundingFacilityInstant(aaveModule, aaveFacilityData);

        // Setup Morpho adapter - get market params directly from Morpho
        FundingMorpho morphoModule = new FundingMorpho(address(box), address(morpho), 99e16);
        MarketParams memory marketParams = morpho.idToMarketParams(Id.wrap(MORPHO_MARKET_ID));
        bytes memory morphoFacilityData = morphoModule.encodeFacilityData(marketParams);
        box.addFundingInstant(morphoModule);
        box.addFundingCollateralInstant(morphoModule, ptSusde25Sep);
        box.addFundingDebtInstant(morphoModule, usdc);
        box.addFundingFacilityInstant(morphoModule, morphoFacilityData);

        vm.stopPrank();

        // Supply PT-sUSDe tokens for both protocols
        uint256 ptAmount = 2000 ether; // 2000 PT tokens total
        deal(address(ptSusde25Sep), address(box), ptAmount);

        // Fund Box with initial USDC
        deal(address(usdc), address(this), 1000e6);
        usdc.approve(address(box), 1000e6);
        box.deposit(1000e6, address(this));

        uint256 navBefore = box.totalAssets();
        console2.log("NAV before cross-protocol operations:", navBefore / 1e6, "USDC");

        vm.startPrank(allocator);

        // Supply 1000 PT to Aave
        uint256 aaveCollateralSupply = 1000 ether;
        box.pledge(aaveModule, aaveFacilityData, ptSusde25Sep, aaveCollateralSupply);
        console2.log("Supplied", aaveCollateralSupply / 1e18, "PT-sUSDe to Aave");

        // Supply 1000 PT to Morpho
        uint256 morphoCollateralSupply = 1000 ether;
        box.pledge(morphoModule, morphoFacilityData, ptSusde25Sep, morphoCollateralSupply);
        console2.log("Supplied", morphoCollateralSupply / 1e18, "PT-sUSDe to Morpho");

        // Check Aave collateral and borrow amount
        uint256 aaveCollateralBalance = aaveModule.collateralBalance(ptSusde25Sep);
        console2.log("Aave collateral balance:", aaveCollateralBalance / 1e18, "PT-sUSDe");

        // Borrow 500 USDC from Aave
        uint256 aaveBorrowAmount = 500e6;
        box.borrow(aaveModule, aaveFacilityData, usdc, aaveBorrowAmount);
        uint256 aaveLTVAfterBorrow = aaveModule.ltv(aaveFacilityData);
        console2.log("Borrowed", aaveBorrowAmount / 1e6, "USDC from Aave");
        console2.log("Aave LTV after borrow:", (aaveLTVAfterBorrow * 100) / 1e18, "%");

        // Check Morpho collateral and borrow amount
        uint256 morphoCollateralBalance = morphoModule.collateralBalance(ptSusde25Sep);
        console2.log("Morpho collateral balance:", morphoCollateralBalance / 1e18, "PT-sUSDe");

        // Borrow 600 USDC from Morpho
        uint256 morphoBorrowAmount = 600e6;
        box.borrow(morphoModule, morphoFacilityData, usdc, morphoBorrowAmount);
        uint256 morphoLTVAfterBorrow = morphoModule.ltv(morphoFacilityData);
        console2.log("Borrowed", morphoBorrowAmount / 1e6, "USDC from Morpho");
        console2.log("Morpho LTV after borrow:", (morphoLTVAfterBorrow * 100) / 1e18, "%");

        // Verify final state (LTV already calculated above)
        uint256 navAfter = box.totalAssets();

        console2.log("NAV after operations:", navAfter / 1e6, "USDC");
        console2.log("Final Aave LTV:", (aaveLTVAfterBorrow * 100) / 1e18, "%");
        console2.log("Final Morpho LTV:", (morphoLTVAfterBorrow * 100) / 1e18, "%");
        console2.log("Total borrowed:", (aaveBorrowAmount + morphoBorrowAmount) / 1e6, "USDC");

        // Verify NAV stability - borrowing assets at fair value should keep NAV constant
        assertApproxEqRel(navAfter, navBefore, 0.001e18, "NAV should remain approximately constant");

        // Verify both protocols show reasonable LTVs
        assertLt(aaveLTVAfterBorrow, 0.8e18, "Aave LTV should be under 80%");
        assertLt(morphoLTVAfterBorrow, 0.8e18, "Morpho LTV should be under 80%");

        // Verify we have the borrowed USDC
        uint256 totalExpected = 1000e6 + aaveBorrowAmount + morphoBorrowAmount;
        uint256 actualBalance = usdc.balanceOf(address(box));
        assertApproxEqAbs(actualBalance, totalExpected, 1e6, "Should have borrowed USDC plus initial deposit");

        vm.stopPrank();
    }
}
