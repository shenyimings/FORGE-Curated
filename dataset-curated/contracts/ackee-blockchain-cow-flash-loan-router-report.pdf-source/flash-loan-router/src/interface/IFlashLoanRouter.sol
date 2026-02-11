// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {Loan} from "../library/Loan.sol";
import {ICowAuthentication} from "../vendored/ICowAuthentication.sol";
import {ICowSettlement} from "./ICowSettlement.sol";

/// @title Flash-loan Router Interface
/// @author CoW DAO developers
/// @notice Interface describing the functions available for interacting with
/// the flash-loan router.
/// @dev The flash loan router is intended to be a solver for CoW Protocol.
interface IFlashLoanRouter {
    /// @notice Request all flash loan specified in the input and, after that,
    /// executes the specified settlement.
    /// @dev It's the solver's responsibility to make sure the loan is specified
    /// correctly. The router contract offers no validation of the fact that
    /// the flash loan proceeds are available for spending.
    ///
    /// The repayment of a flash loan is different based on the protocol. For
    /// example, some expect to retrieve the funds from this borrower contract
    /// through `transferFrom`, while other check the lender balance is as
    /// expected after the flash loan has been processed. The executed
    /// settlement must be built to cater to the needs of the specified lender.
    ///
    /// A settlement can be executed at most once in a call. The settlement
    /// data cannot change during execution. Only the settle function can be
    /// called. All of this is also the case if the lender is untrusted.
    /// @param loans The list of flash loans to be requested before the
    /// settlement is executed. The loans will be requested in the specified
    /// order.
    /// @param settlement The ABI-encoded bytes for a call to `settle()` (as
    /// in `abi.encodeCall`).
    function flashLoanAndSettle(Loan.Data[] calldata loans, bytes calldata settlement) external;

    /// @notice Once a borrower has received the proceeds of a flash loan, it
    /// calls back the router through this function.
    /// @param encodedLoansWithSettlement The data the borrower received when
    /// it was called, without any modification.
    function borrowerCallBack(bytes calldata encodedLoansWithSettlement) external;

    /// @notice The settlement contract supported by this router. This is the
    /// contract that will be called when the settlement is executed.
    function settlementContract() external returns (ICowSettlement);

    /// @notice The settlement authenticator contract for CoW Protocol. This
    /// contract determines who the solvers for CoW Protocol are.
    function settlementAuthentication() external returns (ICowAuthentication);
}
