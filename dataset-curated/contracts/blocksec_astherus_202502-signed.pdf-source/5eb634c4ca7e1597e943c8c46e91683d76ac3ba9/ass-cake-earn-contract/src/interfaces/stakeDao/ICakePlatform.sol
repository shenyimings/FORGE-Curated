// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title PancakeSwap Platform by StakeDAO
/// @notice VoteMarket for PancakeSwap gauges. Takes into account the 2 weeks voting Epoch, so claimable period active on EVEN week Thursday.
/// please refer to https://bscscan.com/address/0x62c5D779f5e56F6BC7578066546527fEE590032c#code
interface ICakePlatform {
  function setRecipient(address _recipient) external;
  function claimAllFor(address _user, uint256[] calldata ids) external;
}
