// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

interface IPFAlertsController {
    function raiseAlert(address _feed) external;
}
