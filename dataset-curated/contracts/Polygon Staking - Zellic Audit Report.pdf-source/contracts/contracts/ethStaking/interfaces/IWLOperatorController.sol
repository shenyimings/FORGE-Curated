// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import "./IOperatorController.sol";

interface IWLOperatorController is IOperatorController {
    function assignNextValidators(
        uint256[] calldata _operatorIds,
        uint256[] calldata _validatorCounts,
        uint256 _totalValidatorCount
    ) external returns (bytes memory keys, bytes memory signatures);

    function getNextValidators(
        uint256 _validatorCount
    )
        external
        view
        returns (
            uint256[] memory operatorIds,
            uint256[] memory validatorCounts,
            uint256 totalValidatorCount,
            bytes memory keys
        );
}
