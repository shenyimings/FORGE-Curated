// SPDX-License-Identifier: GNU General Public License Version 3
// See license at: https://github.com/forta-network/forta-firewall-contracts/blob/master/LICENSE-GPLv3.md

pragma solidity ^0.8.25;

interface IFirewallAccess {
    function isFirewallAdmin(address caller) external view returns (bool);
    function isProtocolAdmin(address caller) external view returns (bool);
    function isCheckpointManager(address caller) external view returns (bool);
    function isLogicUpgrader(address caller) external view returns (bool);
    function isCheckpointExecutor(address caller) external view returns (bool);
    function isAttesterManager(address caller) external view returns (bool);
    function isTrustedAttester(address caller) external view returns (bool);
}
