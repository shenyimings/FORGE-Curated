// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {IFlashLoanRouter} from "./interface/IFlashLoanRouter.sol";
import {Borrower} from "./mixin/Borrower.sol";
import {IAaveFlashLoanReceiver} from "./vendored/IAaveFlashLoanReceiver.sol";
import {IAavePool} from "./vendored/IAavePool.sol";
import {IERC20} from "./vendored/IERC20.sol";

/// @title Aave Borrower
/// @author CoW DAO developers
/// @notice A borrower contract for the flash-loan router that adds support for
/// Aave protocol.
contract AaveBorrower is Borrower, IAaveFlashLoanReceiver {
    /// @param _router The router supported by this contract.
    constructor(IFlashLoanRouter _router) Borrower(_router) {}

    /// @inheritdoc Borrower
    function triggerFlashLoan(address lender, IERC20 token, uint256 amount, bytes calldata callBackData)
        internal
        override
    {
        // For documentation on the call parameters, see:
        // <https://aave.com/docs/developers/smart-contracts/pool#write-methods-flashloan-input-parameters>
        IAaveFlashLoanReceiver receiverAddress = this;
        address[] memory assets = new address[](1);
        assets[0] = address(token);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;
        uint256[] memory interestRateModes = new uint256[](1);
        // Don't open any debt position, just revert if funds can't be
        // transferred from this contract.
        interestRateModes[0] = 0;
        // The next value is technically unused, since `interestRateMode` is 0.
        address onBehalfOf = address(this);
        bytes calldata params = callBackData;
        // Referral supply is currently inactive
        uint16 referralCode = 0;
        IAavePool(lender).flashLoan(
            address(receiverAddress), assets, amounts, interestRateModes, onBehalfOf, params, referralCode
        );
    }

    /// @inheritdoc IAaveFlashLoanReceiver
    function executeOperation(
        address[] calldata,
        uint256[] calldata,
        uint256[] calldata,
        address,
        bytes calldata callBackData
    ) external returns (bool) {
        flashLoanCallBack(callBackData);
        return true;
    }
}
