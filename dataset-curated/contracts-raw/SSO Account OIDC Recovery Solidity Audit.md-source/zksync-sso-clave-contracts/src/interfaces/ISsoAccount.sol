// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import { IAccount } from "@matterlabs/zksync-contracts/l2/system-contracts/interfaces/IAccount.sol";

import { IERC1271Upgradeable } from "@openzeppelin/contracts-upgradeable/interfaces/IERC1271Upgradeable.sol";
import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import { IERC1155Receiver } from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";

import { IHookManager } from "./IHookManager.sol";
import { IOwnerManager } from "./IOwnerManager.sol";
import { IValidatorManager } from "./IValidatorManager.sol";

/**
 * @title ISsoAccount
 * @notice Interface for the SSO contract
 * @dev Implementations of this interface are contracts that can be used as an SSO account (it's no longer Clave compatible)
 */
interface ISsoAccount is
  IERC1271Upgradeable,
  IERC721Receiver,
  IERC1155Receiver,
  IHookManager,
  IOwnerManager,
  IValidatorManager,
  IAccount
{
  function initialize(bytes[] calldata initialValidators, address[] calldata initialK1Owners) external;
}
