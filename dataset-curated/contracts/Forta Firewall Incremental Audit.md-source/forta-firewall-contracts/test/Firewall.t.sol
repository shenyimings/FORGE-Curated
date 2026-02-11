// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {Test, console, Vm} from "forge-std/Test.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Firewall} from "../src/Firewall.sol";
import {
    FIREWALL_ADMIN_ROLE,
    PROTOCOL_ADMIN_ROLE,
    ATTESTER_MANAGER_ROLE,
    TRUSTED_ATTESTER_ROLE
} from "../src/FirewallAccess.sol";
import {Quantization} from "../src/Quantization.sol";
import "../src/interfaces/Checkpoint.sol";
import "../src/interfaces/FirewallDependencies.sol";

contract FirewallImpl is Firewall {
    constructor(
        ISecurityValidator _validator,
        ICheckpointHook _checkpointHook,
        bytes32 _attesterControllerId,
        IFirewallAccess _firewallAccess
    ) {
        _updateFirewallConfig(_validator, _checkpointHook, _attesterControllerId, _firewallAccess);
    }

    function secureExecution(uint256) public {
        _secureExecution();
    }

    function secureExecutionWithRef(uint256 ref) public {
        _secureExecution(msg.sender, msg.sig, ref);
    }

    function secureExecutionWithRefAndSelector(bytes4 selector, uint256 ref) public {
        _secureExecution(msg.sender, selector, ref);
    }
}

contract FirewallTest is Test {
    bytes32 constant attesterControllerId = bytes32(uint256(123));

    address constant mockValidator = address(uint160(234));
    address constant mockAccess = address(uint160(345));
    address constant testAttester = address(uint160(456));
    address constant mockHook = address(uint160(567));

    FirewallImpl firewall;

    Checkpoint checkpoint =
        Checkpoint({threshold: 1, refStart: 2, refEnd: 3, activation: Activation.AlwaysActive, trustedOrigin: true});

    function setUp() public {
        firewall = new FirewallImpl(
            ISecurityValidator(mockValidator),
            ICheckpointHook(mockHook),
            attesterControllerId,
            IFirewallAccess(mockAccess)
        );
    }

    function testFirewall_setCheckpointWithSelector() public {
        vm.mockCall(
            address(mockAccess),
            abi.encodeWithSelector(IFirewallAccess.isCheckpointManager.selector, address(this)),
            abi.encode(true)
        );
        firewall.setCheckpoint(0xaaaaaaaa, checkpoint);
        (uint192 threshold, uint16 refStart, uint16 refEnd, Activation activation, bool trustedOrigin) =
            firewall.getCheckpoint(0xaaaaaaaa);
        assertEq(checkpoint.threshold, threshold);
        assertEq(checkpoint.refStart, refStart);
        assertEq(checkpoint.refEnd, refEnd);
        assertEq(uint8(checkpoint.activation), uint8(activation));
        assertEq(checkpoint.trustedOrigin, trustedOrigin);

        vm.mockCall(
            address(mockAccess),
            abi.encodeWithSelector(IFirewallAccess.isCheckpointManager.selector, address(this)),
            abi.encode(true)
        );
        firewall.setCheckpointActivation(0xaaaaaaaa, Activation.AlwaysBlocked);
        (,,, activation,) = firewall.getCheckpoint(0xaaaaaaaa);
        assertEq(uint8(Activation.AlwaysBlocked), uint8(activation));

        /// Refuse access.
        vm.mockCall(
            address(mockAccess),
            abi.encodeWithSelector(IFirewallAccess.isCheckpointManager.selector, address(this)),
            abi.encode(false)
        );
        vm.expectRevert();
        firewall.setCheckpoint(0xaaaaaaaa, checkpoint);

        /// Refuse access.
        vm.mockCall(
            address(mockAccess),
            abi.encodeWithSelector(IFirewallAccess.isCheckpointManager.selector, address(this)),
            abi.encode(false)
        );
        vm.expectRevert();
        firewall.setCheckpointActivation(0xaaaaaaaa, Activation.AlwaysBlocked);
    }

    function testFirewall_setCheckpointInvalidRefRange() public {
        vm.mockCall(
            address(mockAccess),
            abi.encodeWithSelector(IFirewallAccess.isCheckpointManager.selector, address(this)),
            abi.encode(true)
        );
        checkpoint.refStart = 2;
        checkpoint.refEnd = 1;
        vm.expectRevert();
        firewall.setCheckpoint(0xaaaaaaaa, checkpoint);
    }

    function testFirewall_getAttesterControllerId() public view {
        assertEq(attesterControllerId, firewall.getAttesterControllerId());
    }

    function testFirewall_updateFirewallConfig() public {
        address newValidator = address(uint160(777));
        bytes32 newControllerId = bytes32(uint256(888));
        address newAccess = address(uint160(999));
        address newHook = address(uint160(1010));

        /// Refuse access.
        vm.mockCall(
            address(mockAccess),
            abi.encodeWithSelector(IFirewallAccess.isFirewallAdmin.selector, address(this)),
            abi.encode(false)
        );
        vm.expectRevert();
        firewall.updateFirewallConfig(
            ISecurityValidator(newValidator), ICheckpointHook(newHook), newControllerId, IFirewallAccess(newAccess)
        );

        /// Grant access.
        vm.mockCall(
            address(mockAccess),
            abi.encodeWithSelector(IFirewallAccess.isFirewallAdmin.selector, address(this)),
            abi.encode(true)
        );
        firewall.updateFirewallConfig(
            ISecurityValidator(newValidator), ICheckpointHook(newHook), newControllerId, IFirewallAccess(newAccess)
        );

        (ISecurityValidator validator, ICheckpointHook checkpointHook, bytes32 controllerId, IFirewallAccess access) =
            firewall.getFirewallConfig();
        assertEq(newValidator, address(validator));
        assertEq(newHook, address(checkpointHook));
        assertEq(newControllerId, controllerId);
        assertEq(newAccess, address(access));
    }

    function testFirewall_secureExecution() public {
        vm.mockCall(
            address(mockAccess),
            abi.encodeWithSelector(IFirewallAccess.isCheckpointManager.selector, address(this)),
            abi.encode(true)
        );
        Checkpoint memory chk = Checkpoint({
            threshold: 2,
            refStart: 4,
            refEnd: 36,
            activation: Activation.ConstantThreshold,
            trustedOrigin: false
        });
        firewall.setCheckpoint(FirewallImpl.secureExecution.selector, chk);
        uint256 arg = 3;
        bytes32 checkpointHash = keccak256(
            abi.encode(
                address(this), address(firewall), FirewallImpl.secureExecution.selector, Quantization.quantize(arg)
            )
        );
        vm.mockCall(
            address(mockValidator),
            abi.encodeWithSelector(ISecurityValidator.getCurrentAttester.selector),
            abi.encode(testAttester)
        );
        vm.mockCall(
            address(mockAccess),
            abi.encodeWithSelector(IFirewallAccess.isTrustedAttester.selector, address(testAttester)),
            abi.encode(true)
        );
        vm.mockCall(
            address(mockHook),
            abi.encodeWithSelector(
                ICheckpointHook.handleCheckpoint.selector, address(this), FirewallImpl.secureExecution.selector, arg
            ),
            abi.encode(HookResult.Inconclusive)
        );
        vm.mockCall(
            address(mockValidator),
            abi.encodeWithSelector(ISecurityValidator.executeCheckpoint.selector, checkpointHash),
            abi.encode(keccak256(abi.encode(checkpointHash, address(firewall), bytes32(0))))
        );
        firewall.secureExecution(arg);
    }

    function testFirewall_secureExecutionLargeRange() public {
        vm.mockCall(
            address(mockAccess),
            abi.encodeWithSelector(IFirewallAccess.isCheckpointManager.selector, address(this)),
            abi.encode(true)
        );
        Checkpoint memory chk = Checkpoint({
            threshold: 2,
            /// The data range below is larger than 32.
            refStart: 0,
            refEnd: 36,
            activation: Activation.ConstantThreshold,
            trustedOrigin: false
        });
        firewall.setCheckpoint(FirewallImpl.secureExecution.selector, chk);
        uint256 arg = 3;
        /// Should use a hash input instead of quantized reference.
        bytes32 checkpointHashInput = keccak256(abi.encodeWithSelector(firewall.secureExecution.selector, arg));
        bytes32 checkpointHash = keccak256(
            abi.encode(address(this), address(firewall), FirewallImpl.secureExecution.selector, checkpointHashInput)
        );
        vm.mockCall(
            address(mockValidator),
            abi.encodeWithSelector(ISecurityValidator.getCurrentAttester.selector),
            abi.encode(testAttester)
        );
        vm.mockCall(
            address(mockAccess),
            abi.encodeWithSelector(IFirewallAccess.isTrustedAttester.selector, address(testAttester)),
            abi.encode(true)
        );
        vm.mockCall(
            address(mockHook),
            abi.encodeWithSelector(
                ICheckpointHook.handleCheckpoint.selector, address(this), FirewallImpl.secureExecution.selector, arg
            ),
            abi.encode(HookResult.Inconclusive)
        );
        vm.mockCall(
            address(mockValidator),
            abi.encodeWithSelector(ISecurityValidator.executeCheckpoint.selector, checkpointHash),
            abi.encode(keccak256(abi.encode(checkpointHash, address(firewall), bytes32(0))))
        );
        firewall.secureExecution(arg);
    }

    function testFirewall_secureExecutionWithRef() public {
        vm.mockCall(
            address(mockAccess),
            abi.encodeWithSelector(IFirewallAccess.isCheckpointManager.selector, address(this)),
            abi.encode(true)
        );
        Checkpoint memory chk = Checkpoint({
            threshold: 2,
            refStart: 4,
            refEnd: 36,
            activation: Activation.ConstantThreshold,
            trustedOrigin: false
        });
        firewall.setCheckpoint(FirewallImpl.secureExecutionWithRef.selector, chk);
        uint256 arg = 3;
        bytes32 checkpointHash = keccak256(
            abi.encode(
                address(this),
                address(firewall),
                FirewallImpl.secureExecutionWithRef.selector,
                Quantization.quantize(arg)
            )
        );
        vm.mockCall(
            address(mockValidator),
            abi.encodeWithSelector(ISecurityValidator.getCurrentAttester.selector),
            abi.encode(testAttester)
        );
        vm.mockCall(
            address(mockAccess),
            abi.encodeWithSelector(IFirewallAccess.isTrustedAttester.selector, address(testAttester)),
            abi.encode(true)
        );
        vm.mockCall(
            address(mockHook),
            abi.encodeWithSelector(
                ICheckpointHook.handleCheckpoint.selector,
                address(this),
                FirewallImpl.secureExecutionWithRef.selector,
                arg
            ),
            abi.encode(HookResult.Inconclusive)
        );
        vm.mockCall(
            address(mockValidator),
            abi.encodeWithSelector(ISecurityValidator.executeCheckpoint.selector, checkpointHash),
            abi.encode(keccak256(abi.encode(checkpointHash, address(firewall), bytes32(0))))
        );
        firewall.secureExecutionWithRef(arg);
    }

    function testFirewall_secureExecutionWithRefAndSelector() public {
        vm.mockCall(
            address(mockAccess),
            abi.encodeWithSelector(IFirewallAccess.isCheckpointManager.selector, address(this)),
            abi.encode(true)
        );
        Checkpoint memory chk = Checkpoint({
            threshold: 2,
            refStart: 4,
            refEnd: 36,
            activation: Activation.ConstantThreshold,
            trustedOrigin: false
        });
        firewall.setCheckpoint(0xaaaaaaaa, chk);
        uint256 arg = 3;
        bytes32 checkpointHash =
            keccak256(abi.encode(address(this), address(firewall), bytes4(0xaaaaaaaa), Quantization.quantize(arg)));
        vm.mockCall(
            address(mockValidator),
            abi.encodeWithSelector(ISecurityValidator.getCurrentAttester.selector),
            abi.encode(testAttester)
        );
        vm.mockCall(
            address(mockAccess),
            abi.encodeWithSelector(IFirewallAccess.isTrustedAttester.selector, address(testAttester)),
            abi.encode(true)
        );
        vm.mockCall(
            address(mockHook),
            abi.encodeWithSelector(ICheckpointHook.handleCheckpoint.selector, address(this), bytes4(0xaaaaaaaa), arg),
            abi.encode(HookResult.Inconclusive)
        );
        vm.mockCall(
            address(mockValidator),
            abi.encodeWithSelector(ISecurityValidator.executeCheckpoint.selector, checkpointHash),
            abi.encode(keccak256(abi.encode(checkpointHash, address(firewall), bytes32(0))))
        );
        firewall.secureExecutionWithRefAndSelector(0xaaaaaaaa, arg);
    }

    function testFirewall_hookForceActivation() public {
        vm.mockCall(
            address(mockAccess),
            abi.encodeWithSelector(IFirewallAccess.isCheckpointManager.selector, address(this)),
            abi.encode(true)
        );
        Checkpoint memory chk = Checkpoint({
            threshold: 2,
            refStart: 4,
            refEnd: 36,
            activation: Activation.ConstantThreshold,
            trustedOrigin: false
        });
        firewall.setCheckpoint(FirewallImpl.secureExecution.selector, chk);
        uint256 arg = 3;
        bytes32 checkpointHash = keccak256(
            abi.encode(
                address(this), address(firewall), FirewallImpl.secureExecution.selector, Quantization.quantize(arg)
            )
        );
        vm.mockCall(
            address(mockValidator),
            abi.encodeWithSelector(ISecurityValidator.getCurrentAttester.selector),
            abi.encode(testAttester)
        );
        vm.mockCall(
            address(mockAccess),
            abi.encodeWithSelector(IFirewallAccess.isTrustedAttester.selector, address(testAttester)),
            abi.encode(true)
        );
        vm.mockCall(
            address(mockHook),
            abi.encodeWithSelector(
                ICheckpointHook.handleCheckpoint.selector, address(this), FirewallImpl.secureExecution.selector, arg
            ),
            abi.encode(HookResult.ForceActivation)
        );
        /// Validator call is done as usual.
        vm.mockCall(
            address(mockValidator),
            abi.encodeWithSelector(ISecurityValidator.executeCheckpoint.selector, checkpointHash),
            abi.encode(keccak256(abi.encode(checkpointHash, address(firewall), bytes32(0))))
        );
        firewall.secureExecution(arg);
    }

    function testFirewall_hookForceDeactivation() public {
        vm.mockCall(
            address(mockAccess),
            abi.encodeWithSelector(IFirewallAccess.isCheckpointManager.selector, address(this)),
            abi.encode(true)
        );
        Checkpoint memory chk = Checkpoint({
            threshold: 2,
            refStart: 4,
            refEnd: 36,
            activation: Activation.ConstantThreshold,
            trustedOrigin: false
        });
        firewall.setCheckpoint(FirewallImpl.secureExecution.selector, chk);
        uint256 arg = 3;
        vm.mockCall(
            address(mockValidator),
            abi.encodeWithSelector(ISecurityValidator.getCurrentAttester.selector),
            abi.encode(testAttester)
        );
        vm.mockCall(
            address(mockAccess),
            abi.encodeWithSelector(IFirewallAccess.isTrustedAttester.selector, address(testAttester)),
            abi.encode(true)
        );
        vm.mockCall(
            address(mockHook),
            abi.encodeWithSelector(
                ICheckpointHook.handleCheckpoint.selector, address(this), FirewallImpl.secureExecution.selector, arg
            ),
            abi.encode(HookResult.ForceDeactivation)
        );
        /// No validator call!
        firewall.secureExecution(arg);
    }
}
