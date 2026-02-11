// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IPaymaster, ExecutionResult, PAYMASTER_VALIDATION_SUCCESS_MAGIC } from "@matterlabs/zksync-contracts/l2/system-contracts/interfaces/IPaymaster.sol";
import { IPaymasterFlow } from "@matterlabs/zksync-contracts/l2/system-contracts/interfaces/IPaymasterFlow.sol";
import { TransactionHelper, Transaction } from "@matterlabs/zksync-contracts/l2/system-contracts/libraries/TransactionHelper.sol";
import "@matterlabs/zksync-contracts/l2/system-contracts/Constants.sol";

contract TestPaymaster is IPaymaster {
  modifier onlyBootloader() {
    require(msg.sender == BOOTLOADER_FORMAL_ADDRESS, "Only bootloader can call this method");
    // Continue execution if called from the bootloader.
    _;
  }

  function validateAndPayForPaymasterTransaction(
    bytes32,
    bytes32,
    Transaction calldata transaction
  ) external payable onlyBootloader returns (bytes4 magic, bytes memory) {
    magic = PAYMASTER_VALIDATION_SUCCESS_MAGIC;

    bytes4 paymasterInputSelector = bytes4(transaction.paymasterInput[:4]);
    if (paymasterInputSelector == IPaymasterFlow.approvalBased.selector) {
      (address token, uint256 amount, bytes memory data) = abi.decode(
        transaction.paymasterInput[4:],
        (address, uint256, bytes)
      );

      uint256 providedAllowance = IERC20(token).allowance(address(uint160(transaction.from)), address(this));

      // For testing purposes any non-zero allowance of any token is enough
      require(providedAllowance > 0, "Min allowance too low");
      IERC20(token).transferFrom(address(uint160(transaction.from)), address(this), amount);
    } else if (paymasterInputSelector == IPaymasterFlow.general.selector) {
      // For testing purposes any transaction is valid
    } else {
      revert("Unsupported paymaster flow");
    }

    uint256 requiredETH = transaction.gasLimit * transaction.maxFeePerGas;
    (bool success, ) = payable(BOOTLOADER_FORMAL_ADDRESS).call{ value: requiredETH }("");
    require(success, "Paymaster out of funds");
  }

  function postTransaction(
    bytes calldata _context,
    Transaction calldata transaction,
    bytes32,
    bytes32,
    ExecutionResult _txResult,
    uint256 _maxRefundedGas
  ) external payable override onlyBootloader {}

  receive() external payable {}
}
