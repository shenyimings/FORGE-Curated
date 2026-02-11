// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/governance/TimelockController.sol";

contract Timelock is TimelockController {
  event MaxDelayChanged(uint256 oldValue, uint256 newValue);

  uint256 public MAX_DELAY;
  uint256 public salt;

  constructor(
    uint256 minDelay,
    uint256 maxDelay,
    address[] memory proposers,
    address[] memory executors
  ) TimelockController(minDelay, proposers, executors, address(0)) {
    require(maxDelay > minDelay + 3600, "illegal maxDelay");
    MAX_DELAY = maxDelay;
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

  function scheduleTask(
    address target,
    string calldata functionSignature,
    bytes calldata data
  ) external onlyRole(PROPOSER_ROLE) {
    bytes memory finalData = abi.encodePacked(bytes4(keccak256(bytes(functionSignature))), data);
    salt++;
    this.schedule(target, 0, finalData, bytes32(0), bytes32(salt), getMinDelay());
  }

  function executeTask(
    address target,
    string calldata functionSignature,
    bytes calldata data,
    uint256 _salt
  ) external onlyRoleOrOpenRole(EXECUTOR_ROLE) {
    bytes memory finalData = abi.encodePacked(bytes4(keccak256(bytes(functionSignature))), data);
    this.execute(target, 0, finalData, bytes32(0), bytes32(_salt));
  }
}
