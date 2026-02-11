// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Steakhouse Financial
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {FundingMorpho} from "../src/FundingMorpho.sol";
import {IMorpho, MarketParams, Position} from "@morpho-blue/interfaces/IMorpho.sol";
import {Morpho} from "@morpho-blue/Morpho.sol";
import {IrmMock} from "@morpho-blue/mocks/IrmMock.sol";
import {OracleMock} from "@morpho-blue/mocks/OracleMock.sol";
import {ERC20MockDecimals} from "./mocks/ERC20MockDecimals.sol";
import {ErrorsLib} from "../src/libraries/ErrorsLib.sol";

contract FundingMorphoTest is Test {
    FundingMorpho fundingMorpho;
    IMorpho morpho;
    address owner = address(0x123);
    address nonOwner = address(0x456);

    ERC20MockDecimals collateralToken;
    ERC20MockDecimals collateral2Token;
    ERC20MockDecimals debtToken;
    ERC20MockDecimals debt2Token;

    uint256 lltv80 = 800000000000000000;
    uint256 lltv90 = 900000000000000000;

    OracleMock oracle;

    MarketParams marketParamsLtv80;
    MarketParams marketParamsLtv90;

    address irm;

    bytes facilityDataLtv80;
    bytes facilityDataLtv90;

    function setUp() public {
        // Deploy a mock Morpho contract
        morpho = IMorpho(address(new Morpho(address(this))));

        collateralToken = new ERC20MockDecimals(18);
        collateralToken.mint(address(this), 10 ether);
        collateralToken.approve(address(morpho), 10 ether);
        collateral2Token = new ERC20MockDecimals(6);
        collateral2Token.mint(address(this), 10 ether);
        collateral2Token.approve(address(morpho), 10 ether);
        debtToken = new ERC20MockDecimals(18);
        debtToken.mint(address(this), 10 ether);
        debtToken.approve(address(morpho), 10 ether);
        debt2Token = new ERC20MockDecimals(6);
        debt2Token.mint(address(this), 10 ether);
        debt2Token.approve(address(morpho), 10 ether);

        irm = address(new IrmMock());

        morpho.enableIrm(irm);
        morpho.enableLltv(lltv80);
        morpho.enableLltv(lltv90);

        oracle = new OracleMock();
        oracle.setPrice(1e36);

        // Create a 80% lltv market and seed it
        marketParamsLtv80 = MarketParams(address(debtToken), address(collateralToken), address(oracle), address(irm), lltv80);
        morpho.createMarket(marketParamsLtv80);
        morpho.supplyCollateral(marketParamsLtv80, 1 ether, address(this), "");
        morpho.supply(marketParamsLtv80, 1 ether, 0, address(this), "");
        morpho.borrow(marketParamsLtv80, 0.5 ether, 0, address(this), address(this));
        facilityDataLtv80 = abi.encode(marketParamsLtv80);

        // Create a 90% lltv market and seed it
        marketParamsLtv90 = MarketParams(address(debtToken), address(collateralToken), address(oracle), address(irm), lltv90);
        morpho.createMarket(marketParamsLtv90);
        morpho.supplyCollateral(marketParamsLtv90, 1 ether, address(this), "");
        morpho.supply(marketParamsLtv90, 1 ether, 0, address(this), "");
        morpho.borrow(marketParamsLtv90, 0.5 ether, 0, address(this), address(this));
        facilityDataLtv90 = abi.encode(marketParamsLtv90);

        // Deploy the FundingMorpho contract
        fundingMorpho = new FundingMorpho(owner, address(morpho), 99e16);

        vm.startPrank(owner);
        fundingMorpho.addCollateralToken(collateralToken);
        fundingMorpho.addDebtToken(debtToken);
        fundingMorpho.addFacility(facilityDataLtv80);
        fundingMorpho.addFacility(facilityDataLtv90);
        vm.stopPrank();
    }

    /// @dev Ensure test setup was as expected
    function testSetup() public view {
        assertEq(fundingMorpho.facilitiesLength(), 2);
        assertTrue(fundingMorpho.isFacility(facilityDataLtv80));
        assertTrue(fundingMorpho.isFacility(facilityDataLtv90));

        assertEq(fundingMorpho.collateralTokensLength(), 1);
        assertTrue(fundingMorpho.isCollateralToken(collateralToken));
        assertEq(fundingMorpho.collateralBalance(facilityDataLtv80, collateralToken), 0 ether);
        assertEq(fundingMorpho.collateralBalance(collateralToken), 0 ether);

        assertEq(fundingMorpho.debtTokensLength(), 1);
        assertTrue(fundingMorpho.isDebtToken(debtToken));
        assertEq(fundingMorpho.debtBalance(facilityDataLtv80, debtToken), 0 ether);
        assertEq(fundingMorpho.debtBalance(debtToken), 0 ether);

        // When no collateral ltv is 0%
        assertEq(fundingMorpho.ltv(facilityDataLtv80), 0);
    }

    function testCreation(address owner_, address morpho_, uint256 lltvCap) public {
        vm.assume(owner_ != address(0));
        vm.assume(morpho_ != address(0));
        vm.assume(lltvCap > 0 && lltvCap <= 1e18);
        FundingMorpho fundingMorphoLocal = new FundingMorpho(owner_, morpho_, lltvCap);
        assertEq(fundingMorphoLocal.owner(), owner_);
        assertEq(address(fundingMorphoLocal.morpho()), morpho_);
        assertEq(fundingMorphoLocal.lltvCap(), lltvCap);
    }

    function testBadCreation() public {
        vm.expectRevert(ErrorsLib.InvalidValue.selector);
        FundingMorpho fundingMorphoLocal = new FundingMorpho(owner, address(morpho), 101e16);

        vm.expectRevert(ErrorsLib.InvalidValue.selector);
        fundingMorphoLocal = new FundingMorpho(owner, address(morpho), 0);

        vm.expectRevert(ErrorsLib.InvalidAddress.selector);
        fundingMorphoLocal = new FundingMorpho(address(0), address(morpho), 50e16);

        vm.expectRevert(ErrorsLib.InvalidAddress.selector);
        fundingMorphoLocal = new FundingMorpho(owner, address(0), 50e16);
    }

    /// @dev Test a simple funding cycle
    function testSimpleCycle() public {
        vm.startPrank(owner);

        collateralToken.mint(address(owner), 1 ether);

        // ========== Invalid operations ==========

        // Revert because collateral wasn't transferred to the contract
        vm.expectRevert();
        fundingMorpho.pledge(facilityDataLtv80, collateralToken, 1 ether);

        // Can't borrow without collateral
        vm.expectRevert();
        fundingMorpho.borrow(facilityDataLtv80, debtToken, 0.5 ether);

        // Can't withdraw without collateral
        vm.expectRevert();
        fundingMorpho.depledge(facilityDataLtv80, collateralToken, 1 ether);

        // Can't repay without debt
        vm.expectRevert();
        fundingMorpho.repay(facilityDataLtv80, debtToken, 0.5 ether);

        // ========== Valid cycle ==========

        // Deposit collateral
        collateralToken.transfer(address(fundingMorpho), 1 ether);
        fundingMorpho.pledge(facilityDataLtv80, collateralToken, 1 ether);

        assertEq(fundingMorpho.collateralBalance(facilityDataLtv80, collateralToken), 1 ether);
        assertEq(fundingMorpho.ltv(facilityDataLtv80), 0);

        // Borrow some debt
        fundingMorpho.borrow(facilityDataLtv80, debtToken, 0.5 ether);

        assertEq(fundingMorpho.debtBalance(facilityDataLtv80, debtToken), 0.5 ether);
        assertEq(fundingMorpho.ltv(facilityDataLtv80), 0.5 ether);

        // Repay part of the debt, but forget to send debt tokens first
        vm.expectRevert();
        fundingMorpho.repay(facilityDataLtv80, debtToken, 0.25 ether);

        // Repay part of the debt
        debtToken.transfer(address(fundingMorpho), 0.25 ether);
        fundingMorpho.repay(facilityDataLtv80, debtToken, 0.25 ether);

        assertEq(fundingMorpho.debtBalance(facilityDataLtv80, debtToken), 0.25 ether);
        assertEq(fundingMorpho.ltv(facilityDataLtv80), 0.25 ether);

        // Withdrawing too much would revert
        vm.expectRevert();
        fundingMorpho.depledge(facilityDataLtv80, collateralToken, 10 ether);

        // Repay the rest of the debt
        debtToken.transfer(address(fundingMorpho), 0.25 ether);
        fundingMorpho.repay(facilityDataLtv80, debtToken, fundingMorpho.debtBalance(facilityDataLtv80, debtToken));

        assertEq(fundingMorpho.debtBalance(facilityDataLtv80, debtToken), 0);
        assertEq(fundingMorpho.ltv(facilityDataLtv80), 0);

        // Withdraw part of the collateral
        fundingMorpho.depledge(facilityDataLtv80, collateralToken, 0.5 ether);
        assertEq(fundingMorpho.collateralBalance(facilityDataLtv80, collateralToken), 0.5 ether);
        assertEq(collateralToken.balanceOf(address(owner)), 0.5 ether);

        // Withdraw the rest of the collateral
        fundingMorpho.depledge(facilityDataLtv80, collateralToken, 0.5 ether);
        assertEq(fundingMorpho.collateralBalance(facilityDataLtv80, collateralToken), 0);
        assertEq(collateralToken.balanceOf(address(owner)), 1 ether);

        vm.stopPrank();
    }

    function testOnlyOwner() public {
        vm.expectRevert(ErrorsLib.OnlyOwner.selector);
        fundingMorpho.addFacility(facilityDataLtv80);

        vm.expectRevert(ErrorsLib.OnlyOwner.selector);
        fundingMorpho.removeFacility(facilityDataLtv80);

        vm.expectRevert(ErrorsLib.OnlyOwner.selector);
        fundingMorpho.addCollateralToken(collateralToken);

        vm.expectRevert(ErrorsLib.OnlyOwner.selector);
        fundingMorpho.removeCollateralToken(collateralToken);

        vm.expectRevert(ErrorsLib.OnlyOwner.selector);
        fundingMorpho.addDebtToken(debtToken);

        vm.expectRevert(ErrorsLib.OnlyOwner.selector);
        fundingMorpho.removeDebtToken(debtToken);

        vm.expectRevert(ErrorsLib.OnlyOwner.selector);
        fundingMorpho.pledge(facilityDataLtv80, collateralToken, 1 ether);

        vm.expectRevert(ErrorsLib.OnlyOwner.selector);
        fundingMorpho.depledge(facilityDataLtv80, collateralToken, 1 ether);

        vm.expectRevert(ErrorsLib.OnlyOwner.selector);
        fundingMorpho.borrow(facilityDataLtv80, debtToken, 1 ether);

        vm.expectRevert(ErrorsLib.OnlyOwner.selector);
        fundingMorpho.repay(facilityDataLtv80, debtToken, 1 ether);
    }

    function testCleanFundingModule() public {
        // Setup
        collateralToken.mint(address(fundingMorpho), 1 ether);

        vm.startPrank(owner);
        fundingMorpho.pledge(facilityDataLtv80, collateralToken, 1 ether);
        fundingMorpho.borrow(facilityDataLtv80, debtToken, 0.5 ether);

        // Can't remove facility while it has activity
        vm.expectRevert(ErrorsLib.CannotRemove.selector);
        fundingMorpho.removeFacility(facilityDataLtv80);

        // This one should work as there is no activity
        fundingMorpho.removeFacility(facilityDataLtv90);

        vm.expectRevert(ErrorsLib.CannotRemove.selector);
        fundingMorpho.removeCollateralToken(collateralToken);

        vm.expectRevert(ErrorsLib.CannotRemove.selector);
        fundingMorpho.removeDebtToken(debtToken);

        debtToken.transfer(address(fundingMorpho), fundingMorpho.debtBalance(facilityDataLtv80, debtToken));
        fundingMorpho.repay(facilityDataLtv80, debtToken, fundingMorpho.debtBalance(facilityDataLtv80, debtToken));
        fundingMorpho.depledge(facilityDataLtv80, collateralToken, fundingMorpho.collateralBalance(facilityDataLtv80, collateralToken));

        assertEq(fundingMorpho.collateralBalance(facilityDataLtv80, collateralToken), 0 ether);
        assertEq(fundingMorpho.debtBalance(facilityDataLtv80, debtToken), 0 ether);

        // Remove facilities and tokens
        fundingMorpho.removeFacility(facilityDataLtv80);
        fundingMorpho.removeCollateralToken(collateralToken);
        fundingMorpho.removeDebtToken(debtToken);

        assertEq(fundingMorpho.facilitiesLength(), 0);
        assertEq(fundingMorpho.collateralTokensLength(), 0);
        assertEq(fundingMorpho.debtTokensLength(), 0);

        vm.stopPrank();
    }

    function testLtvTooHigh() public {
        vm.startPrank(owner);

        collateralToken.mint(address(owner), 1 ether);

        // Deposit collateral
        collateralToken.transfer(address(fundingMorpho), 1 ether);
        fundingMorpho.pledge(facilityDataLtv80, collateralToken, 0.1 ether);

        // Borrow some debt too close from the 80% LLTV
        vm.expectRevert("insufficient collateral");
        fundingMorpho.borrow(facilityDataLtv80, debtToken, 0.08 ether + 1);

        // Borrow some debt too close from the 80% LLTV
        vm.expectRevert(ErrorsLib.ExcessiveLTV.selector);
        fundingMorpho.borrow(facilityDataLtv80, debtToken, 0.08 ether);

        fundingMorpho.borrow(facilityDataLtv80, debtToken, (0.08 ether * fundingMorpho.lltvCap()) / 1e18);
    }

    /// @dev Test for audit issue 5.6: Ensure token parameters match the market's actual tokens
    function testTokenParameterValidation() public {
        // Setup: whitelist a second collateral token
        vm.startPrank(owner);
        fundingMorpho.addCollateralToken(collateral2Token);

        // Create a market with collateralToken but we'll try to use collateral2Token parameter
        collateralToken.mint(address(fundingMorpho), 1 ether);

        // Test pledge: should revert when using wrong collateral token parameter
        vm.expectRevert("FundingModuleMorpho: Wrong collateral token");
        fundingMorpho.pledge(facilityDataLtv80, collateral2Token, 1 ether);

        // Correct pledge should work
        fundingMorpho.pledge(facilityDataLtv80, collateralToken, 1 ether);

        // Test depledge: should revert when using wrong collateral token parameter
        vm.expectRevert("FundingModuleMorpho: Wrong collateral token");
        fundingMorpho.depledge(facilityDataLtv80, collateral2Token, 0.5 ether);

        // Correct depledge should work
        fundingMorpho.depledge(facilityDataLtv80, collateralToken, 0.5 ether);

        // Setup for debt token tests: whitelist a second debt token
        fundingMorpho.addDebtToken(debt2Token);

        // Test borrow: should revert when using wrong debt token parameter
        vm.expectRevert("FundingModuleMorpho: Wrong debt token");
        fundingMorpho.borrow(facilityDataLtv80, debt2Token, 0.1 ether);

        // Correct borrow should work
        fundingMorpho.borrow(facilityDataLtv80, debtToken, 0.1 ether);

        // Test repay: should revert when using wrong debt token parameter
        debt2Token.mint(address(fundingMorpho), 0.1 ether);
        vm.expectRevert("FundingModuleMorpho: Wrong debt token");
        fundingMorpho.repay(facilityDataLtv80, debt2Token, 0.1 ether);

        // Correct repay should work
        debtToken.transfer(address(fundingMorpho), 0.1 ether);
        fundingMorpho.repay(facilityDataLtv80, debtToken, 0.1 ether);

        vm.stopPrank();
    }
}
