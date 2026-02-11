// SPDX-License-Identifier: MIT

pragma solidity ^0.8.26;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";

abstract contract StrategyBase is AccessControl {
  bytes32 public constant HARVESTER_ROLE = keccak256("HARVESTER_ROLE");

  address public immutable operator;

  /**
   * @dev This empty reserved space is put in place to allow future versions to add new
   * variables without shifting down storage in the inheritance chain.
   */
  uint256[50] private __gap;

  modifier onlyOperator() {
    if (msg.sender != operator) revert();
    _;
  }

  constructor(address _admin, address _operator) {
    operator = _operator;

    _grantRole(DEFAULT_ADMIN_ROLE, _admin);
  }

  function harvest(address receiver) external onlyRole(HARVESTER_ROLE) {
    _harvest(receiver);
  }

  function execute(
    address to,
    uint256 value,
    bytes calldata data
  ) external onlyOperator returns (bool success, bytes memory returnData) {
    (success, returnData) = to.call{ value: value }(data);
  }

  function _harvest(address receiver) internal virtual;
}
