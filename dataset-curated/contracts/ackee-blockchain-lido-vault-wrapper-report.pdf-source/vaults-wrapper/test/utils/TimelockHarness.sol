// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.30;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {Test} from "forge-std/Test.sol";

contract TimelockHarness is Test {
    TimelockController public timelock;

    address timelockProposer;
    address timelockExecutor;

    bytes32 salt = keccak256("timelock.salt.for.test");

    function _setupTimelock(address _timelock, address _proposer, address _executor) internal {
        timelock = TimelockController(payable(_timelock));
        timelockProposer = _proposer;
        timelockExecutor = _executor;
    }

    function _timelockSchedule(address target, bytes memory payload) internal {
        uint256 delay = timelock.getMinDelay();

        vm.prank(timelockProposer);
        timelock.schedule({target: target, value: 0, data: payload, predecessor: bytes32(0), salt: salt, delay: delay});
    }

    function _timelockScheduleBatch(address[] memory targets, bytes[] memory payloads) internal {
        uint256 delay = timelock.getMinDelay();

        vm.prank(timelockProposer);
        timelock.scheduleBatch({
            targets: targets,
            values: new uint256[](targets.length),
            payloads: payloads,
            predecessor: bytes32(0),
            salt: salt,
            delay: delay
        });
    }

    function _timelockWarp() internal {
        vm.warp(block.timestamp + timelock.getMinDelay());
    }

    function _timelockExecute(address target, bytes memory payload) internal {
        vm.prank(timelockExecutor);
        timelock.execute({target: target, value: 0, payload: payload, predecessor: bytes32(0), salt: salt});
    }

    function _timelockExecuteBatch(address[] memory targets, bytes[] memory payloads) internal {
        vm.prank(timelockExecutor);
        timelock.executeBatch({
            targets: targets,
            values: new uint256[](targets.length),
            payloads: payloads,
            predecessor: bytes32(0),
            salt: salt
        });
    }

    function _timelockScheduleAndExecute(address target, bytes memory payload) internal {
        _timelockSchedule(target, payload);
        _timelockWarp();
        _timelockExecute(target, payload);
    }

    function _timelockScheduleAndExecuteBatch(address[] memory targets, bytes[] memory payloads) internal {
        _timelockScheduleBatch(targets, payloads);
        _timelockWarp();
        _timelockExecuteBatch(targets, payloads);
    }
}
