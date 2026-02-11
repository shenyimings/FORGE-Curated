// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/Address.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// File contracts/interfaces/IAggregationExecutor.sol

/// @title Interface for making arbitrary calls during swap
interface IAggregationExecutor {
  /// @notice propagates information about original msg.sender and executes arbitrary data
  function execute(address msgSender) external payable returns (uint256);  // 0x4b64e492
}

contract MockAggregationRouterV6 {
  using SafeERC20 for IERC20;
  using Address for address payable;
  //swap native address
  address public nativeAddress;

  struct SwapDescription {
    IERC20 srcToken;
    IERC20 dstToken;
    address payable srcReceiver;
    address payable dstReceiver;
    uint256 amount;
    uint256 minReturnAmount;
    uint256 flags;
  }

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor(address _nativeAddress) {
    nativeAddress = _nativeAddress;
  }

  /**
    * @notice Performs a swap, delegating all calls encoded in `data` to `executor`. See tests for usage examples.
    * @dev Router keeps 1 wei of every token on the contract balance for gas optimisations reasons.
    *      This affects first swap of every token by leaving 1 wei on the contract.
    * @param executor Aggregation executor that executes calls described in `data`.
    * @param desc Swap description.
    * @param data Encoded calls that `caller` should execute in between of swaps.
    * @return returnAmount Resulting token amount.
    * @return spentAmount Source token amount.
    */
  function swap(
    IAggregationExecutor executor,
    SwapDescription calldata desc,
    bytes calldata data
  )
  external
  payable
  returns (
    uint256 returnAmount,
    uint256 spentAmount
  )
  {
    IERC20 srcToken = desc.srcToken;
    IERC20 dstToken = desc.dstToken;

    if (!isETH(srcToken)) {
      srcToken.transferFrom(
        msg.sender,
        address(this),
        desc.amount
      );
    }

    if (isETH(dstToken)) {
      desc.dstReceiver.sendValue(desc.minReturnAmount);
    } else {
      dstToken.safeTransfer(desc.dstReceiver, desc.minReturnAmount);
    }

    return (desc.minReturnAmount, desc.amount);
  }

  /// @dev Returns true if `token` is ETH.
  function isETH(IERC20 token) internal view returns (bool) {
    return address(token) == nativeAddress;
  }
}
