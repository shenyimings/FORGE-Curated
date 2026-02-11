// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IMultiPathConverter {
  function queryConvert(
    uint256 _amount,
    uint256 _encoding,
    uint256[] calldata _routes
  ) external returns (uint256 amountOut);

  function convert(
    address _tokenIn,
    uint256 _amount,
    uint256 _encoding,
    uint256[] calldata _routes
  ) external payable returns (uint256 amountOut);
}
