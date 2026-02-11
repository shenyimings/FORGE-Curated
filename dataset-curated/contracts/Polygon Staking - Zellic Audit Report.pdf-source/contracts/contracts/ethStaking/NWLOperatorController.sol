// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import "./base/OperatorController.sol";
import "./interfaces/IOperatorWhitelist.sol";
import "./interfaces/IEthStakingStrategy.sol";

/**
 * @title Non-Whitelist Operator Controller
 * @notice Handles non-whitelisted validator keys, operator stakes, and operator rewards distribution
 */
contract NWLOperatorController is OperatorController {
    uint256 public constant DEPOSIT_AMOUNT = 16 ether;

    struct QueueEntry {
        uint256 operatorId;
        uint256 numKeyPairs;
    }

    QueueEntry[] private queue;
    uint256 public queueIndex;

    mapping(uint256 => uint256) public ethLost;
    mapping(uint256 => uint256) public ethWithdrawn;

    event RemoveKeyPairs(uint256 indexed operatorId, uint256 quantity);
    event ReportKeyPairValidation(uint256 indexed operatorId, bool success);
    event ReportStoppedValidators(
        uint256 indexed operatorId,
        uint256 totalStoppedValidators,
        uint256 totalEthLost
    );
    event WithdrawStake(uint256 indexed _operatorId, uint256 amount);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _ethStakingStrategy, address _wsdToken) public initializer {
        __OperatorController_init(_ethStakingStrategy, _wsdToken);
    }

    /**
     * @notice Returns a list of queue entries
     * @param _startIndex start index of entries to return
     * @param _numEntries number of entries to return
     * @return entries list of queue entries
     */
    function getQueueEntries(
        uint256 _startIndex,
        uint256 _numEntries
    ) external view returns (QueueEntry[] memory entries) {
        require(_startIndex < queue.length, "startIndex out of range");

        uint256 endIndex = _startIndex + _numEntries;
        if (endIndex > queue.length) {
            endIndex = queue.length;
        }

        entries = new QueueEntry[](endIndex - _startIndex);
        for (uint256 i = _startIndex; i < endIndex; i++) {
            entries[i] = queue[i];
        }
    }

    /**
     * @notice Returns the total active stake across all validators
     * @return totalActiveStake total active stake
     */
    function totalActiveStake() external view returns (uint256) {
        return totalActiveValidators * DEPOSIT_AMOUNT;
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
    ) external payable operatorExists(_operatorId) {
        require(msg.sender == operators[_operatorId].owner, "Sender is not operator owner");
        require(msg.value == _quantity * DEPOSIT_AMOUNT, "Incorrect stake amount");
        _addKeyPairs(_operatorId, _quantity, _pubkeys, _signatures);
    }

    /**
     * @notice Removes added pubkey/signature pairs from an operator in LIFO order
     * @param _operatorId id of operator
     * @param _quantity number of pairs to remove
     * @param _queueEntryIndexes indexes of this operator's queue entries to remove
     */
    function removeKeyPairs(
        uint256 _operatorId,
        uint256 _quantity,
        uint256[] calldata _queueEntryIndexes
    ) external operatorExists(_operatorId) {
        require(msg.sender == operators[_operatorId].owner, "Sender is not operator owner");
        require(_quantity > 0, "Quantity must be greater than 0");
        require(
            _quantity <= operators[_operatorId].totalKeyPairs - operators[_operatorId].usedKeyPairs,
            "Cannot remove used key pairs or more keys than are added"
        );

        uint256 toRemove = _quantity;
        uint256 unverifiedKeys = operators[_operatorId].totalKeyPairs -
            operators[_operatorId].validatorLimit;

        if (unverifiedKeys < toRemove) {
            toRemove -= unverifiedKeys;
            queueLength -= toRemove;
            for (uint256 i = 0; i < _queueEntryIndexes.length; i++) {
                require(
                    _queueEntryIndexes[i] >= queueIndex,
                    "Cannot remove from queue entry that is already passed by"
                );
                require(
                    _queueEntryIndexes[i] < queue.length,
                    "Cannot remove from queue entry that does not exist"
                );

                QueueEntry memory entry = queue[_queueEntryIndexes[i]];
                require(
                    entry.operatorId == _operatorId,
                    "Sender is not operator owner of queue entry"
                );

                if (entry.numKeyPairs < toRemove) {
                    queue[_queueEntryIndexes[i]].numKeyPairs = 0;
                    toRemove -= entry.numKeyPairs;
                } else {
                    queue[_queueEntryIndexes[i]].numKeyPairs -= toRemove;
                    break;
                }
            }
        }

        operators[_operatorId].totalKeyPairs -= uint64(_quantity);
        if (operators[_operatorId].validatorLimit > operators[_operatorId].totalKeyPairs) {
            operators[_operatorId].validatorLimit = operators[_operatorId].totalKeyPairs;
        }

        currentStateHash = keccak256(
            abi.encodePacked(
                currentStateHash,
                "removeKeyPairs",
                _operatorId,
                _quantity,
                _queueEntryIndexes
            )
        );

        (bool success, ) = payable(msg.sender).call{value: _quantity * DEPOSIT_AMOUNT}("");
        require(success, "ETH transfer failed");

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
            uint256 newKeyPairs = operators[_operatorId].totalKeyPairs -
                operators[_operatorId].validatorLimit;
            queue.push(QueueEntry(_operatorId, newKeyPairs));
            queueLength += newKeyPairs;
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
     * @param _totalValidatorCount total number of validators to assign
     * @return keys concatenated list of pubkeys
     * @return signatures concatenated list of signatures
     */
    function assignNextValidators(
        uint256 _totalValidatorCount
    ) external onlyEthStakingStrategy returns (bytes memory keys, bytes memory signatures) {
        require(_totalValidatorCount > 0, "Validator count must be greater than 0");
        require(_totalValidatorCount <= queueLength, "Cannot assign more than queue length");

        bytes32 stateHash = currentStateHash;
        uint256 toAssign = _totalValidatorCount;
        uint256 index = queueIndex;

        while (index < queue.length) {
            uint256 numKeyPairs = queue[index].numKeyPairs;
            uint256 operatorId = queue[index].operatorId;

            if (numKeyPairs > 0 && operators[operatorId].active) {
                uint256 assignToOperator;

                if (numKeyPairs < toAssign) {
                    assignToOperator = numKeyPairs;
                    toAssign -= numKeyPairs;
                } else {
                    assignToOperator = toAssign;
                    if (numKeyPairs == toAssign) {
                        index++;
                    } else {
                        queue[index].numKeyPairs -= toAssign;
                    }
                    toAssign = 0;
                }

                rewardsPool.updateReward(operators[operatorId].owner);

                operators[operatorId].usedKeyPairs += uint64(assignToOperator);
                activeValidators[operators[operatorId].owner] += assignToOperator;

                uint256 usedKeyPairs = operators[operatorId].usedKeyPairs;

                for (uint256 j = usedKeyPairs - assignToOperator; j < usedKeyPairs; j++) {
                    (bytes memory key, bytes memory signature) = _loadKeyPair(operatorId, j);
                    keys = bytes.concat(keys, key);
                    signatures = bytes.concat(signatures, signature);
                    stateHash = keccak256(
                        abi.encodePacked(stateHash, "assignKey", operatorId, key)
                    );
                }

                if (toAssign == 0) {
                    break;
                }
            }
            index++;
        }

        (bool success, ) = payable(ethStakingStrategy).call{
            value: _totalValidatorCount * DEPOSIT_AMOUNT
        }("");
        require(success, "ETH transfer failed");

        currentStateHash = stateHash;
        totalAssignedValidators += _totalValidatorCount;
        totalActiveValidators += _totalValidatorCount;
        queueLength -= _totalValidatorCount;
        queueIndex = index;
    }

    /**
     * @notice Returns the next set of validator keys to be assigned
     * @param _validatorCount total number of validators to assign
     * @return keys validator keys to be assigned
     */
    function getNextValidators(uint256 _validatorCount) external view returns (bytes memory keys) {
        require(_validatorCount > 0, "Validator count must be greater than 0");
        require(_validatorCount <= queueLength, "Cannot assign more than queue length");

        uint256[] memory assignedToOperators = new uint256[](operators.length);
        uint256 toAssign = _validatorCount;
        uint256 index = queueIndex;

        while (index < queue.length) {
            uint256 numKeyPairs = queue[index].numKeyPairs;
            uint256 operatorId = queue[index].operatorId;

            if (numKeyPairs > 0 && operators[operatorId].active) {
                uint256 assignToOperator;

                if (numKeyPairs < toAssign) {
                    assignToOperator = numKeyPairs;
                    toAssign -= numKeyPairs;
                } else {
                    assignToOperator = toAssign;
                    toAssign = 0;
                }

                uint256 usedKeyPairs = operators[operatorId].usedKeyPairs +
                    assignedToOperators[operatorId];
                assignedToOperators[operatorId] += assignToOperator;

                for (uint256 j = usedKeyPairs; j < usedKeyPairs + assignToOperator; j++) {
                    (bytes memory key, ) = _loadKeyPair(operatorId, j);
                    keys = bytes.concat(keys, key);
                }

                if (toAssign == 0) {
                    break;
                }
            }
            index++;
        }
    }

    /**
     * @notice Reports lifetime stopped validators and ETH lost for a list of operators
     * @param _operatorIds list of operator ids to report for
     * @param _stoppedValidators list of lifetime stopped validators for each operator
     * @param _ethLost list of lifetime lost ETH sum for each operator
     */
    function reportStoppedValidators(
        uint256[] calldata _operatorIds,
        uint256[] calldata _stoppedValidators,
        uint256[] calldata _ethLost
    ) external onlyBeaconOracle {
        require(
            _operatorIds.length == _stoppedValidators.length &&
                _operatorIds.length == _ethLost.length,
            "Inconsistent list lengths"
        );

        uint256 totalNewlyStoppedValidators;
        uint256 totalNewlyLostETH;

        for (uint256 i = 0; i < _operatorIds.length; i++) {
            uint256 operatorId = _operatorIds[i];
            require(operatorId < operators.length, "Operator does not exist");
            require(
                _stoppedValidators[i] > operators[operatorId].stoppedValidators,
                "Reported negative or zero stopped validators"
            );
            require(_ethLost[i] >= ethLost[operatorId], "Reported negative lost ETH");
            require(
                _stoppedValidators[i] <= operators[operatorId].usedKeyPairs,
                "Reported more stopped validators than active"
            );

            rewardsPool.updateReward(operators[operatorId].owner);

            uint256 newlyStoppedValidators = _stoppedValidators[i] -
                operators[operatorId].stoppedValidators;
            uint256 newlyLostETH = _ethLost[i] - ethLost[operatorId];

            require(
                newlyLostETH <= newlyStoppedValidators * DEPOSIT_AMOUNT,
                "Reported more than max loss of 16 ETH per validator"
            );

            operators[operatorId].stoppedValidators += uint64(newlyStoppedValidators);
            ethLost[operatorId] += newlyLostETH;
            totalNewlyLostETH += newlyLostETH;

            if (operators[operatorId].active) {
                activeValidators[operators[operatorId].owner] -= newlyStoppedValidators;
                totalNewlyStoppedValidators += newlyStoppedValidators;
            }

            emit ReportStoppedValidators(operatorId, _stoppedValidators[i], _ethLost[i]);
        }

        totalActiveValidators -= totalNewlyStoppedValidators;
    }

    /**
     * @notice Withdraws an operator's stake
     * @param _operatorId id of operator
     * @param _amount amount to withdraw
     */
    function withdrawStake(
        uint256 _operatorId,
        uint256 _amount
    ) external operatorExists(_operatorId) {
        require(msg.sender == operators[_operatorId].owner, "Sender is not operator owner");
        require(_amount <= withdrawableStake(_operatorId), "Cannot withdraw more than available");

        ethWithdrawn[_operatorId] += _amount;
        IEthStakingStrategy(ethStakingStrategy).nwlWithdraw(msg.sender, _amount);

        emit WithdrawStake(_operatorId, _amount);
    }

    /**
     * @notice Returns the total withdrawable stake for an operator
     * @param _operatorId id of operator
     * @return withdrawableStake total withdrawable stake
     */
    function withdrawableStake(uint256 _operatorId) public view returns (uint256) {
        return
            operators[_operatorId].stoppedValidators *
            DEPOSIT_AMOUNT -
            (ethLost[_operatorId] + ethWithdrawn[_operatorId]);
    }
}
