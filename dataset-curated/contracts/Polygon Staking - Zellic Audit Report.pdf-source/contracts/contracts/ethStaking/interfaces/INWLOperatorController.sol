// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import "./IOperatorController.sol";

interface INWLOperatorController is IOperatorController {
    function assignNextValidators(
        uint256 _totalValidatorCount
    ) external returns (bytes memory keys, bytes memory signatures);

    function totalActiveStake() external view returns (uint256);

    function getNextValidators(uint256 _validatorCount) external view returns (bytes memory keys);
}
