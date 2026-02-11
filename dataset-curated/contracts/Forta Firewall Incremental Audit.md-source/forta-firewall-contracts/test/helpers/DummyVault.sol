// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "evc/interfaces/IVault.sol";
import {Checkpoint, Activation, ICheckpointHook} from "../../src/Firewall.sol";
import {InternalFirewall} from "../../src/InternalFirewall.sol";
import {ISecurityValidator} from "../../src/SecurityValidator.sol";
import {IFirewallAccess} from "../../src/FirewallAccess.sol";

bytes32 constant DoFirstCheckpoint = keccak256("doFirst");
bytes32 constant DoSecondCheckpoint = keccak256("doSecond");

contract DummySecurityAccess {
    function isSecurityAdmin(address) public pure returns (bool) {
        return true;
    }

    function isCheckpointManager(address) external pure returns (bool) {
        return true;
    }

    function isLogicUpgrader(address) external pure returns (bool) {
        return true;
    }

    function isTrustedAttester(address) public pure returns (bool) {
        return true;
    }
}

interface IDummyVault {
    function doFirst(uint256 amount) external;
    function doSecond(uint256 amount) external;
}

contract DummyVault is IVault, IDummyVault, InternalFirewall {
    constructor(ISecurityValidator _validator)
        InternalFirewall(_validator, ICheckpointHook(address(0)), bytes32(0), _initSecurityAccess())
    {
        Checkpoint memory checkpoint;
        checkpoint.threshold = 0;
        checkpoint.refStart = 4;
        checkpoint.refEnd = 36;
        checkpoint.activation = Activation.ConstantThreshold;
        checkpoint.trustedOrigin = false;
        setCheckpoint(IDummyVault.doFirst.selector, checkpoint);
        setCheckpoint(IDummyVault.doSecond.selector, checkpoint);
    }

    function _initSecurityAccess() private returns (IFirewallAccess) {
        return IFirewallAccess(address(new DummySecurityAccess()));
    }

    function disableController() public {}

    function checkAccountStatus(address, address[] calldata) public pure returns (bytes4 magicValue) {
        return 0xb168c58f;
    }

    function checkVaultStatus() public pure returns (bytes4 magicValue) {
        return 0x4b3d1223;
    }

    function doFirst(uint256 amount) public {
        _secureExecution(msg.sender, msg.sig, amount);
    }

    function doSecond(uint256 amount) public {
        _secureExecution(msg.sender, msg.sig, amount);
    }
}
