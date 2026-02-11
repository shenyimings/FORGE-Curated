// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { TimeLockPenaltyERC20, IERC20, IERC20Permit } from "./TimeLockPenaltyERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title sPRL1
/// @author Cooper Labs
/// @custom:contact security@cooperlabs.xyz
/// @notice sPRL1 is a staking contract that allows users to deposit PRL assets.
contract sPRL1 is TimeLockPenaltyERC20 {
    using SafeERC20 for IERC20;

    string constant NAME = "Stake PRL";
    string constant SYMBOL = "sPRL1";

    //-------------------------------------------
    // Constructor
    //-------------------------------------------

    /// @notice Deploy the sPRL1 contract.
    /// @param _underlying The underlying PRL token.
    /// @param _feeReceiver The address to receive the fees.
    /// @param _accessManager The address of the AccessManager.
    /// @param _startPenaltyPercentage The percentage of the penalty fee.
    /// @param _timeLockDuration The time lock duration.
    constructor(
        address _underlying,
        address _feeReceiver,
        address _accessManager,
        uint256 _startPenaltyPercentage,
        uint64 _timeLockDuration
    )
        TimeLockPenaltyERC20(
            NAME,
            SYMBOL,
            _underlying,
            _feeReceiver,
            _accessManager,
            _startPenaltyPercentage,
            _timeLockDuration
        )
    { }

    //-------------------------------------------
    // External functions
    //-------------------------------------------

    /// @notice Deposit assets into the contract and mint the equivalent amount of tokens.
    /// @param _assetAmount The amount of assets to deposit.
    function deposit(uint256 _assetAmount) external whenNotPaused nonReentrant {
        underlying.safeTransferFrom(msg.sender, address(this), _assetAmount);
        _deposit(_assetAmount);
    }

    /// @notice Deposit assets into the contract using ERC20Permit and mint the equivalent amount of tokens
    /// @param _assetAmount The amount of assets to deposit
    /// @param _deadline The deadline for the permit.
    /// @param _v The v value of the permit signature.
    /// @param _r The r value of the permit signature.
    /// @param _s The s value of the permit signature.
    function depositWithPermit(
        uint256 _assetAmount,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    )
        external
        whenNotPaused
        nonReentrant
    {
        // @dev using try catch to avoid reverting the transaction in case of front-running
        try IERC20Permit(address(underlying)).permit(msg.sender, address(this), _assetAmount, _deadline, _v, _r, _s) {
        } catch { }
        underlying.safeTransferFrom(msg.sender, address(this), _assetAmount);
        _deposit(_assetAmount);
    }

    /// @notice Allow users to emergency withdraw assets without penalties.
    /// @dev This function can only be called when the contract is paused.
    /// @param _unlockingAmount The amount of assets to unlock.
    function emergencyWithdraw(uint256 _unlockingAmount) external whenPaused nonReentrant {
        _burn(msg.sender, _unlockingAmount);
        emit EmergencyWithdraw(msg.sender, _unlockingAmount);
        underlying.safeTransfer(msg.sender, _unlockingAmount);
    }

    /// @notice Withdraw multiple withdrawal requests.
    /// @param _ids The IDs of the withdrawal requests to withdraw.
    function withdraw(uint256[] calldata _ids) external nonReentrant {
        (uint256 totalAmountWithdrawn, uint256 totalFeeAmount) = _withdrawMultiple(_ids);
        unlockingAmount = unlockingAmount - totalAmountWithdrawn - totalFeeAmount;
        if (totalFeeAmount > 0) {
            underlying.safeTransfer(feeReceiver, totalFeeAmount);
        }
        underlying.safeTransfer(msg.sender, totalAmountWithdrawn);
    }
}
