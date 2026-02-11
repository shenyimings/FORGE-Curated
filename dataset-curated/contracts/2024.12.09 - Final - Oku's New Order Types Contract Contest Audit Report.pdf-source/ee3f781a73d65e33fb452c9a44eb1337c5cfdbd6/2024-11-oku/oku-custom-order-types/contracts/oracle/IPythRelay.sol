// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;
import "./IOracleRelay.sol";

/// @title OracleRelay Interface
interface IPythRelay is IOracleRelay {
  function updatePrice(bytes[] calldata priceUpdate) external payable returns (uint256 updatedPrice);
  function getUpdateFee(bytes[] calldata priceUpdate) external view returns (uint fee);
}
