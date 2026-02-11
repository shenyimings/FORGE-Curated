// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "solidity-bytes-utils/contracts/BytesLib.sol";

import "../base/OperatorController.sol";

/**
 * @title Operator Controller
 * @notice Base controller contract to be inherited from
 */
contract OperatorControllerMock is OperatorController {
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _ethStakingStrategy, address _wsdToken) public initializer {
        __OperatorController_init(_ethStakingStrategy, _wsdToken);
    }

    /**
     * @notice Adds a new operator
     * @param _name name of operator
     */
    function addOperator(string calldata _name) external {
        _addOperator(_name);
    }

    /**
     * @notice Adds a set of new validator pubkey/signature pairs for an operator
     * @param _operatorId id of operator
     * @param _quantity number of new pairs to add
     * @param _pubkeys concatenated set of pubkeys to add
     * @param _signatures concatenated set of signatures to add
     */
    function addKeyPairs(
        uint256 _operatorId,
        uint256 _quantity,
        bytes calldata _pubkeys,
        bytes calldata _signatures
    ) external {
        _addKeyPairs(_operatorId, _quantity, _pubkeys, _signatures);
    }

    /**
     * @notice Assigns the next set of validators in the queue
     * @param _operatorIds ids of operators that should be assigned validators
     * @param _validatorCounts number of validators to assign each operator
     * @return keys concatenated list of pubkeys
     * @return signatures concatenated list of signatures
     */
    function assignNextValidators(
        uint256[] calldata _operatorIds,
        uint256[] calldata _validatorCounts,
        uint256
    ) external returns (bytes memory keys, bytes memory signatures) {
        for (uint256 i = 0; i < _operatorIds.length; i++) {
            uint256 operatorId = _operatorIds[i];

            operators[operatorId].usedKeyPairs += uint64(_validatorCounts[i]);
            activeValidators[operators[operatorId].owner] += _validatorCounts[i];
            totalActiveValidators += _validatorCounts[i];
            totalAssignedValidators += _validatorCounts[i];
        }
    }

    function reportKeyPairValidation(uint256 _operatorId, bool _success) external {
        require(operators[_operatorId].keyValidationInProgress, "No key validation in progress");

        if (_success) {
            queueLength +=
                operators[_operatorId].totalKeyPairs -
                operators[_operatorId].validatorLimit;
            operators[_operatorId].validatorLimit = operators[_operatorId].totalKeyPairs;
        }
        operators[_operatorId].keyValidationInProgress = false;
    }
}
