// SPDX-License-Identifier: GNU General Public License Version 3
// See license at: https://github.com/forta-network/forta-firewall-contracts/blob/master/LICENSE-GPLv3.md

pragma solidity ^0.8.25;

import {Proxy} from "@openzeppelin/contracts/proxy/Proxy.sol";
import {StorageSlot} from "@openzeppelin/contracts/utils/StorageSlot.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";
import {FirewallPermissions} from "./FirewallPermissions.sol";
import {Quantization} from "./Quantization.sol";
import "./interfaces/IFirewall.sol";
import "./interfaces/FirewallDependencies.sol";
import "./interfaces/IAttesterInfo.sol";

/**
 * @notice Firewall is a base contract which provides protection against exploits.
 * It keeps a collection of configurable checkpoints per function, in its namespaced storage,
 * and makes available internal functions to the child contract in order to help intercept
 * function calls.
 *
 * When a function call is intercepted, one of the arguments can be used as a reference to compare
 * with a configured threshold. Exceeding the threshold causes checkpoint execution which requires
 * a corresponding attestation to be present in the SecurityValidator.
 */
abstract contract Firewall is IFirewall, IAttesterInfo, FirewallPermissions {
    using StorageSlot for bytes32;
    using Quantization for uint256;

    error InvalidActivationType();
    error UntrustedAttester(address attester);
    error CheckpointBlocked();

    struct FirewallStorage {
        ISecurityValidator validator;
        ICheckpointHook checkpointHook;
        bytes32 attesterControllerId;
        mapping(bytes4 funcSelector => Checkpoint checkpoint) checkpoints;
    }

    /// @custom:storage-location erc7201:forta.Firewall.storage
    bytes32 private constant STORAGE_SLOT = 0x993f81a6354aa9d98fa5ac249e63371dfc7f5589eeb8a5b081145c8ed289c400;

    /**
     * @notice Updates the firewall config.
     * @param _validator Validator used for checkpoint execution calls.
     * @param _checkpointHook Checkpoint hook contract which is called before every checkpoint.
     * @param _attesterControllerId The ID of the external controller which keeps settings related
     * to the attesters.
     * @param _firewallAccess Firewall access controller.
     */
    function updateFirewallConfig(
        ISecurityValidator _validator,
        ICheckpointHook _checkpointHook,
        bytes32 _attesterControllerId,
        IFirewallAccess _firewallAccess
    ) public virtual onlyFirewallAdmin {
        _updateFirewallConfig(_validator, _checkpointHook, _attesterControllerId, _firewallAccess);
    }

    /**
     * @notice Updates the firewall config.
     * @param _validator The security validator which the firewall calls for saving
     * the attestation and executing checkpoints.
     * @param _checkpointHook Checkpoint hook contract which is called before every checkpoint.
     * @param _attesterControllerId The id of the controller that lives on Forta chain. Attesters
     * regards this value to find out the settings for this contract before creating an attestation.
     * @param _firewallAccess The access control contract that knows the accounts which can manage
     * the settings of a firewall.
     */
    function _updateFirewallConfig(
        ISecurityValidator _validator,
        ICheckpointHook _checkpointHook,
        bytes32 _attesterControllerId,
        IFirewallAccess _firewallAccess
    ) internal virtual {
        FirewallStorage storage $ = _getFirewallStorage();
        $.validator = _validator;
        $.checkpointHook = _checkpointHook;
        $.attesterControllerId = _attesterControllerId;
        _updateFirewallAccess(_firewallAccess);
        emit SecurityConfigUpdated(_validator, _firewallAccess);
        emit AttesterControllerUpdated(_attesterControllerId);
    }

    /**
     * @notice Returns the firewall configuration.
     * @return validator The security validator which the firewall calls for saving
     * the attestation and executing checkpoints.
     * @return checkpointHook Checkpoint hook contract which is called before every checkpoint.
     * @return attesterControllerId The id of the controller that lives on Forta chain. Attesters
     * regards this value to find out the settings for this contract before creating an attestation.
     * @return firewallAccess The access control contract that knows the accounts which can manage
     * the settings of a firewall.
     */
    function getFirewallConfig()
        public
        view
        returns (
            ISecurityValidator validator,
            ICheckpointHook checkpointHook,
            bytes32 attesterControllerId,
            IFirewallAccess firewallAccess
        )
    {
        FirewallStorage storage $ = _getFirewallStorage();
        firewallAccess = _getFirewallAccess();
        return ($.validator, $.checkpointHook, $.attesterControllerId, firewallAccess);
    }

    /**
     * @notice Returns the attester controller id from the configuration.
     */
    function getAttesterControllerId() public view returns (bytes32) {
        return _getFirewallStorage().attesterControllerId;
    }

    /**
     * @notice Sets checkpoint values for given function selector, call data byte range
     * and with given threshold type.
     * @param selector Selector of the function.
     * @param checkpoint Checkpoint data.
     */
    function setCheckpoint(bytes4 selector, Checkpoint memory checkpoint) public virtual onlyCheckpointManager {
        require(checkpoint.refStart <= checkpoint.refEnd, "refStart is larger than refEnd");
        _getFirewallStorage().checkpoints[selector] = checkpoint;
    }

    /**
     * @notice Sets the checkpoint activation type.
     * @param selector Selector of the function.
     * @param activation Activation type.
     */
    function setCheckpointActivation(bytes4 selector, Activation activation) public virtual onlyCheckpointManager {
        _getFirewallStorage().checkpoints[selector].activation = activation;
    }

    /**
     * @notice Gets the checkpoint values for given function selector.
     * @param selector Selector of the function.
     */
    function getCheckpoint(bytes4 selector) public view virtual returns (uint192, uint16, uint16, Activation, bool) {
        Checkpoint storage checkpoint = _getFirewallStorage().checkpoints[selector];
        return (
            checkpoint.threshold,
            checkpoint.refStart,
            checkpoint.refEnd,
            checkpoint.activation,
            checkpoint.trustedOrigin
        );
    }

    /**
     * @notice Helps write an attestation and call any function of this contract.
     * @param attestation The set of fields that correspond to and enable the execution of call(s)
     * @param attestationSignature Signature of EIP-712 message
     * @param data Call data which contains the function selector and the encoded arguments
     */
    function attestedCall(Attestation calldata attestation, bytes calldata attestationSignature, bytes calldata data)
        public
        returns (bytes memory)
    {
        _getFirewallStorage().validator.saveAttestation(attestation, attestationSignature);
        return Address.functionDelegateCall(address(this), data);
    }

    function _secureExecution() internal virtual {
        Checkpoint memory checkpoint = _getFirewallStorage().checkpoints[msg.sig];
        require(checkpoint.refEnd <= msg.data.length, "refEnd too large for slicing");
        /// Default to msg data length.
        uint256 refEnd = checkpoint.refEnd;
        if (refEnd > msg.data.length) refEnd = msg.data.length;
        if (msg.sig == 0 || (checkpoint.refEnd == 0 && checkpoint.refStart == 0)) {
            /// Ether transaction or paid transaction with no ref range: use msg.value as ref
            _secureExecution(msg.sender, msg.sig, msg.value);
        } else if (refEnd - checkpoint.refStart > 32) {
            /// Support larger data ranges as direct input hashes instead of deriving a reference.
            bytes calldata byteRange = msg.data[checkpoint.refStart:checkpoint.refEnd];
            bytes32 input = keccak256(byteRange);
            _secureExecution(msg.sender, msg.sig, input);
        } else {
            bytes calldata byteRange = msg.data[checkpoint.refStart:checkpoint.refEnd];
            uint256 ref = uint256(bytes32(byteRange));
            _secureExecution(msg.sender, msg.sig, ref);
        }
    }

    function _secureExecution(address caller, bytes4 selector, uint256 ref) internal virtual {
        Checkpoint memory checkpoint = _getFirewallStorage().checkpoints[selector];
        bool ok;
        (ref, ok) = _checkpointActivated(checkpoint, caller, selector, ref);
        if (ok) _executeCheckpoint(checkpoint, caller, bytes32(ref.quantize()), selector);
    }

    function _secureExecution(address caller, bytes4 selector, bytes32 input) internal virtual {
        Checkpoint memory checkpoint = _getFirewallStorage().checkpoints[selector];
        bool ok = _checkpointActivated(checkpoint);
        if (ok) _executeCheckpoint(checkpoint, caller, input, selector);
    }

    function _executeCheckpoint(Checkpoint memory checkpoint, address caller, bytes32 input, bytes4 selector)
        internal
        virtual
    {
        FirewallStorage storage $ = _getFirewallStorage();

        /// Short-circuit if the trusted origin pattern is supported and is available.
        /// Otherwise, continue with checkpoint execution.
        if (_isTrustedOrigin(checkpoint)) return;

        $.validator.executeCheckpoint(keccak256(abi.encode(caller, address(this), selector, input)));

        /// Ensure first that the current attester can be trusted.
        /// If the current attester is zero address, let the security validator deal with that.
        address currentAttester = $.validator.getCurrentAttester();
        if (currentAttester != address(0) && !_isTrustedAttester(currentAttester)) {
            revert UntrustedAttester(currentAttester);
        }
    }

    function _checkpointActivated(Checkpoint memory checkpoint, address caller, bytes4 selector, uint256 ref)
        internal
        virtual
        returns (uint256, bool)
    {
        ICheckpointHook checkpointHook = _getFirewallStorage().checkpointHook;
        if (address(checkpointHook) != address(0)) {
            HookResult result = checkpointHook.handleCheckpoint(caller, selector, ref);
            if (result == HookResult.ForceActivation) return (ref, true);
            if (result == HookResult.ForceDeactivation) return (ref, false);
            // Otherwise, just keep on with default checkpoint configuration and logic.
        }
        if (checkpoint.activation == Activation.Inactive) return (ref, false);
        if (checkpoint.activation == Activation.AlwaysBlocked) revert CheckpointBlocked();
        if (checkpoint.activation == Activation.AlwaysActive) return (ref, true);
        if (checkpoint.activation == Activation.ConstantThreshold) return (ref, ref >= checkpoint.threshold);
        if (checkpoint.activation != Activation.AccumulatedThreshold) {
            revert InvalidActivationType();
        }
        /// Continue with the "accumulated threshold" logic.
        bytes32 slot = keccak256(abi.encode(selector, msg.sender));
        uint256 acc = StorageSlot.tload(slot.asUint256());
        acc += ref;
        StorageSlot.tstore(slot.asUint256(), acc);
        return (ref, acc >= checkpoint.threshold);
    }

    function _checkpointActivated(Checkpoint memory checkpoint) internal pure virtual returns (bool) {
        if (checkpoint.activation == Activation.Inactive) return false;
        if (checkpoint.activation == Activation.AlwaysBlocked) revert CheckpointBlocked();
        if (checkpoint.activation == Activation.AlwaysActive) return true;
        return false;
    }

    function _isTrustedOrigin(Checkpoint memory checkpoint) internal virtual returns (bool) {
        if (checkpoint.trustedOrigin) {
            emit SupportsTrustedOrigin(address(this));
            return _isTrustedAttester(tx.origin);
        }
        return false;
    }

    function _getFirewallStorage() internal pure virtual returns (FirewallStorage storage $) {
        assembly {
            $.slot := STORAGE_SLOT
        }
    }
}
