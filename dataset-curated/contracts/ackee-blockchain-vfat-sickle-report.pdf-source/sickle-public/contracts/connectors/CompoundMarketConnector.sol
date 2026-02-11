// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { ILendingConnector } from "contracts/interfaces/ILendingConnector.sol";
import {
    CTokenInterface,
    CErc20Interface,
    ComptrollerInterface
} from "contracts/interfaces/external/compound-v2/CTokenInterfaces.sol";
import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract CompoundMarketConnector is ILendingConnector {
    error CompoundActionFailed(string action, uint256 errorCode);

    function mint(
        address target,
        uint256 amount,
        bytes memory // extraData
    ) external payable override {
        CErc20Interface cToken = CErc20Interface(target);
        SafeTransferLib.safeApprove(cToken.underlying(), target, amount);
        uint256 error = cToken.mint(amount);
        if (error != 0) {
            revert CompoundActionFailed("mint", error);
        }

        address[] memory markets = new address[](1);
        markets[0] = target;
        uint256[] memory results = ComptrollerInterface(
            CTokenInterface(target).comptroller()
        ).enterMarkets(markets);
        if (results[0] != 0) {
            revert CompoundActionFailed("enterMarkets", results[0]);
        }
    }

    function redeem(
        address target,
        uint256 amount,
        bytes memory // extraData
    ) external override {
        if (amount == type(uint256).max) {
            amount = IERC20(target).balanceOf(address(this));
        }
        CErc20Interface cToken = CErc20Interface(target);
        uint256 result = cToken.redeem(amount);
        if (result != 0) {
            revert CompoundActionFailed("redeem", result);
        }
        if (IERC20(target).balanceOf(address(this)) == 0) {
            result = ComptrollerInterface(CTokenInterface(target).comptroller())
                .exitMarket(target);
            if (result != 0) {
                revert CompoundActionFailed("exitMarket", result);
            }
        }
    }

    function redeemUnderlying(
        address target,
        uint256 amount,
        bytes memory // extraData
    ) external override {
        CErc20Interface cToken = CErc20Interface(target);
        uint256 result = cToken.redeemUnderlying(amount);
        if (result != 0) {
            revert CompoundActionFailed("redeemUnderlying", result);
        }
        if (IERC20(target).balanceOf(address(this)) == 0) {
            result = ComptrollerInterface(CTokenInterface(target).comptroller())
                .exitMarket(target);
            if (result != 0) {
                revert CompoundActionFailed("exitMarket", result);
            }
        }
    }

    function borrow(
        address target,
        uint256 amount,
        bytes memory // extraData
    ) external payable override {
        CErc20Interface cToken = CErc20Interface(target);
        uint256 result = cToken.borrow(amount);
        if (result != 0) {
            revert CompoundActionFailed("borrow", result);
        }
    }

    function repay(
        address target,
        uint256 amount,
        bytes memory // extraData
    ) external payable override {
        CErc20Interface cToken = CErc20Interface(target);
        SafeTransferLib.safeApprove(cToken.underlying(), target, amount);
        uint256 result = cToken.repayBorrow(amount);
        if (result != 0) {
            revert CompoundActionFailed("repayBorrow", result);
        }
        if (amount == type(uint256).max) {
            SafeTransferLib.safeApprove(cToken.underlying(), target, 0);
        }
    }

    function repayFor(
        address target,
        address borrower,
        uint256 amount,
        bytes memory // extraData
    ) external payable override {
        if (amount == 0) amount = type(uint256).max;
        CErc20Interface cToken = CErc20Interface(target);
        SafeTransferLib.safeApprove(cToken.underlying(), target, amount);
        uint256 result = cToken.repayBorrowBehalf(borrower, amount);
        if (result != 0) {
            revert CompoundActionFailed("repayBorrowBehalf", result);
        }
        if (amount == type(uint256).max) {
            SafeTransferLib.safeApprove(cToken.underlying(), target, 0);
        }
    }
}
