// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8;

import {Borrower, IFlashLoanRouter} from "./mixin/Borrower.sol";
import {IERC20} from "./vendored/IERC20.sol";
import {IERC3156FlashBorrower} from "./vendored/IERC3156FlashBorrower.sol";
import {IERC3156FlashLender} from "./vendored/IERC3156FlashLender.sol";

/// @title ERC-3156 Borrower
/// @author CoW DAO developers
/// @notice A borrower contract for the flash-loan router that adds support for
/// any flash-loan provider that is compatible with ERC 3156.
contract ERC3156Borrower is Borrower, IERC3156FlashBorrower {
    /// @notice ERC 3156 requires flash loan borrowers to return this value if
    /// execution was successful.
    bytes32 private constant ERC3156_ONFLASHLOAN_SUCCESS = keccak256("ERC3156FlashBorrower.onFlashLoan");

    /// @param _router The router supported by this contract.
    constructor(IFlashLoanRouter _router) Borrower(_router) {}

    /// @inheritdoc Borrower
    function triggerFlashLoan(address lender, IERC20 token, uint256 amount, bytes calldata callBackData)
        internal
        override
    {
        bool success = IERC3156FlashLender(lender).flashLoan(this, address(token), amount, callBackData);
        require(success, "Flash loan was unsuccessful");
    }

    /// @inheritdoc IERC3156FlashBorrower
    function onFlashLoan(address, address, uint256, uint256, bytes calldata callBackData) external returns (bytes32) {
        flashLoanCallBack(callBackData);
        return ERC3156_ONFLASHLOAN_SUCCESS;
    }
}
