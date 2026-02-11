// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IMintable} from "src/interfaces/IMintable.sol";

interface IMintableAndDelegatable is IMintable {
  function DOMAIN_SEPARATOR() external view returns (bytes32);
  function delegateOnBehalf(address _signer, address _delegatee, uint256 _expiry, bytes memory _signature) external;
  function delegates(address _account) external view returns (address);
}
