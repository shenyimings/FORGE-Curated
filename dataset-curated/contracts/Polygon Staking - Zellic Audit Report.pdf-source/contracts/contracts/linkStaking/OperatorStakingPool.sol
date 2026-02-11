// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import "../core/interfaces/IStakingPool.sol";

/**
 * @title Operator Staking Pool
 * @notice Tracks node operator LST balances for the purpose of differentiating from community LST balances
 * @dev node operators are required to stake their LSTs into this contract
 */
contract OperatorStakingPool is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    // address of liquid staking token
    IStakingPool public lst;

    // list of whitelisted operators
    address[] private operators;
    // used to check membership of operators in this pool
    mapping(address => bool) private operatorMap;

    // stores the LST share balance for each operator
    mapping(address => uint256) private shareBalances;
    // total number of LST shares staked in this pool
    uint256 private totalShares;

    // max LST deposits per operator
    uint256 public depositLimit;

    event Deposit(address account, uint256 amount, uint256 sharesAmount);
    event Withdraw(address account, uint256 amount, uint256 sharesAmount);

    error SenderNotAuthorized();
    error OperatorAlreadyAdded();
    error OperatorNotFound();
    error InvalidToken();
    error ExceedsDepositLimit();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes contract
     * @param _lst address of liquid staking token
     * @param _depositLimit max LST deposits per operator
     **/
    function initialize(address _lst, uint256 _depositLimit) public initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();
        lst = IStakingPool(_lst);
        depositLimit = _depositLimit;
    }

    /**
     * @notice Returns a list of all operators
     * @return list of operators
     **/
    function getOperators() external view returns (address[] memory) {
        return operators;
    }

    /**
     * @notice Returns an operator's principal staked balance
     * @param _operator address of operator
     * @return principal staked amount
     **/
    function getOperatorPrincipal(address _operator) public view returns (uint256) {
        uint256 balance = lst.getStakeByShares(shareBalances[_operator]);
        return balance > depositLimit ? depositLimit : balance;
    }

    /**
     * @notice Returns an operator's total staked balance
     * @param _operator address of operator
     * @return staked amount
     **/
    function getOperatorStaked(address _operator) public view returns (uint256) {
        return lst.getStakeByShares(shareBalances[_operator]);
    }

    /**
     * @notice Returns the total principal staked amount
     * @return total principal staked amount
     **/
    function getTotalPrincipal() external view returns (uint256) {
        uint256 numOperators = operators.length;
        uint256 total;

        for (uint256 i = 0; i < numOperators; ++i) {
            total += getOperatorPrincipal(operators[i]);
        }

        return total;
    }

    /**
     * @notice Returns the total staked amount
     * @return total staked amount
     **/
    function getTotalStaked() external view returns (uint256) {
        return lst.getStakeByShares(totalShares);
    }

    /**
     * @notice ERC677 implementation to receive deposits
     * @param _sender address of sender
     * @param _value amount of tokens to deposit
     **/
    function onTokenTransfer(address _sender, uint256 _value, bytes calldata) external {
        if (msg.sender != address(lst)) revert InvalidToken();
        if (!isOperator(_sender)) revert SenderNotAuthorized();
        if (getOperatorStaked(_sender) + _value > depositLimit) revert ExceedsDepositLimit();

        uint256 sharesAmount = lst.getSharesByStake(_value);
        shareBalances[_sender] += sharesAmount;
        totalShares += sharesAmount;

        emit Deposit(_sender, _value, sharesAmount);
    }

    /**
     * @notice Withdraws tokens
     * @param _amount amount to withdraw
     **/
    function withdraw(uint256 _amount) external {
        if (!isOperator(msg.sender)) revert SenderNotAuthorized();
        _withdraw(msg.sender, _amount);
    }

    /**
     * @notice Returns whether an account is an operator
     * @return true if account is operator, false otherwise
     **/
    function isOperator(address _account) public view returns (bool) {
        return operatorMap[_account];
    }

    /**
     * @notice Adds new operators
     * @param _operators list of operators to add
     **/
    function addOperators(address[] calldata _operators) external onlyOwner {
        for (uint256 i = 0; i < _operators.length; ++i) {
            address operator = _operators[i];
            if (isOperator(operator)) revert OperatorAlreadyAdded();

            operatorMap[operator] = true;
            operators.push(operator);
        }
    }

    /**
     * @notice Removes existing operators
     * @param _operators list of operators to remove
     **/
    function removeOperators(address[] calldata _operators) external onlyOwner {
        uint256 numOperators = operators.length;

        for (uint256 i = 0; i < _operators.length; ++i) {
            address operator = _operators[i];
            if (!isOperator(operator)) revert OperatorNotFound();

            uint256 staked = getOperatorStaked(operator);
            if (staked != 0) {
                _withdraw(operator, staked);
            }

            operatorMap[operator] = false;
            for (uint256 j = 0; j < numOperators; ++j) {
                if (operators[j] == operator) {
                    operators[j] = operators[numOperators - 1];
                    operators.pop();
                    --numOperators;
                }
            }
        }
    }

    /**
     * @notice Sets the deposit limit
     * @param _depositLimit max amount of deposits per operator
     **/
    function setDepositLimit(uint256 _depositLimit) external onlyOwner {
        depositLimit = _depositLimit;
    }

    /**
     * @notice Withdraws tokens
     * @param _operator address of operator to withdraw for
     * @param _amount amount to withdraw
     **/
    function _withdraw(address _operator, uint256 _amount) private {
        uint256 sharesAmount = lst.getSharesByStake(_amount);
        shareBalances[_operator] -= sharesAmount;
        totalShares -= sharesAmount;

        lst.transferShares(_operator, sharesAmount);

        emit Withdraw(_operator, _amount, sharesAmount);
    }

    /**
     * @dev Checks authorization for contract upgrades
     */
    function _authorizeUpgrade(address) internal override onlyOwner {}
}
