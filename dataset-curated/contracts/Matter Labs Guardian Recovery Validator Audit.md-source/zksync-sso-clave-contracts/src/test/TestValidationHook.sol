// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Transaction, TransactionHelper } from "@matterlabs/zksync-contracts/l2/system-contracts/libraries/TransactionHelper.sol";
import { IValidationHook } from "../interfaces/IHook.sol";
import { IModule } from "../interfaces/IModule.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

contract TestValidationHook is IValidationHook {
  using TransactionHelper for Transaction;

  event ValidationHookInstalled(address indexed account);
  event ValidationHookUninstalled(address indexed account);
  event ValidationHookTriggered(address indexed account, address indexed target);

  mapping(address => address) public lastTarget;

  function onInstall(bytes calldata data) external {
    bool shouldRevert = abi.decode(data, (bool));
    if (shouldRevert) {
      revert("Install hook failed");
    }
    emit ValidationHookInstalled(msg.sender);
  }

  function onUninstall(bytes calldata data) external {
    bool shouldRevert = abi.decode(data, (bool));
    if (shouldRevert) {
      revert("Uninstall hook failed");
    }
    emit ValidationHookUninstalled(msg.sender);
  }

  function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
    return
      interfaceId == type(IValidationHook).interfaceId ||
      interfaceId == type(IModule).interfaceId ||
      interfaceId == type(IERC165).interfaceId;
  }

  // FIXME: if a validation hook were to always revert, the account would be bricked
  function validationHook(bytes32 signedHash, Transaction calldata transaction) external {
    if (transaction.data.length == 0) {
      revert("Empty calldata not allowed");
    }

    address target = address(uint160(transaction.to));

    // emit event
    emit ValidationHookTriggered(msg.sender, target);

    // store some data in storage
    lastTarget[msg.sender] = target;
  }
}
