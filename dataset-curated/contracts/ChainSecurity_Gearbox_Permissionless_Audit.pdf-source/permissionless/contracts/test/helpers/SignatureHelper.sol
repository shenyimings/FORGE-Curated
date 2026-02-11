// SPDX-License-Identifier: BUSL-1.1
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2024.
pragma solidity ^0.8.23;

import {Test, Vm} from "forge-std/Test.sol";
import {VmSafe} from "forge-std/Vm.sol";
import {console2} from "forge-std/console2.sol";

contract SignatureHelper is Test {
    address private prevCaller;

    error PrevCallerIsAlreadySet();

    function _generatePrivateKey(string memory salt) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(salt)));
    }

    function _sign(uint256 privateKey, bytes32 bytecodeHash) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, bytecodeHash);
        return abi.encodePacked(r, s, v);
    }

    function _startPrankOrBroadcast(address addr) internal {
        if (prevCaller != address(0)) {
            revert PrevCallerIsAlreadySet();
        }

        (VmSafe.CallerMode callerMode, address msgSender,) = vm.readCallers();
        if (callerMode == VmSafe.CallerMode.Broadcast || callerMode == VmSafe.CallerMode.RecurrentBroadcast) {
            vm.stopBroadcast();
            vm.startBroadcast(addr);
            prevCaller = msgSender;
        } else {
            vm.startPrank(addr);
        }
    }

    function _stopPrankOrBroadcast() internal {
        (Vm.CallerMode callerMode,,) = vm.readCallers();
        if (callerMode == VmSafe.CallerMode.Broadcast || callerMode == VmSafe.CallerMode.RecurrentBroadcast) {
            vm.stopBroadcast();
            if (prevCaller != address(0)) {
                vm.startBroadcast(prevCaller);
            }
        } else {
            vm.stopPrank();
            if (prevCaller != address(0)) {
                vm.startPrank(prevCaller);
            }
        }

        prevCaller = address(0);
    }
}
