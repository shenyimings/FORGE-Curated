// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Transaction, TransactionHelper } from "@matterlabs/zksync-contracts/l2/system-contracts/libraries/TransactionHelper.sol";
import { IExecutionHook } from "../interfaces/IHook.sol";
import { IModule } from "../interfaces/IModule.sol";
import { IERC165 } from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

contract TestExecutionHook is IExecutionHook {
  using TransactionHelper for Transaction;

  event ExecutionHookInstalled(address indexed account);
  event ExecutionHookUninstalled(address indexed account);

  event PreExecution(address indexed account, address indexed target);
  event PostExecution(address indexed account, address indexed target);

  mapping(address => address) public lastTarget;

  function onInstall(bytes calldata data) external {
    bool shouldRevert = abi.decode(data, (bool));
    if (shouldRevert) {
      revert("Install hook failed");
    }
    emit ExecutionHookInstalled(msg.sender);
  }

  function onUninstall(bytes calldata data) external {
    bool shouldRevert = abi.decode(data, (bool));
    if (shouldRevert) {
      revert("Uninstall hook failed");
    }
    emit ExecutionHookUninstalled(msg.sender);
  }

  function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
    return
      interfaceId == type(IExecutionHook).interfaceId ||
      interfaceId == type(IModule).interfaceId ||
      interfaceId == type(IERC165).interfaceId;
  }

  function preExecutionHook(Transaction calldata transaction) external returns (bytes memory context) {
    // arbitrary revert condition
    if (transaction.to == 0) {
      revert("PreExecution hook failed");
    }

    // store some data in transient storage
    uint256 slot = uint256(uint160(msg.sender));
    uint256 storedTarget = transaction.to;
    assembly {
      tstore(slot, storedTarget)
    }

    // store some data in regular storage
    lastTarget[msg.sender] = address(uint160(transaction.to));

    // emit event
    emit PreExecution(msg.sender, address(uint160(transaction.to)));

    // pass some data via context
    return abi.encode(transaction);
  }

  function postExecutionHook(bytes calldata context) external {
    // decode context data
    Transaction memory transaction = abi.decode(context, (Transaction));

    // arbitrary revert condition
    if (transaction.to == uint256(uint160(msg.sender))) {
      revert("PostExecution hook failed");
    }

    // load data from transient storage
    uint256 storedTarget;
    uint256 slot = uint256(uint160(msg.sender));
    assembly {
      storedTarget := tload(slot)
    }

    require(storedTarget != 0, "No data in transient storage");
    require(transaction.to == storedTarget, "Targets do not match (tload)");
    require(transaction.to == uint256(uint160(lastTarget[msg.sender])), "Targets do not match (sload)");

    // emit event
    emit PostExecution(msg.sender, address(uint160(transaction.to)));
  }
}
