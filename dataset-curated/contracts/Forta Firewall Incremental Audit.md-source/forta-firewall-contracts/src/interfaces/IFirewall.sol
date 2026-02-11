// SPDX-License-Identifier: GNU General Public License Version 3
// See license at: https://github.com/forta-network/forta-firewall-contracts/blob/master/LICENSE-GPLv3.md

pragma solidity ^0.8.25;

import "./ISecurityValidator.sol";
import "./IFirewallAccess.sol";
import "./Checkpoint.sol";
import "./ICheckpointHook.sol";

interface IFirewall {
    event SecurityConfigUpdated(ISecurityValidator indexed validator, IFirewallAccess indexed firewallAccess);
    event SupportsTrustedOrigin(address indexed firewall);
    event CheckpointUpdated(bytes4 selector, Checkpoint checkpoint);

    function updateFirewallConfig(
        ISecurityValidator _validator,
        ICheckpointHook _checkpointHook,
        bytes32 _attesterControllerId,
        IFirewallAccess _firewallAccess
    ) external;

    function getFirewallConfig()
        external
        view
        returns (
            ISecurityValidator _validator,
            ICheckpointHook _checkpointHook,
            bytes32 _attesterControllerId,
            IFirewallAccess _firewallAccess
        );

    function setCheckpoint(bytes4 selector, Checkpoint memory checkpoint) external;

    function setCheckpointActivation(bytes4 selector, Activation activation) external;

    function getCheckpoint(bytes4 selector) external view returns (uint192, uint16, uint16, Activation, bool);

    function attestedCall(Attestation calldata attestation, bytes calldata attestationSignature, bytes calldata data)
        external
        returns (bytes memory);
}
