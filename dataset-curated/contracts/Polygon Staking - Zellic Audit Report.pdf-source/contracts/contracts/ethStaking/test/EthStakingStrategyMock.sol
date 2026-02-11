// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import "../interfaces/INWLOperatorController.sol";

contract EthStakingStrategyMock {
    address public nwlOperatorController;

    receive() external payable {}

    function depositEther(uint256 _totalValidatorCount) external {
        INWLOperatorController(nwlOperatorController).assignNextValidators(_totalValidatorCount);
    }

    function nwlWithdraw(address, uint256) external {
        require(
            msg.sender == address(nwlOperatorController),
            "Sender is not non-whitelisted operator controller"
        );
    }

    function setNWLOperatorController(address _nwlOperatorController) external {
        nwlOperatorController = _nwlOperatorController;
    }
}
