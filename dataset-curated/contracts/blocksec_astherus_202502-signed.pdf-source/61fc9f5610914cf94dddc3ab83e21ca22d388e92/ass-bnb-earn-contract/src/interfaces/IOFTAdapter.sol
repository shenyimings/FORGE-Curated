// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import { IOFT } from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";

/// @title OFTAdapter interface
/// @notice for exposing decimalConversionRate
interface IOFTAdapter is IOFT {
  function decimalConversionRate() external view returns (uint256);
}
