// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {IBorrower} from "../interface/IBorrower.sol";
import {ICowSettlement} from "../interface/ICowSettlement.sol";
import {IFlashLoanRouter} from "../interface/IFlashLoanRouter.sol";
import {IERC20} from "../vendored/IERC20.sol";
import {SafeERC20} from "../vendored/SafeERC20.sol";

/// @title Generic Borrower
/// @author CoW DAO developers
/// @notice An generic implementation of a borrower that is designed to make it
/// easy to support different flash-loan providers with a simpler, dedicated
/// contract that imports this.
/// It handles fund management through ERC-20 approvals, call authentication,
/// and router interactions.
abstract contract Borrower is IBorrower {
    using SafeERC20 for IERC20;

    /// @inheritdoc IBorrower
    IFlashLoanRouter public immutable router;
    /// @inheritdoc IBorrower
    ICowSettlement public immutable settlementContract;

    /// @notice A function with this modifier can only be called in the context
    /// of a CoW Protocol settlement.
    modifier onlySettlementContract() {
        require(msg.sender == address(settlementContract), "Only callable in a settlement");
        _;
    }

    /// @notice Only the registered flash-loan router can call.
    modifier onlyRouter() {
        require(msg.sender == address(router), "Not the router");
        _;
    }

    /// @param _router The router address that will be using this contract to
    /// trigger flash loans and that will be called back by this contract.
    constructor(IFlashLoanRouter _router) {
        router = _router;
        settlementContract = _router.settlementContract();
    }

    /// @inheritdoc IBorrower
    function flashLoanAndCallBack(address lender, IERC20 token, uint256 amount, bytes calldata callBackData)
        external
        onlyRouter
    {
        triggerFlashLoan(lender, token, amount, callBackData);
    }

    /// @inheritdoc IBorrower
    function approve(IERC20 token, address target, uint256 amount) external onlySettlementContract {
        token.forceApprove(target, amount);
    }

    /// @notice Every flash-loan provider has different syntax for requesting a
    /// flash loan. This function is intended to be realized in a concrete
    /// implementation to support the specific logic of the provider.
    /// @param lender The contract where the loan can be triggered.
    /// @param token The token to borrow.
    /// @param amount The amount of tokens to borrow.
    /// @param callBackData Data to be sent back to this contract in the
    /// flash-loan callback without any change.
    function triggerFlashLoan(address lender, IERC20 token, uint256 amount, bytes calldata callBackData)
        internal
        virtual;

    /// @notice This function is expected to be called in the concrete call-back
    /// implementation that is requested by the supported flash-loan provider.
    /// @param callBackData Data that was sent by the lender in the call back.
    function flashLoanCallBack(bytes calldata callBackData) internal {
        router.borrowerCallBack(callBackData);
    }
}
