// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import "./VaultV1.sol";

/**
 * @title Operator Vault
 * @notice Vault contract for depositing LINK collateral into the Chainlink staking controller as an operator
 */
contract OperatorVaultV1 is VaultV1 {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    address public operator;

    event AlertRaised();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _token,
        address _vaultController,
        address _stakeController,
        address _operator
    ) public reinitializer(2) {
        __Vault_init(_token, _vaultController, _stakeController);
        operator = _operator;
    }

    modifier onlyOperator() {
        require(operator == msg.sender, "Operator only");
        _;
    }

    /**
     * @notice returns the total balance of this contract in the Chainlink staking contract
     * @return total balance
     */
    function getTotalDeposits() public view override returns (uint256) {
        return
            stakeController.getStake(address(this)) +
            stakeController.getBaseReward(address(this)) +
            stakeController.getDelegationReward(address(this));
    }

    /**
     * @notice raises an alert in the Chainlink staking contract
     */
    function raiseAlert() external onlyOperator {
        stakeController.raiseAlert();
        token.safeTransfer(vaultController, token.balanceOf(address(this)));
        emit AlertRaised();
    }

    /**
     * @notice sets the operator address if not already set
     * @param _operator operator address
     */
    function setOperator(address _operator) external onlyOwner {
        require(operator == address(0), "Operator already set");
        operator = _operator;
    }
}
