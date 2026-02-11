// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
import { SendParam } from "@layerzerolabs/oft-evm/contracts/interfaces/IOFT.sol";

/// @title Minter interface
interface IAsBnbMinter {
  struct TokenMintReq {
    address user; // user who made the request
    uint256 amountIn; // amount of token deposited
  }

  // mint with slisBNB
  function mintAsBnb(uint256 amountIn) external returns (uint256);
  // mint with BNB
  function mintAsBnb() external payable returns (uint256);
  // mint with slisBNB and send asBNB cross-chain
  function mintAsBnbToChain(uint256 amountIn, SendParam memory sendParam) external payable returns (uint256);
  // mint with BNB and send asBNB cross-chain
  function mintAsBnbToChain(SendParam memory sendParam) external payable returns (uint256);
  // compound rewards
  function compoundRewards(uint256 _amountIn) external;
  // internal use only, migrate v1's slisBNB as asBNB
  function mintAsBnbFor(uint256 amountIn, address forAddr) external returns (uint256);
  // internal use only, migrate v1's BNB as asBNB
  function mintAsBnbFor(address forAddr) external payable returns (uint256);
  // burn asBNB and get back slisBNB
  function burnAsBnb(uint256 amountToBurn) external returns (uint256);
  // read-only func.
  function convertToTokens(uint256 asBNBAmount) external view returns (uint256);
  function convertToAsBnb(uint256 tokenAmount) external view returns (uint256);
}
