// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Steakhouse Financial
pragma solidity 0.8.28;

import {IMorpho, Id, MarketParams, Position} from "@morpho-blue/interfaces/IMorpho.sol";
import "@morpho-blue/libraries/ConstantsLib.sol";
import {MarketParamsLib} from "@morpho-blue/libraries/MarketParamsLib.sol";
import {MorphoBalancesLib} from "@morpho-blue/libraries/periphery/MorphoBalancesLib.sol";
import {MorphoLib} from "@morpho-blue/libraries/periphery/MorphoLib.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {MathLib} from "./../lib/morpho-blue/src/libraries/MathLib.sol";
import {FundingBase} from "./FundingBase.sol";
import {IOracleCallback} from "./interfaces/IFunding.sol";
import {IOracle} from "./interfaces/IOracle.sol";
import {ErrorsLib} from "./libraries/ErrorsLib.sol";

contract FundingMorpho is FundingBase {
    using SafeERC20 for IERC20;
    using MarketParamsLib for MarketParams;
    using MorphoBalancesLib for IMorpho;
    using MorphoLib for IMorpho;
    using MathLib for uint256;
    using EnumerableSet for EnumerableSet.Bytes32Set;
    using EnumerableSet for EnumerableSet.AddressSet;

    IMorpho public immutable morpho;
    uint256 public immutable lltvCap; // Maximum LTV/LTTV ration in 18 decimals, e.g. 80e16 for 80%

    mapping(bytes32 => bytes) public facilityDataMap; // hash => facility data

    constructor(address owner_, address morpho_, uint256 lltvCap_) FundingBase(owner_) {
        require(morpho_ != address(0), ErrorsLib.InvalidAddress());
        require(lltvCap_ <= 100e16, ErrorsLib.InvalidValue()); // Max 100%
        require(lltvCap_ > 0, ErrorsLib.InvalidValue()); // Min above 0%

        morpho = IMorpho(morpho_);
        lltvCap = lltvCap_;
    }

    // ========== ADMIN ==========

    /// @dev Before adding a facility, you need to add the underlying tokens as collateral/debt tokens
    function addFacility(bytes calldata facilityData) external override {
        require(msg.sender == owner, ErrorsLib.OnlyOwner());

        MarketParams memory market = decodeFacilityData(facilityData);
        require(isCollateralToken(IERC20(market.collateralToken)), ErrorsLib.TokenNotWhitelisted());
        require(isDebtToken(IERC20(market.loanToken)), ErrorsLib.TokenNotWhitelisted());

        bytes32 facilityHash = keccak256(facilityData);
        require(facilitiesSet.add(facilityHash), ErrorsLib.AlreadyWhitelisted());
        facilityDataMap[facilityHash] = facilityData;
    }

    function removeFacility(bytes calldata facilityData) external override {
        require(msg.sender == owner, ErrorsLib.OnlyOwner());
        require(!_isFacilityUsed(facilityData), ErrorsLib.CannotRemove());

        bytes32 facilityHash = keccak256(facilityData);
        require(facilitiesSet.remove(facilityHash), ErrorsLib.NotWhitelisted());
        delete facilityDataMap[facilityHash];
    }

    function facilities(uint256 index) external view returns (bytes memory) {
        bytes32 facilityHash = facilitiesSet.at(index);
        return facilityDataMap[facilityHash];
    }

    /// @dev Before being able to remove a collateral, no facility should reference it and the balance should be 0
    function removeCollateralToken(IERC20 collateralToken) external override {
        require(msg.sender == owner, ErrorsLib.OnlyOwner());
        require(_collateralBalance(collateralToken) == 0, ErrorsLib.CannotRemove());

        uint256 length = facilitiesSet.length();
        for (uint i = 0; i < length; i++) {
            bytes32 facilityHash = facilitiesSet.at(i);
            MarketParams memory market = decodeFacilityData(facilityDataMap[facilityHash]);
            require(address(market.collateralToken) != address(collateralToken), ErrorsLib.CannotRemove());
        }

        require(collateralTokensSet.remove(address(collateralToken)), ErrorsLib.NotWhitelisted());
    }

    /// @dev Before being able to remove a debt, no facility should reference it and the balance should be 0
    function removeDebtToken(IERC20 debtToken) external override {
        require(msg.sender == owner, ErrorsLib.OnlyOwner());
        require(_debtBalance(debtToken) == 0, ErrorsLib.CannotRemove());

        uint256 length = facilitiesSet.length();
        for (uint i = 0; i < length; i++) {
            bytes32 facilityHash = facilitiesSet.at(i);
            MarketParams memory market = decodeFacilityData(facilityDataMap[facilityHash]);
            require(address(market.loanToken) != address(debtToken), ErrorsLib.CannotRemove());
        }

        require(debtTokensSet.remove(address(debtToken)), ErrorsLib.NotWhitelisted());
    }

    // ========== ACTIONS ==========

    /// @dev Assume caller did transfer the collateral tokens to this contract before calling
    function pledge(bytes calldata facilityData, IERC20 collateralToken, uint256 collateralAmount) external override {
        require(msg.sender == owner, ErrorsLib.OnlyOwner());
        require(isFacility(facilityData), ErrorsLib.NotWhitelisted());
        require(isCollateralToken(collateralToken), ErrorsLib.TokenNotWhitelisted());

        MarketParams memory market = decodeFacilityData(facilityData);
        require(address(collateralToken) == market.collateralToken, "FundingModuleMorpho: Wrong collateral token");

        collateralToken.forceApprove(address(morpho), collateralAmount);
        morpho.supplyCollateral(market, collateralAmount, address(this), "");
    }

    function depledge(bytes calldata facilityData, IERC20 collateralToken, uint256 collateralAmount) external override {
        require(msg.sender == owner, ErrorsLib.OnlyOwner());
        require(isFacility(facilityData), ErrorsLib.NotWhitelisted());
        require(isCollateralToken(collateralToken), ErrorsLib.TokenNotWhitelisted());

        MarketParams memory market = decodeFacilityData(facilityData);
        require(address(collateralToken) == market.collateralToken, "FundingModuleMorpho: Wrong collateral token");

        morpho.withdrawCollateral(market, collateralAmount, address(this), owner);

        require(ltv(facilityData) <= (market.lltv * lltvCap) / 100e16, ErrorsLib.ExcessiveLTV());
    }

    function borrow(bytes calldata facilityData, IERC20 debtToken, uint256 borrowAmount) external override {
        require(msg.sender == owner, ErrorsLib.OnlyOwner());
        require(isFacility(facilityData), ErrorsLib.NotWhitelisted());
        require(isDebtToken(debtToken), ErrorsLib.TokenNotWhitelisted());

        MarketParams memory market = decodeFacilityData(facilityData);
        require(address(debtToken) == market.loanToken, "FundingModuleMorpho: Wrong debt token");

        morpho.borrow(market, borrowAmount, 0, address(this), owner);

        require(ltv(facilityData) <= (market.lltv * lltvCap) / 100e16, ErrorsLib.ExcessiveLTV());
    }

    /// @dev Assume caller did transfer the debt tokens to this contract before calling
    function repay(bytes calldata facilityData, IERC20 debtToken, uint256 repayAmount) external override {
        require(msg.sender == owner, ErrorsLib.OnlyOwner());
        require(isFacility(facilityData), ErrorsLib.NotWhitelisted());
        require(isDebtToken(debtToken), ErrorsLib.TokenNotWhitelisted());

        MarketParams memory market = decodeFacilityData(facilityData);
        require(address(debtToken) == market.loanToken, "FundingModuleMorpho: Wrong debt token");

        uint256 debtAmount = morpho.expectedBorrowAssets(market, address(this));

        debtToken.forceApprove(address(morpho), repayAmount);

        // If the amount repaid is all the debt, we convert to all shares
        // amount repaid would internally get translated to more shares that there is to repaid
        if (repayAmount == debtAmount) {
            morpho.repay(market, 0, morpho.borrowShares(market.id(), address(this)), address(this), "");
        } else {
            morpho.repay(market, repayAmount, 0, address(this), "");
        }
    }

    // ========== POSITION ==========

    /// @dev returns 0 if there is no collateral
    function ltv(bytes calldata facilityData) public view override returns (uint256) {
        MarketParams memory market = decodeFacilityData(facilityData);
        Id marketId = market.id();
        uint256 borrowedAssets = morpho.expectedBorrowAssets(market, address(this));
        uint256 collateralAmount = morpho.collateral(marketId, address(this));
        if (collateralAmount == 0) return 0;
        require(market.oracle != address(0), ErrorsLib.NoOracleForToken());
        uint256 collateralPrice = IOracle(market.oracle).price();
        uint256 collateralValue = collateralAmount.mulDivDown(collateralPrice, ORACLE_PRICE_SCALE);
        return (collateralValue == 0) ? 0 : borrowedAssets.wDivUp(collateralValue);
    }

    function debtBalance(bytes calldata facilityData, IERC20 debtToken) external view override returns (uint256) {
        MarketParams memory market = decodeFacilityData(facilityData);
        require(address(debtToken) == market.loanToken, "FundingModuleMorpho: Wrong debt token");
        return morpho.expectedBorrowAssets(market, address(this));
    }

    function collateralBalance(bytes calldata facilityData, IERC20 collateralToken) external view override returns (uint256) {
        MarketParams memory market = decodeFacilityData(facilityData);
        require(address(collateralToken) == market.collateralToken, "FundingModuleMorpho: Wrong collateral token");
        return morpho.collateral(market.id(), address(this));
    }

    /// @dev The NAV for a given lending market can be negative but there is no recourse so it can be floored to 0.
    function nav(IOracleCallback oraclesProvider) public view override returns (uint256) {
        uint256 nav_ = 0;
        address asset = oraclesProvider.asset();
        uint256 length = facilitiesSet.length();
        for (uint256 i = 0; i < length; i++) {
            uint256 facilityNav = 0;
            bytes32 facilityHash = facilitiesSet.at(i);
            MarketParams memory market = decodeFacilityData(facilityDataMap[facilityHash]);
            uint256 collateralBalance_ = morpho.collateral(market.id(), address(this));

            if (collateralBalance_ == 0) continue; // No debt if no collateral

            if (market.collateralToken == asset) {
                // RIs are considered to have a price of ORACLE_PRECISION
                facilityNav += collateralBalance_;
            } else {
                IOracle oracle = oraclesProvider.oracles(IERC20(market.collateralToken));
                facilityNav += collateralBalance_.mulDivDown(oracle.price(), ORACLE_PRICE_SCALE);
            }

            uint256 debtBalance_ = morpho.expectedBorrowAssets(market, address(this));

            if (market.loanToken == asset) {
                facilityNav = (facilityNav > debtBalance_) ? facilityNav - debtBalance_ : 0;
            } else {
                IOracle oracle = oraclesProvider.oracles(IERC20(market.loanToken));
                uint256 value = debtBalance_.mulDivUp(oracle.price(), ORACLE_PRICE_SCALE);
                facilityNav = (facilityNav > value) ? facilityNav - value : 0;
            }

            nav_ += facilityNav;
        }
        return nav_;
    }

    // ========== Other exposed view functions ==========

    function decodeFacilityData(bytes memory facilityData) public pure returns (MarketParams memory market) {
        // MarketParams has 4 addresses (32 bytes each) + 1 uint256 (32 bytes) = 160 bytes
        require(facilityData.length == 160, ErrorsLib.InvalidFacilityData());
        (MarketParams memory marketParams) = abi.decode(facilityData, (MarketParams));
        return (marketParams);
    }

    function encodeFacilityData(MarketParams memory market) public pure returns (bytes memory) {
        return abi.encode(market);
    }

    // ========== Internal functions ==========
    function _debtBalance(IERC20 debtToken) internal view override returns (uint256 balance) {
        uint256 length = facilitiesSet.length();
        for (uint256 i = 0; i < length; i++) {
            bytes32 facilityHash = facilitiesSet.at(i);
            MarketParams memory market = decodeFacilityData(facilityDataMap[facilityHash]);
            if (address(debtToken) == market.loanToken) {
                balance += morpho.expectedBorrowAssets(market, address(this));
            }
        }
    }

    function _collateralBalance(IERC20 collateralToken) internal view override returns (uint256 balance) {
        uint256 length = facilitiesSet.length();
        for (uint256 i = 0; i < length; i++) {
            bytes32 facilityHash = facilitiesSet.at(i);
            MarketParams memory market = decodeFacilityData(facilityDataMap[facilityHash]);
            if (address(collateralToken) == market.collateralToken) {
                balance += morpho.collateral(market.id(), address(this));
            }
        }
    }

    function _isFacilityUsed(bytes calldata facilityData) internal view override returns (bool) {
        MarketParams memory market = decodeFacilityData(facilityData);
        Position memory position = morpho.position(market.id(), address(this));
        return position.collateral > 0 || position.borrowShares > 0;
    }
}
