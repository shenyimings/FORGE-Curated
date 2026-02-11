// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Dependency imports
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

// Internal imports
import {ILeverageManager} from "src/interfaces/ILeverageManager.sol";

contract MockLendingAdapter {
    uint256 public constant BASE_EXCHANGE_RATE = 1e8;

    ERC20Mock public collateralAsset;
    ERC20Mock public debtAsset;

    uint256 public collateralToDebtAssetExchangeRate;

    uint256 public debt;

    address public authorizedCreator;

    constructor(address _collateralAsset, address _debtAsset, address _authorizedCreator) {
        collateralAsset = ERC20Mock(_collateralAsset);
        debtAsset = ERC20Mock(_debtAsset);
        authorizedCreator = _authorizedCreator;

        // collateral:debt is 1:1 by default
        collateralToDebtAssetExchangeRate = BASE_EXCHANGE_RATE;
    }

    function getCollateralAsset() external view returns (IERC20) {
        return collateralAsset;
    }

    function getDebtAsset() external view returns (IERC20) {
        return debtAsset;
    }

    function convertCollateralToDebtAsset(uint256 amount) external view returns (uint256) {
        return collateralToDebtAssetExchangeRate > 0
            ? Math.mulDiv(amount, collateralToDebtAssetExchangeRate, BASE_EXCHANGE_RATE, Math.Rounding.Floor)
            : amount;
    }

    function convertDebtToCollateralAsset(uint256 amount) public view returns (uint256) {
        return collateralToDebtAssetExchangeRate > 0
            ? Math.mulDiv(amount, BASE_EXCHANGE_RATE, collateralToDebtAssetExchangeRate, Math.Rounding.Ceil)
            : amount;
    }

    function getEquityInCollateralAsset() external view returns (uint256) {
        uint256 collateral = getCollateral();
        uint256 debtInCollateralAsset = convertDebtToCollateralAsset(getDebt());
        return collateral > debtInCollateralAsset ? collateral - debtInCollateralAsset : 0;
    }

    function getEquityInDebtAsset() external view returns (uint256) {
        uint256 collateralInDebtAsset = getCollateralInDebtAsset();
        uint256 _debt = getDebt();
        return collateralInDebtAsset > _debt ? collateralInDebtAsset - _debt : 0;
    }

    function getCollateral() public view returns (uint256) {
        return collateralAsset.balanceOf(address(this));
    }

    function getCollateralInDebtAsset() public view returns (uint256) {
        return collateralAsset.balanceOf(address(this)) * collateralToDebtAssetExchangeRate / BASE_EXCHANGE_RATE;
    }

    function getDebt() public view returns (uint256) {
        return debt;
    }

    function preLeverageTokenCreation(address /* creator */ ) external {}

    function addCollateral(uint256 amount) external {
        SafeERC20.safeTransferFrom(collateralAsset, msg.sender, address(this), amount);
    }

    function removeCollateral(uint256 amount) external {
        SafeERC20.safeTransfer(collateralAsset, msg.sender, amount);
    }

    function borrow(uint256 amount) external {
        debt += amount;
        debtAsset.mint(msg.sender, amount);
    }

    function repay(uint256 amount) external {
        debt -= amount;
        SafeERC20.safeTransferFrom(debtAsset, msg.sender, address(this), amount);
    }

    function mockCollateral(uint256 amount) external {
        collateralAsset.mint(address(this), amount);
    }

    function mockDebt(uint256 amount) external {
        debt = amount;
    }

    function mockConvertCollateralToDebtAssetExchangeRate(uint256 exchangeRate) external {
        collateralToDebtAssetExchangeRate = exchangeRate;
    }
}
