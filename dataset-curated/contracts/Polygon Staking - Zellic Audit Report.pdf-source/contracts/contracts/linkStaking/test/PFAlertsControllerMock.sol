// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import "../../core/interfaces/IERC677.sol";

/**
 * @title Price Feed Alerts Controller
 * @dev Mocks contract for testing
 */
contract PFAlertsControllerMock {
    IERC677 public token;

    constructor(address _token) {
        token = IERC677(_token);
    }

    function raiseAlert(address) external {
        token.transfer(msg.sender, 13 ether);
    }
}
