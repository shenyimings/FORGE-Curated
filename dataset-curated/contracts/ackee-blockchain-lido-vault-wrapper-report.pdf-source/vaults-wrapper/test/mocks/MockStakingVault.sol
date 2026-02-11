// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title MockStakingVault
 * @notice Mock contract for testing StakingVault
 */
contract MockStakingVault {
    address public nodeOperator;
    uint256 public totalAssets;

    event Funded(address indexed sender, uint256 amount);
    event StakingVaultFunded(address sender, uint256 amount);

    constructor() {
        nodeOperator = address(0x123);
    }

    receive() external payable {}

    function fund() external payable {
        emit StakingVaultFunded(msg.sender, msg.value);
        totalAssets += msg.value;
        emit Funded(msg.sender, msg.value);
    }

    function setNodeOperator(address _nodeOperator) external {
        nodeOperator = _nodeOperator;
    }

    function setTotalAssets(uint256 _totalAssets) external {
        totalAssets = _totalAssets;
    }

    function withdraw(address recipient, uint256 amount) external {
        // require(msg.sender == nodeOperator, "Not node operator");
        (bool success,) = recipient.call{value: amount}("");
        require(success, "Transfer failed");
    }

    function triggerValidatorWithdrawals(
        bytes calldata pubkeys,
        uint64[] calldata amountsInGwei,
        address refundRecipient
    ) external payable {
        // Mock implementation
    }

    function availableBalance() external view returns (uint256) {
        return address(this).balance;
    }
}
