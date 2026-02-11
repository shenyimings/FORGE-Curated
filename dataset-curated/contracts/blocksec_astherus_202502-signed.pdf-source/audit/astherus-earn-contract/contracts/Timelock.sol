// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import '@openzeppelin/contracts/governance/TimelockController.sol';
import '@openzeppelin/contracts/access/extensions/AccessControlEnumerable.sol';

contract Timelock is TimelockController, AccessControlEnumerable {

    event MaxDelayChanged(uint256 oldValue, uint256 newValue);

    uint256 public MAX_DELAY;
    uint256 public salt;

    constructor(uint256 minDelay, uint256 maxDelay, address[] memory proposers, address[] memory executors)
    TimelockController(minDelay, proposers, executors, address(0))
    {
        require(maxDelay > minDelay + 3600, "illegal maxDelay");
        MAX_DELAY = maxDelay;
        _grantRole(PROPOSER_ROLE, address(this));
        _grantRole(EXECUTOR_ROLE, address(this));
    }

    function setMaxDelay(uint256 maxDelay) external {
        require(maxDelay > getMinDelay() + 3600, "illegal maxDelay");
        if (msg.sender != address(this)) {
            revert TimelockUnauthorizedCaller(msg.sender);
        }
        emit MaxDelayChanged(MAX_DELAY, maxDelay);
        MAX_DELAY = maxDelay;
    }

    function getTimestamp(bytes32 id) public view override returns (uint256) {
        uint timestamp = super.getTimestamp(id);
        if (block.timestamp > timestamp + MAX_DELAY) {
            return 0;
        } else {
            return timestamp;
        }
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(TimelockController, AccessControlEnumerable) returns (bool) {
        return TimelockController.supportsInterface(interfaceId) || AccessControlEnumerable.supportsInterface(interfaceId);
    }

    function _revokeRole(bytes32 role, address account) internal virtual override(AccessControl, AccessControlEnumerable) returns (bool) {
        return AccessControlEnumerable._revokeRole(role, account);
    }

    function _grantRole(bytes32 role, address account) internal virtual override(AccessControl, AccessControlEnumerable) returns (bool) {
        return AccessControlEnumerable._grantRole(role, account);
    }

    function scheduleTask(address target, string calldata functionSignature, bytes calldata data) external onlyRole(PROPOSER_ROLE) {
        bytes memory finalData = abi.encodePacked(bytes4(keccak256(bytes(functionSignature))), data);
        salt ++;
        this.schedule(
            target,
            0,
            finalData,
            bytes32(0),
            bytes32(salt),
            getMinDelay()
        );
    }

    function executeTask(address target, string calldata functionSignature, bytes calldata data) external onlyRoleOrOpenRole(EXECUTOR_ROLE) {
        bytes memory finalData = abi.encodePacked(bytes4(keccak256(bytes(functionSignature))), data);
        this.execute(
            target,
            0,
            finalData,
            bytes32(0),
            bytes32(salt)
        );
    }
}

