// Copyright (c) 2025 Merge Layers Inc.
//
// This source code is licensed under the Business Source License 1.1
// (the "License"); you may not use this file except in compliance with the
// License. You may obtain a copy of the License at
//
//     https://github.com/malda-protocol/malda-lending/blob/main/LICENSE-BSL
//
// See the License for the specific language governing permissions and
// limitations under the License.
//
// This file contains code derived from or inspired by Compound V2,
// originally licensed under the BSD 3-Clause License. See LICENSE-COMPOUND-V2
// for original license terms and attributions.

// SPDX-License-Identifier: BSL-1.1
pragma solidity =0.8.28;

/*
 _____ _____ __    ____  _____ 
|     |  _  |  |  |    \|  _  |
| | | |     |  |__|  |  |     |
|_|_|_|__|__|_____|____/|__|__|   
*/

// interfaces
import {ImErc20} from "src/interfaces/ImErc20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ImTokenMinimal, ImTokenDelegator} from "src/interfaces/ImToken.sol";

// contracts
import {mToken} from "./mToken.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title Malda's mErc20 Contract
 * @notice mTokens which wrap an EIP-20 underlying
 */
abstract contract mErc20 is mToken, ImErc20 {
    using SafeERC20 for IERC20;

    // ----------- STORAGE ------------
    /**
     * @notice Underlying asset for this mToken
     */
    address public underlying;

    // ----------- ERRORS ------------
    error mErc20_TokenNotValid();

    /**
     * @notice Initialize the new money market
     * @param underlying_ The address of the underlying asset
     * @param operator_ The address of the Operator
     * @param interestRateModel_ The address of the interest rate model
     * @param initialExchangeRateMantissa_ The initial exchange rate, scaled by 1e18
     * @param name_ ERC-20 name of this token
     * @param symbol_ ERC-20 symbol of this token
     * @param decimals_ ERC-20 decimal precision of this token
     */
    function _initializeMErc20(
        address underlying_,
        address operator_,
        address interestRateModel_,
        uint256 initialExchangeRateMantissa_,
        string memory name_,
        string memory symbol_,
        uint8 decimals_
    ) internal {
        // mToken initialize does the bulk of the work
        _initializeMToken(operator_, interestRateModel_, initialExchangeRateMantissa_, name_, symbol_, decimals_);

        // Set underlying and sanity check it
        underlying = underlying_;
        ImTokenMinimal(underlying).totalSupply();
    }

    modifier checkSameChainAllowed() {
        if (sameChainFlowStateDisabled) revert mToken_SameChainOperationsAreDisabled();
        _;
    } 

    // ----------- OWNER ------------
    /**
     * @notice Admin call to delegate the votes of the MALDA-like underlying
     * @param delegatee The address to delegate votes to
     * @dev mTokens whose underlying are not  should revert here
     */
    function delegateMaldaLikeTo(address delegatee) external onlyAdmin {
        ImTokenDelegator(underlying).delegate(delegatee);
    }

    /**
     * @notice A public function to sweep accidental ERC-20 transfers to this contract. Tokens are sent to admin (timelock)
     * @param token The address of the ERC-20 token to sweep
     */
    function sweepToken(IERC20 token) external onlyAdmin {
        require(address(token) != underlying, mErc20_TokenNotValid());

        uint256 underlyingBefore = IERC20(underlying).balanceOf(address(this));
        uint256 balance = token.balanceOf(address(this));
        token.safeTransfer(admin, balance);
        uint256 underlyingAfter = IERC20(underlying).balanceOf(address(this));
        require(underlyingBefore == underlyingAfter, mToken_TransferNotValid());
    }

    // ----------- MARKET PUBLIC ------------
    /**
     * @inheritdoc ImErc20
     */
    function mint(uint256 mintAmount, address receiver, uint256 minAmountOut) external checkSameChainAllowed {
        _mint(msg.sender, receiver, mintAmount, minAmountOut, true);
    }

    /**
     * @inheritdoc ImErc20
     */
    function redeem(uint256 redeemTokens) external checkSameChainAllowed {
        _redeem(msg.sender, redeemTokens, true);
    }

    /**
     * @inheritdoc ImErc20
     */
    function redeemUnderlying(uint256 redeemAmount) external checkSameChainAllowed {
        _redeemUnderlying(msg.sender, redeemAmount, true);
    }

    /**
     * @inheritdoc ImErc20
     */
    function borrow(uint256 borrowAmount) external checkSameChainAllowed {
        _borrow(msg.sender, borrowAmount, true);
    }

    /**
     * @inheritdoc ImErc20
     */
    function repay(uint256 repayAmount) external checkSameChainAllowed returns (uint256) {
        return _repay(repayAmount, true);
    }

    /**
     * @inheritdoc ImErc20
     */
    function repayBehalf(address borrower, uint256 repayAmount) external checkSameChainAllowed returns (uint256) {
        return _repayBehalf(borrower, repayAmount, true);
    }

    /**
     * @inheritdoc ImErc20
     */
    function liquidate(address borrower, uint256 repayAmount, address mTokenCollateral) external checkSameChainAllowed {
        _liquidate(msg.sender, borrower, repayAmount, mTokenCollateral, true);
    }

    /**
     * @inheritdoc ImErc20
     */
    function addReserves(uint256 addAmount) external {
        return _addReserves(addAmount);
    }

    // ----------- INTERNAL ------------
    /**
     * @notice Gets balance of this contract in terms of the underlying
     * @dev This excludes the value of the current message, if any
     * @return The quantity of underlying tokens owned by this contract
     */
    function _getCashPrior() internal view virtual override returns (uint256) {
        return totalUnderlying;
    }

    /**
     * @dev Performs a transfer in, reverting upon failure. Returns the amount actually transferred to the protocol, in case of a fee.
     *  This may revert due to insufficient balance or insufficient allowance.
     */
    function _doTransferIn(address from, uint256 amount) internal virtual override returns (uint256) {
        uint256 balanceBefore = IERC20(underlying).balanceOf(address(this));
        IERC20(underlying).safeTransferFrom(from, address(this), amount);
        uint256 balanceAfter = IERC20(underlying).balanceOf(address(this));
        return balanceAfter - balanceBefore;
    }

    /**
     * @dev Performs a transfer out, ideally returning an explanatory error code upon failure rather than reverting.
     *  If caller has not called checked protocol's balance, may revert due to insufficient cash held in the contract.
     *  If caller has checked protocol's balance, and verified it is >= amount, this should not revert in normal conditions.
     */
    function _doTransferOut(address payable to, uint256 amount) internal virtual override {
        IERC20(underlying).safeTransfer(to, amount);
    }
}
