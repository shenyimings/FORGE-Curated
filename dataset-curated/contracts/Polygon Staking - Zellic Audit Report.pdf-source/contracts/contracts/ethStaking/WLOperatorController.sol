// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import "./base/OperatorController.sol";
import "./interfaces/IOperatorWhitelist.sol";

/**
 * @title Whitelist Operator Controller
 * @notice Handles whitelisted validator keys and operator rewards distribution
 */
contract WLOperatorController is OperatorController {
    struct OperatorCache {
        uint256 id;
        uint256 usedKeyPairs;
        uint256 validatorLimit;
        uint256 validatorCount;
    }

    IOperatorWhitelist public operatorWhitelist;

    uint256 public batchSize;
    uint256 public assignmentIndex;

    event RemoveKeyPairs(uint256 indexed operatorId, uint256 quantity);
    event ReportKeyPairValidation(uint256 indexed operatorId, bool success);
    event ReportStoppedValidators(uint256 indexed operatorId, uint256 totalStoppedValidators);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _ethStakingStrategy,
        address _wsdToken,
        address _operatorWhitelist,
        uint256 _batchSize
    ) public initializer {
        __OperatorController_init(_ethStakingStrategy, _wsdToken);
        operatorWhitelist = IOperatorWhitelist(_operatorWhitelist);
        batchSize = _batchSize;
    }

    /**
     * @notice Adds a new operator
     * @param _name name of operator
     */
    function addOperator(string calldata _name) external {
        operatorWhitelist.useWhitelist(msg.sender);
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
    ) external operatorExists(_operatorId) {
        require(msg.sender == operators[_operatorId].owner, "Sender is not operator owner");
        _addKeyPairs(_operatorId, _quantity, _pubkeys, _signatures);
    }

    /**
     * @notice Removes added pubkey/signature pairs from an operator in LIFO order
     * @param _operatorId id of operator
     * @param _quantity number of pairs to remove
     */
    function removeKeyPairs(
        uint256 _operatorId,
        uint256 _quantity
    ) external operatorExists(_operatorId) {
        require(msg.sender == operators[_operatorId].owner, "Sender is not operator owner");
        require(_quantity > 0, "Quantity must be greater than 0");
        require(
            _quantity <= operators[_operatorId].totalKeyPairs,
            "Cannot remove more keys than are added"
        );
        require(
            _quantity <= operators[_operatorId].totalKeyPairs - operators[_operatorId].usedKeyPairs,
            "Cannot remove used key pairs"
        );

        operators[_operatorId].totalKeyPairs -= uint64(_quantity);
        if (operators[_operatorId].validatorLimit > operators[_operatorId].totalKeyPairs) {
            queueLength -=
                operators[_operatorId].validatorLimit -
                operators[_operatorId].totalKeyPairs;
            operators[_operatorId].validatorLimit = operators[_operatorId].totalKeyPairs;
        }

        currentStateHash = keccak256(
            abi.encodePacked(currentStateHash, "removeKeyPairs", _operatorId, _quantity)
        );

        emit RemoveKeyPairs(_operatorId, _quantity);
    }

    /**
     * @notice Reports the results of key pair validation for an operator
     * @param _operatorId id of operator
     * @param _success whether the pairs are valid
     */
    function reportKeyPairValidation(
        uint256 _operatorId,
        bool _success
    ) external onlyKeyValidationOracle operatorExists(_operatorId) {
        require(operators[_operatorId].keyValidationInProgress, "No key validation in progress");

        if (_success && operators[_operatorId].active) {
            queueLength +=
                operators[_operatorId].totalKeyPairs -
                operators[_operatorId].validatorLimit;
            operators[_operatorId].validatorLimit = operators[_operatorId].totalKeyPairs;
            currentStateHash = keccak256(
                abi.encodePacked(currentStateHash, "reportKeyPairValidation", _operatorId)
            );
        }
        operators[_operatorId].keyValidationInProgress = false;

        emit ReportKeyPairValidation(_operatorId, _success);
    }

    /**
     * @notice Assigns the next set of validators in the queue
     * @param _operatorIds ids of operators that should be assigned validators
     * @param _validatorCounts number of validators to assign each operator
     * @param _totalValidatorCount sum of all entries in _validatorCounts
     * @return keys concatenated list of pubkeys
     * @return signatures concatenated list of signatures
     */
    function assignNextValidators(
        uint256[] calldata _operatorIds,
        uint256[] calldata _validatorCounts,
        uint256 _totalValidatorCount
    ) external onlyEthStakingStrategy returns (bytes memory keys, bytes memory signatures) {
        require(_operatorIds.length > 0, "Empty operatorIds");
        require(
            _operatorIds.length == _validatorCounts.length,
            "Inconsistent operatorIds and validatorCounts length"
        );

        OperatorCache memory lastOperator = OperatorCache(
            assignmentIndex == 0 ? operators.length - 1 : assignmentIndex - 1,
            0,
            0,
            0
        );

        bool[] memory seenOperatorIds = new bool[](operators.length);
        uint256 totalValidatorCount;
        uint256 maxBatches;
        uint256 maxBatchOperatorId;
        bytes32 stateHash = currentStateHash;

        for (uint256 i = 0; i < _operatorIds.length; i++) {
            uint256 operatorId = _operatorIds[i];

            require(operators[operatorId].active, "Inactive operator");
            require(!seenOperatorIds[operatorId], "Duplicate operator");
            seenOperatorIds[operatorId] = true;

            rewardsPool.updateReward(operators[operatorId].owner);

            operators[operatorId].usedKeyPairs += uint64(_validatorCounts[i]);
            activeValidators[operators[operatorId].owner] += _validatorCounts[i];

            OperatorCache memory operator = OperatorCache(
                operatorId,
                operators[operatorId].usedKeyPairs,
                operators[operatorId].validatorLimit,
                _validatorCounts[i]
            );

            require(
                totalValidatorCount + operator.validatorCount <= _totalValidatorCount,
                "Inconsistent total validator count"
            );

            for (
                uint256 j = operator.usedKeyPairs - operator.validatorCount;
                j < operator.usedKeyPairs;
                j++
            ) {
                (bytes memory key, bytes memory signature) = _loadKeyPair(operatorId, j);
                keys = bytes.concat(keys, key);
                signatures = bytes.concat(signatures, signature);
                stateHash = keccak256(abi.encodePacked(stateHash, "assignKey", operatorId, key));
                totalValidatorCount++;
            }

            require(
                operator.usedKeyPairs <= operator.validatorLimit,
                "Assigned more keys than validator limit"
            );
            require(
                (operator.validatorCount % batchSize == 0) ||
                    (operator.usedKeyPairs == operator.validatorLimit),
                "Invalid batching"
            );

            // All excluded operators between any 2 successive included operators must be at capacity
            if (operatorId > (lastOperator.id + 1)) {
                for (uint256 j = lastOperator.id + 1; j < operatorId; j++) {
                    require(
                        operators[j].usedKeyPairs == operators[j].validatorLimit,
                        "1: Validator assignments were skipped"
                    );
                }
            } else if (operatorId < (lastOperator.id + 1)) {
                for (uint256 j = lastOperator.id + 1; j < operators.length; j++) {
                    require(
                        operators[j].usedKeyPairs == operators[j].validatorLimit,
                        "2: Validator assignments were skipped"
                    );
                }
                for (uint256 j = 0; j < operatorId; j++) {
                    require(
                        operators[j].usedKeyPairs == operators[j].validatorLimit,
                        "3: Validator assignments were skipped"
                    );
                }
            }

            if (operator.validatorCount > lastOperator.validatorCount) {
                // An operator cannot be assigned more validators than the operator before unless the operator before is at capacity
                require(
                    lastOperator.usedKeyPairs == lastOperator.validatorLimit,
                    "1: Validator assignments incorrectly split"
                );
            } else if (operator.validatorCount < lastOperator.validatorCount) {
                // An operator cannot be assigned greater than a single batch more than the operator after unless the operator
                // after is at capacity
                require(
                    ((lastOperator.validatorCount - operator.validatorCount) <= batchSize) ||
                        (operator.usedKeyPairs == operator.validatorLimit),
                    "2: Validator assignments incorrectly split"
                );
            }

            uint256 batches = operator.validatorCount /
                batchSize +
                (operator.validatorCount % batchSize > 0 ? 1 : 0);
            if (batches >= maxBatches) {
                maxBatches = batches;
                maxBatchOperatorId = operatorId;
            }

            lastOperator = operator;
        }

        require(totalValidatorCount == _totalValidatorCount, "Inconsistent total validator count");

        // If any operator received more than 1 batch, a full loop has occurred - we need to check that every operator
        // between the last one in _operatorIds and assignmentIndex is at capacity
        if (maxBatches > 1) {
            if (lastOperator.id < assignmentIndex) {
                for (uint256 i = lastOperator.id + 1; i < assignmentIndex; i++) {
                    require(
                        operators[i].usedKeyPairs == operators[i].validatorLimit,
                        "4: Validator assignments were skipped"
                    );
                }
            } else if (lastOperator.id > assignmentIndex) {
                for (uint256 i = lastOperator.id + 1; i < operators.length; i++) {
                    require(
                        operators[i].usedKeyPairs == operators[i].validatorLimit,
                        "5: Validator assignments were skipped"
                    );
                }
                for (uint256 i = 0; i < assignmentIndex; i++) {
                    require(
                        operators[i].usedKeyPairs == operators[i].validatorLimit,
                        "6: Validator assignments were skipped"
                    );
                }
            }
        }

        // The next assignmentIndex should be the one right after the operator that received the most batches,
        // the farthest back in the loop
        if (maxBatchOperatorId == operators.length - 1) {
            assignmentIndex = 0;
        } else {
            assignmentIndex = maxBatchOperatorId + 1;
        }

        totalAssignedValidators += totalValidatorCount;
        totalActiveValidators += totalValidatorCount;
        queueLength -= totalValidatorCount;
        currentStateHash = stateHash;
    }

    /**
     * @notice Returns the next set of validators to be assigned
     * @param _validatorCount target number of validators to assign
     * @return operatorIds ids of operators that should be assigned validators
     * @return validatorCounts number of validators to assign each operator
     * @return totalValidatorCount actual number of validators to be assigned
     * @return keys validator keys to be assigned
     */
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
        )
    {
        require(_validatorCount > 0, "Validator count must be greater than 0");
        require(_validatorCount <= queueLength, "Cannot assign more than queue length");

        uint256[] memory validatorCounter = new uint256[](operators.length);
        uint256[] memory operatorTracker = new uint256[](operators.length);
        uint256 operatorCount;
        uint256 remainingToAssign = _validatorCount;

        uint256 loopValidatorCount;
        uint256 index = assignmentIndex;
        uint256 loopEnd = index == 0 ? operators.length - 1 : index - 1;

        while (true) {
            uint256 validatorRoom = operators[index].validatorLimit -
                (operators[index].usedKeyPairs + validatorCounter[index]);

            if (validatorRoom > 0 && operators[index].active) {
                if (validatorRoom <= batchSize && validatorRoom <= remainingToAssign) {
                    if (validatorCounter[index] == 0) {
                        operatorTracker[operatorCount] = index;
                        operatorCount++;
                    }
                    validatorCounter[index] += validatorRoom;
                    loopValidatorCount += validatorRoom;
                    remainingToAssign -= validatorRoom;
                } else if (batchSize <= remainingToAssign) {
                    if (validatorCounter[index] == 0) {
                        operatorTracker[operatorCount] = index;
                        operatorCount++;
                    }
                    validatorCounter[index] += batchSize;
                    loopValidatorCount += batchSize;
                    remainingToAssign -= batchSize;
                } else {
                    break;
                }
            }

            if (index == loopEnd) {
                if (loopValidatorCount == 0) {
                    break;
                } else {
                    loopValidatorCount = 0;
                }
            }

            if (index == operators.length - 1) {
                index = 0;
            } else {
                index++;
            }
        }

        totalValidatorCount = _validatorCount - remainingToAssign;

        operatorIds = new uint256[](operatorCount);
        validatorCounts = new uint256[](operatorCount);

        for (uint256 i = 0; i < operatorCount; i++) {
            operatorIds[i] = operatorTracker[i];
            validatorCounts[i] = validatorCounter[operatorTracker[i]];

            uint256 operatorId = operatorIds[i];
            uint256 usedKeyPairs = operators[operatorId].usedKeyPairs;

            for (uint256 j = usedKeyPairs; j < usedKeyPairs + validatorCounts[i]; j++) {
                (bytes memory key, ) = _loadKeyPair(operatorId, j);
                keys = bytes.concat(keys, key);
            }
        }
    }

    /**
     * @notice Reports lifetime stopped validators for a list of operators
     * @param _operatorIds list of operator ids to report for
     * @param _stoppedValidators list of lifetime stopped validators for each operator
     */
    function reportStoppedValidators(
        uint256[] calldata _operatorIds,
        uint256[] calldata _stoppedValidators
    ) external onlyBeaconOracle {
        require(_operatorIds.length == _stoppedValidators.length, "Inconsistent list lengths");

        uint256 totalNewlyStoppedValidators;

        for (uint256 i = 0; i < _operatorIds.length; i++) {
            uint256 operatorId = _operatorIds[i];
            require(operatorId < operators.length, "Operator does not exist");
            require(
                _stoppedValidators[i] > operators[operatorId].stoppedValidators,
                "Reported negative or zero stopped validators"
            );
            require(
                _stoppedValidators[i] <= operators[operatorId].usedKeyPairs,
                "Reported more stopped validators than active"
            );

            rewardsPool.updateReward(operators[operatorId].owner);

            uint256 newlyStoppedValidators = _stoppedValidators[i] -
                operators[operatorId].stoppedValidators;

            operators[operatorId].stoppedValidators += uint64(newlyStoppedValidators);

            if (operators[operatorId].active) {
                activeValidators[operators[operatorId].owner] -= newlyStoppedValidators;
                totalNewlyStoppedValidators += newlyStoppedValidators;
            }

            emit ReportStoppedValidators(operatorId, _stoppedValidators[i]);
        }

        totalActiveValidators -= totalNewlyStoppedValidators;
    }

    /**
     * @notice Sets the batch size for validator assignment
     * @param _batchSize new batch size
     */
    function setBatchSize(uint256 _batchSize) external onlyOwner {
        batchSize = _batchSize;
    }

    /**
     * @notice Sets the location of the operator whitelist
     * @param _operatorWhitelist new location of operator whitelist
     */
    function setOperatorWhitelist(address _operatorWhitelist) external onlyOwner {
        operatorWhitelist = IOperatorWhitelist(_operatorWhitelist);
    }
}
