// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { ILendingConnector } from "contracts/interfaces/ILendingConnector.sol";
import {
    IMorpho,
    MarketParams,
    Position,
    Id
} from "@morpho-blue/interfaces/IMorpho.sol";
import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";
import { MorphoBalancesLib } from
    "@morpho-blue/libraries/periphery/MorphoBalancesLib.sol";

using MorphoBalancesLib for IMorpho;

struct MorphoExtraData {
    MarketParams marketParams;
    uint256 shares; // For repay
    Id id;
}

contract MorphoConnector is ILendingConnector {
    error Unsupported();

    function mint(
        address target,
        uint256 amount,
        bytes memory extraData
    ) external payable override {
        MorphoExtraData memory data = abi.decode(extraData, (MorphoExtraData));
        SafeTransferLib.safeApprove(
            data.marketParams.collateralToken, target, amount
        );
        IMorpho(target).supplyCollateral(
            data.marketParams, amount, address(this), ""
        );
    }

    function redeem(
        address target,
        uint256 amount,
        bytes memory extraData
    ) external override {
        MorphoExtraData memory data = abi.decode(extraData, (MorphoExtraData));

        if (amount == type(uint256).max) {
            Position memory position =
                IMorpho(target).position(data.id, address(this));
            amount = position.collateral;
        }
        IMorpho(target).withdrawCollateral(
            data.marketParams, amount, address(this), address(this)
        );
    }

    function redeemUnderlying(
        address, // target
        uint256, // amount
        bytes memory // extraData
    ) external pure override {
        // Not used as the LendingStrategyTwoAsset does not apply to Morpho
        revert Unsupported();
    }

    function borrow(
        address target,
        uint256 amount,
        bytes memory extraData
    ) external payable override {
        MorphoExtraData memory data = abi.decode(extraData, (MorphoExtraData));
        IMorpho(target).borrow(
            data.marketParams, amount, 0, address(this), address(this)
        );
    }

    function repay(
        address target,
        uint256 amount,
        bytes memory extraData
    ) external payable override {
        MorphoExtraData memory data = abi.decode(extraData, (MorphoExtraData));
        SafeTransferLib.safeApprove(data.marketParams.loanToken, target, amount);
        IMorpho(target).repay(
            data.marketParams, 0, data.shares, address(this), ""
        );
        SafeTransferLib.safeApprove(data.marketParams.loanToken, target, 0);
    }

    function repayFor(
        address target,
        address borrower,
        uint256 amount,
        bytes memory extraData
    ) external payable override {
        MorphoExtraData memory data = abi.decode(extraData, (MorphoExtraData));
        SafeTransferLib.safeApprove(data.marketParams.loanToken, target, amount);
        IMorpho(target).repay(data.marketParams, amount, 0, borrower, "");
    }
}
