// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

abstract contract PropertiesSpecifications {
  string constant SOLVENCY_01 = "SOLVENCY_01: SUM(convertToAssets(balanceOf)) <= totalAssets()"; // implemented
  string constant SOLVENCY_02 = "SOLVENCY_02: Direct deposit to strategy should not change convertToAssets(balanceOf) of the meta vault";
  string constant REBALANCE_01 = "REBALANCE_01: rebalance does not change balanceOf"; // implemented
  string constant REBALANCE_02 = "REBALANCE_02: rebalance does not change convertToAssets(balanceOf)"; // implemented
  string constant STRATEGY_01 = "STRATEGY_01: Removing a strategy does not change balanceOf"; // implemented
  string constant STRATEGY_02 = "STRATEGY_02: The SizeMetaVault always has at least 1 strategy"; // implemented
  string constant TOTAL_ASSETS_CAP_01 = "TOTAL_ASSETS_CAP_01: Deposit/Mint cannot lead to totalAssets() > totalAssetsCap()"; // implemented
  string constant ERC4626_MUST_NOT_REVERT = "ERC4626_MUST_NOT_REVERT: MUST NOT revert: "; // implemented
}
