// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {IERC20} from "../vendored/IERC20.sol";
import {ICowSettlement} from "./ICowSettlement.sol";
import {IFlashLoanRouter} from "./IFlashLoanRouter.sol";

/// @title Flash-loan Borrower
/// @author CoW DAO developers
/// @notice The CoW Protocol flash-loan router uses the flash-loan borrower
/// contract as the intermediary that requests funds through a flash loan.
/// Different flash-loan protocols have different logic for flash loans:
/// usually, the call-back function name and parameters are different. Each
/// flash-loan protocol must have a dedicated Borrower contract to be supported
/// by the flash-loan router.
/// A concrete borrower implementation generally calls a dedicated flash-loan
/// function on the lender and then awaits for a callback from it. The borrower
/// then calls back the router for further processing.
interface IBorrower {
    /// @notice Requests a flash loan with the specified parameters from the
    /// lender and, once the funds have been received, call back the router
    /// while passing through the specified custom data. The flash-loan
    /// repayment is expected to take place during the final settlement in the
    /// router.
    /// @param lender The address of the flash-loan lender from which to borrow.
    /// @param token The token that is requested in the flash loan.
    /// @param amount The amount of funds requested from the lender.
    /// @param callBackData The data to send back when calling the router once
    /// the loan is received.
    function flashLoanAndCallBack(address lender, IERC20 token, uint256 amount, bytes calldata callBackData) external;

    /// @notice Approves the target address to spend the specified token on
    /// behalf of the Borrower up to the specified amount.
    /// @dev In general, the only way to transfer funds out of this contract is
    /// through a call to this function and a subsequent call to `transferFrom`.
    /// This approval is expected to work similarly to an ERC-20 approval (in
    /// particular, the allowance doesn't reset once the call is terminated).
    /// @param token The token to approve for transferring.
    /// @param target The address that will be allowed to spend the token.
    /// @param amount The amount of tokens to set as the allowance.
    function approve(IERC20 token, address target, uint256 amount) external;

    /// @notice The settlement contract supported by this contract.
    function settlementContract() external view returns (ICowSettlement);

    /// @notice The router contract that manages this borrower contract. It will
    /// be called back once the flash-loan proceeds are received and is the only
    /// address that can trigger a flash loan request.
    function router() external view returns (IFlashLoanRouter);
}
