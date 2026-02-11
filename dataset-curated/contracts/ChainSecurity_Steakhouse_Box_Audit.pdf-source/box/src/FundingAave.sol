// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2025 Steakhouse Financial
pragma solidity 0.8.28;

import "@morpho-blue/libraries/ConstantsLib.sol";
import {MathLib} from "@morpho-blue/libraries/MathLib.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {FundingBase} from "./FundingBase.sol";
import {IOracleCallback} from "./interfaces/IFunding.sol";
import {IOracle} from "./interfaces/IOracle.sol";
import {ErrorsLib} from "./libraries/ErrorsLib.sol";

interface IPool {
    function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;
    function withdraw(address asset, uint256 amount, address to) external returns (uint256);
    function borrow(address asset, uint256 amount, uint256 interestRateMode, uint16 referralCode, address onBehalfOf) external;
    function repay(address asset, uint256 amount, uint256 interestRateMode, address onBehalfOf) external returns (uint256);
    function setUserUseReserveAsCollateral(address asset, bool useAsCollateral) external;
    function setUserEMode(uint8 categoryId) external;
    function getUserEMode(address user) external view returns (uint256);
    function getEModeCategoryData(
        uint8 categoryId
    ) external view returns (uint16 ltv, uint16 liquidationThreshold, uint16 liquidationBonus, address priceSource, string memory label);
    function getReserveEModeCategory(address asset) external view returns (uint256);

    function getUserAccountData(
        address user
    )
        external
        view
        returns (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            uint256 availableBorrowsBase,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        );

    function getReserveData(
        address asset
    )
        external
        view
        returns (
            uint256 configuration,
            uint128 liquidityIndex,
            uint128 currentLiquidityRate,
            uint128 variableBorrowIndex,
            uint128 currentVariableBorrowRate,
            uint128 currentStableBorrowRate,
            uint40 lastUpdateTimestamp,
            uint16 id,
            address aTokenAddress,
            address stableDebtTokenAddress,
            address variableDebtTokenAddress,
            address interestRateStrategyAddress,
            uint128 accruedToTreasury,
            uint128 unbacked,
            uint128 isolationModeTotalDebt
        );

    function getReserveNormalizedVariableDebt(address asset) external view returns (uint256);
}

interface IScaledBalanceToken {
    function scaledBalanceOf(address user) external view returns (uint256);
}

contract FundingAave is FundingBase {
    using SafeERC20 for IERC20;
    using MathLib for uint256;
    using Math for uint256;
    using EnumerableSet for EnumerableSet.Bytes32Set;
    using EnumerableSet for EnumerableSet.AddressSet;

    IPool public immutable pool;
    uint256 public immutable rateMode = 2; // 1 = Stable, 2 = Variable (Aave v3 constant)
    uint8 public immutable eMode; // 0 = no e-mode

    constructor(address _owner, IPool _pool, uint8 _eMode) FundingBase(_owner) {
        pool = _pool;
        eMode = _eMode;
        if (pool.getUserEMode(address(this)) != eMode) {
            pool.setUserEMode(eMode);
        }
    }

    // ========== ADMIN ==========

    /// @dev FundingAave always expect "" as facilityData
    function addFacility(bytes calldata facilityData) external override {
        require(msg.sender == owner, ErrorsLib.OnlyOwner());
        require(facilityData.length == 0, ErrorsLib.InvalidValue());

        bytes32 facilityHash = keccak256(facilityData);
        require(facilitiesSet.add(facilityHash), ErrorsLib.AlreadyWhitelisted());
    }

    function removeFacility(bytes calldata facilityData) external override {
        require(msg.sender == owner, ErrorsLib.OnlyOwner());
        require(!_isFacilityUsed(facilityData), ErrorsLib.CannotRemove());

        bytes32 facilityHash = keccak256(facilityData);
        require(facilitiesSet.remove(facilityHash), ErrorsLib.NotWhitelisted());
    }

    function facilities(uint256 index) external view returns (bytes memory) {
        // Validate index to be consistent with FundingMorpho behavior (reverts on invalid index)
        facilitiesSet.at(index);
        // For FundingAave, facilities are always empty bytes
        return "";
    }

    function removeCollateralToken(IERC20 collateralToken) external override {
        require(msg.sender == owner, ErrorsLib.OnlyOwner());
        require(_collateralBalance(collateralToken) == 0, ErrorsLib.CannotRemove());
        require(collateralTokensSet.remove(address(collateralToken)), ErrorsLib.NotWhitelisted());
    }

    function removeDebtToken(IERC20 debtToken) external override {
        require(msg.sender == owner, ErrorsLib.OnlyOwner());
        require(_debtBalance(debtToken) == 0, ErrorsLib.CannotRemove());
        require(debtTokensSet.remove(address(debtToken)), ErrorsLib.NotWhitelisted());
    }

    // ========== ACTIONS ==========

    /// @dev Assume caller did transfer the collateral tokens to this contract before calling
    function pledge(bytes calldata facilityData, IERC20 collateralToken, uint256 collateralAmount) external override {
        require(msg.sender == owner, ErrorsLib.OnlyOwner());
        require(isFacility(facilityData), ErrorsLib.NotWhitelisted());
        require(isCollateralToken(collateralToken), ErrorsLib.TokenNotWhitelisted());

        IERC20(collateralToken).forceApprove(address(pool), collateralAmount);
        pool.supply(address(collateralToken), collateralAmount, address(this), 0);
        pool.setUserUseReserveAsCollateral(address(collateralToken), true);
    }

    function depledge(bytes calldata facilityData, IERC20 collateralToken, uint256 collateralAmount) external override {
        require(msg.sender == owner, ErrorsLib.OnlyOwner());
        require(isFacility(facilityData), ErrorsLib.NotWhitelisted());
        require(isCollateralToken(collateralToken), ErrorsLib.TokenNotWhitelisted());

        pool.withdraw(address(collateralToken), collateralAmount, owner);
    }

    function borrow(bytes calldata facilityData, IERC20 debtToken, uint256 borrowAmount) external override {
        require(msg.sender == owner, ErrorsLib.OnlyOwner());
        require(isFacility(facilityData), ErrorsLib.NotWhitelisted());
        require(isDebtToken(debtToken), ErrorsLib.TokenNotWhitelisted());

        pool.borrow(address(debtToken), borrowAmount, rateMode, 0, address(this));
        debtToken.safeTransfer(owner, borrowAmount);
    }

    /// @dev Assume caller did transfer the debt tokens to this contract before calling
    function repay(bytes calldata facilityData, IERC20 debtToken, uint256 repayAmount) external override {
        require(msg.sender == owner, ErrorsLib.OnlyOwner());
        require(isFacility(facilityData), ErrorsLib.NotWhitelisted());
        require(isDebtToken(debtToken), ErrorsLib.TokenNotWhitelisted());

        debtToken.forceApprove(address(pool), repayAmount);
        uint256 actualRepaid = pool.repay(address(debtToken), repayAmount, rateMode, address(this));

        if (actualRepaid < repayAmount) {
            debtToken.safeTransfer(owner, repayAmount - actualRepaid);
        }
    }

    // ========== POSITION ==========

    /// @dev ltv can also use non whitelisted collaterals (donated)
    /// @dev returns 0 if there is no collateral
    function ltv(bytes calldata data) external view override returns (uint256) {
        (uint256 totalCollateralBase, uint256 totalDebtBase, , , , ) = pool.getUserAccountData(address(this));

        return totalCollateralBase == 0 ? 0 : totalDebtBase.wDivUp(totalCollateralBase);
    }

    function debtBalance(bytes calldata facilityData, IERC20 debtToken) external view override returns (uint256) {
        return _debtBalance(debtToken);
    }

    function collateralBalance(bytes calldata facilityData, IERC20 collateralToken) external view override returns (uint256) {
        return _collateralBalance(collateralToken);
    }

    /// @dev The NAV for a given lending market can be negative but there is no recourse so it can be floored to 0.
    function nav(IOracleCallback oraclesProvider) public view override returns (uint256) {
        uint256 totalCollateralValue;
        uint256 totalDebtValue;
        address asset = oraclesProvider.asset();

        // Calculate total collateral value
        uint256 collateralLength = collateralTokensSet.length();
        for (uint256 i = 0; i < collateralLength; i++) {
            IERC20 collateralToken = IERC20(collateralTokensSet.at(i));
            uint256 collateralBalance_ = _collateralBalance(collateralToken);

            if (collateralBalance_ > 0) {
                if (address(collateralToken) == asset) {
                    totalCollateralValue += collateralBalance_;
                } else {
                    IOracle oracle = oraclesProvider.oracles(collateralToken);
                    uint256 price = oracle.price();
                    uint256 value = collateralBalance_.mulDivDown(price, ORACLE_PRICE_SCALE);
                    totalCollateralValue += value;
                }
            }
        }

        // Calculate total debt value
        uint256 debtLength = debtTokensSet.length();
        for (uint256 i = 0; i < debtLength; i++) {
            IERC20 debtToken = IERC20(debtTokensSet.at(i));
            uint256 debtBalance_ = _debtBalance(debtToken);

            if (debtBalance_ > 0) {
                if (address(debtToken) == asset) {
                    totalDebtValue += debtBalance_;
                } else {
                    IOracle oracle = oraclesProvider.oracles(debtToken);
                    uint256 price = oracle.price();
                    uint256 value = debtBalance_.mulDivUp(price, ORACLE_PRICE_SCALE);
                    totalDebtValue += value;
                }
            }
        }

        // Return NAV = collateral - debt (floor at 0)
        if (totalCollateralValue <= totalDebtValue) return 0;
        unchecked {
            return totalCollateralValue - totalDebtValue;
        }
    }

    function _debtBalance(IERC20 debtToken) internal view override returns (uint256 balance) {
        (, , , , , , , , , , address variableDebtToken, , , , ) = pool.getReserveData(address(debtToken));
        return IERC20(variableDebtToken).balanceOf(address(this));
    }

    function _collateralBalance(IERC20 collateralToken) internal view override returns (uint256 balance) {
        (, , , , , , , , address aTokenAddress, , , , , , ) = pool.getReserveData(address(collateralToken));
        return IERC20(aTokenAddress).balanceOf(address(this));
    }

    function _isFacilityUsed(bytes calldata facilityData) internal view override returns (bool) {
        (uint256 totalCollateralBase, uint256 totalDebtBase, , , , ) = pool.getUserAccountData(address(this));

        return totalCollateralBase > 0 || totalDebtBase > 0;
    }
}
