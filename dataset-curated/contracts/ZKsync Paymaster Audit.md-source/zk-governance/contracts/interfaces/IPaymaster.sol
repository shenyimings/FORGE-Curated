// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

enum ExecutionResult {
    Revert,
    Success
}

bytes4 constant PAYMASTER_VALIDATION_SUCCESS_MAGIC = IPaymaster.validateAndPayForPaymasterTransaction.selector;

/// @notice Structure used to represent a zkSync transaction.
struct Transaction {
    // The type of the transaction.
    uint256 txType;
    // The caller.
    uint256 from;
    // The callee.
    uint256 to;
    // The gasLimit to pass with the transaction.
    // It has the same meaning as Ethereum's gasLimit.
    uint256 gasLimit;
    // The maximum amount of gas the user is willing to pay for a byte of pubdata.
    uint256 gasPerPubdataByteLimit;
    // The maximum fee per gas that the user is willing to pay.
    // It is akin to EIP1559's maxFeePerGas.
    uint256 maxFeePerGas;
    // The maximum priority fee per gas that the user is willing to pay.
    // It is akin to EIP1559's maxPriorityFeePerGas.
    uint256 maxPriorityFeePerGas;
    // The transaction's paymaster. If there is no paymaster, it is equal to 0.
    uint256 paymaster;
    // The nonce of the transaction.
    uint256 nonce;
    // The value to pass with the transaction.
    uint256 value;
    // In the future, we might want to add some
    // new fields to the struct. The `txData` struct
    // is to be passed to account and any changes to its structure
    // would mean a breaking change to these accounts. In order to prevent this,
    // we should keep some fields as "reserved".
    // It is also recommended that their length is fixed, since
    // it would allow easier proof integration (in case we will need
    // some special circuit for preprocessing transactions).
    uint256[4] reserved;
    // The transaction's calldata.
    bytes data;
    // The signature of the transaction.
    bytes signature;
    // The properly formatted hashes of bytecodes that must be published on L1
    // with the inclusion of this transaction. Note, that a bytecode has been published
    // before, the user won't pay fees for its republishing.
    bytes32[] factoryDeps;
    // The input to the paymaster.
    bytes paymasterInput;
    // Reserved dynamic type for the future use-case. Using it should be avoided,
    // But it is still here, just in case we want to enable some additional functionality.
    bytes reservedDynamic;
}

interface IPaymaster {
    /// @dev Called by the bootloader to verify that the paymaster agrees to pay for the
    /// fee for the transaction. This transaction should also send the necessary amount of funds onto the bootloader
    /// address.
    /// @param _txHash The hash of the transaction
    /// @param _suggestedSignedHash The hash of the transaction that is signed by an EOA
    /// @param _transaction The transaction itself.
    /// @return magic The value that should be equal to the signature of the validateAndPayForPaymasterTransaction
    /// if the paymaster agrees to pay for the transaction.
    /// @return context The "context" of the transaction: an array of bytes of length at most 1024 bytes, which will be
    /// passed to the `postTransaction` method of the account.
    /// @dev The developer should strive to preserve as many steps as possible both for valid
    /// and invalid transactions as this very method is also used during the gas fee estimation
    /// (without some of the necessary data, e.g. signature).
    function validateAndPayForPaymasterTransaction(
        bytes32 _txHash,
        bytes32 _suggestedSignedHash,
        Transaction calldata _transaction
    ) external payable returns (bytes4 magic, bytes memory context);

    /// @dev Called by the bootloader after the execution of the transaction. Please note that
    /// there is no guarantee that this method will be called at all. Unlike the original EIP4337,
    /// this method won't be called if the transaction execution results in out-of-gas.
    /// @param _context, the context of the execution, returned by the "validateAndPayForPaymasterTransaction" method.
    /// @param _transaction, the users' transaction.
    /// @param _txResult, the result of the transaction execution (success or failure).
    /// @param _maxRefundedGas, the upper bound on the amout of gas that could be refunded to the paymaster.
    /// @dev The exact amount refunded depends on the gas spent by the "postOp" itself and so the developers should
    /// take that into account.
    function postTransaction(
        bytes calldata _context,
        Transaction calldata _transaction,
        bytes32 _txHash,
        bytes32 _suggestedSignedHash,
        ExecutionResult _txResult,
        uint256 _maxRefundedGas
    ) external payable;
}
