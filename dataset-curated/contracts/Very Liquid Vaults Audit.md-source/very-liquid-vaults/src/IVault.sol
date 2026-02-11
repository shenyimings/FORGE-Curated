// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {Auth} from "@src/Auth.sol";

/// @title IVault
/// @custom:security-contact security@size.credit
/// @author Size (https://size.credit/)
/// @notice Interface for the base vault contract
interface IVault is IERC4626 {
  /// @notice Returns the address of the auth contract
  function auth() external view returns (Auth);

  /// @notice Returns the total assets cap of the vault
  function totalAssetsCap() external view returns (uint256);
}
