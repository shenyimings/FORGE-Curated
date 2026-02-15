// SPDX-License-Identifier: MIT
pragma solidity >=0.8.23 <0.9.0;

interface IBeaconBase {
  event InstanceAdded(address indexed instance);
  event BeaconExecuted(address indexed caller, bytes data, bool success, bytes ret);

  error IBeaconBase__IndexOutOfBounds(uint256 max, uint256 given);
  error IBeaconBase__BeaconCallFailed(bytes revertData);

  function beacon() external view returns (address);
  function isInstance(address instance) external view returns (bool);
  function instances(uint256 index) external view returns (address);
  function instances(uint256[] memory indexes) external view returns (address[] memory);
  function instancesLength() external view returns (uint256);
}
