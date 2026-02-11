// SPDX-License-Identifier: Apache-2.0 OR MIT
pragma solidity ^0.8.27;

import {Payments, IValidator} from "../../src/Payments.sol";

contract MockValidator is IValidator {
    enum ValidatorMode {
        STANDARD, // Approves all payments as proposed
        REDUCE_AMOUNT, // Reduces payment amount by a percentage
        REDUCE_DURATION, // Settles for fewer epochs than requested
        CUSTOM_RETURN, // Returns specific values set by the test
        MALICIOUS // Returns invalid values

    }

    ValidatorMode public mode = ValidatorMode.STANDARD; // Default to STANDARD mode
    uint256 public modificationFactor; // Percentage (0-100) for reductions
    uint256 public customAmount;
    uint256 public customUpto;
    string public customNote;

    // Storage for railTerminated calls
    uint256 public lastTerminatedRailId;
    address public lastTerminator;
    uint256 public lastEndEpoch;
    bool public railTerminatedCalled;

    constructor(ValidatorMode _mode) {
        mode = _mode;
        modificationFactor = 100; // 100% = no modification by default
    }

    function configure(uint256 _modificationFactor) external {
        require(_modificationFactor <= 100, "Factor must be between 0-100");
        modificationFactor = _modificationFactor;
    }

    // Set custom return values for CUSTOM_RETURN mode
    function setCustomValues(uint256 _amount, uint256 _upto, string calldata _note) external {
        customAmount = _amount;
        customUpto = _upto;
        customNote = _note;
    }

    // Change the validator's mode
    function setMode(ValidatorMode _mode) external {
        mode = _mode;
    }

    function validatePayment(
        uint256, /* railId */
        uint256 proposedAmount,
        uint256 fromEpoch,
        uint256 toEpoch,
        uint256 /* rate */
    ) external view override returns (ValidationResult memory result) {
        if (mode == ValidatorMode.STANDARD) {
            return ValidationResult({
                modifiedAmount: proposedAmount,
                settleUpto: toEpoch,
                note: "Standard approved payment"
            });
        } else if (mode == ValidatorMode.REDUCE_AMOUNT) {
            uint256 reducedAmount = (proposedAmount * modificationFactor) / 100;
            return ValidationResult({
                modifiedAmount: reducedAmount,
                settleUpto: toEpoch,
                note: "Validator reduced payment amount"
            });
        } else if (mode == ValidatorMode.REDUCE_DURATION) {
            uint256 totalEpochs = toEpoch - fromEpoch;
            uint256 reducedEpochs = (totalEpochs * modificationFactor) / 100;
            uint256 reducedEndEpoch = fromEpoch + reducedEpochs;

            // Calculate reduced amount proportionally
            uint256 reducedAmount = (proposedAmount * reducedEpochs) / totalEpochs;

            return ValidationResult({
                modifiedAmount: reducedAmount,
                settleUpto: reducedEndEpoch,
                note: "Validator reduced settlement duration"
            });
        } else if (mode == ValidatorMode.CUSTOM_RETURN) {
            return ValidationResult({modifiedAmount: customAmount, settleUpto: customUpto, note: customNote});
        } else {
            // Malicious mode attempts to return invalid values
            return ValidationResult({
                modifiedAmount: proposedAmount * 2, // Try to double the payment
                settleUpto: toEpoch + 10, // Try to settle beyond the requested range
                note: "Malicious validator attempting to manipulate payment"
            });
        }
    }

    function railTerminated(uint256 railId, address terminator, uint256 endEpoch) external override {
        lastTerminatedRailId = railId;
        lastTerminator = terminator;
        lastEndEpoch = endEpoch;
        railTerminatedCalled = true;
    }
}
