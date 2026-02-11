// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

import {
    IPaymaster, ExecutionResult, PAYMASTER_VALIDATION_SUCCESS_MAGIC, Transaction
} from "./interfaces/IPaymaster.sol";
import {IPaymasterFlow} from "./interfaces/IPaymasterFlow.sol";
import {ISignatureBasedPaymaster} from "./interfaces/ISignatureBasedPaymaster.sol";

import {BOOTLOADER_FORMAL_ADDRESS} from "./Constants.sol";

/// @title Signature based paymaster
/// @author Matter Labs
/// @custom:security-contact security@matterlabs.dev
/// @dev This paymaster contract pays transaction fees for transactions initiated by approved addresses.
/// The contract aims to serve as a centralized paymaster for hot wallets, addressing an issue where each wallet needs to maintain
/// a balance and be regularly funded. With this solution, there's a single funding source, simplifying the management of multiple
/// hot wallets.
///
/// The contract has two roles: **owner** and **signer**.
/// - The owner can change the signer.
/// - The signer is responsible for managing the list of addresses approved to utilize this paymaster for their transaction fees.
contract SignatureBasedPaymaster is IPaymaster, ISignatureBasedPaymaster, Ownable, EIP712 {
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;

    /// @notice EIP-712 TypeHash for an approval for the transaction senders.
    /// @dev Used for signature validation, ensuring the signer approves the transaction sender, validity period, and nonce.
    bytes32 public constant APPROVED_TRANSACTION_SENDER_TYPEHASH =
        keccak256("ApprovedTransactionSender(address sender,uint256 validUntil,uint256 nonce)");

    /// @notice The signer authorized to approve sender accounts for which this paymaster pay for.
    /// @dev Transactions with a valid signature from this address are considered approved for fee coverage.
    address public signer;

    /// @notice Stores the validity period for approved senders.
    /// @dev Maps each sender to the timestamp until which their transactions are approved for fee coverage.
    mapping(address sender => uint256 validUntil) public approvedSenders;

    /// @notice Tracks nonces for each sender to prevent replay attacks.
    /// @dev Each sender has a unique nonce that must match and increment with changing the
    /// timestamp until which their transactions are approved for fee coverage.
    mapping(address sender => uint256 nonce) public nonces;

    /// @dev Ensures that only the bootloader can call certain functions.
    modifier onlyBootloader() {
        require(msg.sender == BOOTLOADER_FORMAL_ADDRESS, "Only bootloader can call this method");
        // Continue execution if called from the bootloader.
        _;
    }

    /// @notice Checks that the message sender is an active owner or an active signer.
    modifier onlyOwnerOrSigner() {
        require(msg.sender == signer || msg.sender == owner(), "Only signer or owner can call this method");
        _;
    }

    /// @param _signer The initial signer address that is authorized to approve transactions for this paymaster.
    constructor(address _signer) EIP712("SignatureBasedPaymaster", "1") {
        require(_signer != address(0), "Signer cannot be address(0)");
        signer = _signer;
        emit SignerChanged(address(0), _signer);
    }

    /// @inheritdoc IPaymaster
    function validateAndPayForPaymasterTransaction(bytes32, bytes32, Transaction calldata _transaction)
        external
        payable
        onlyBootloader
        returns (bytes4, bytes memory)
    {
        bytes4 paymasterInputSelector = bytes4(_transaction.paymasterInput[0:4]);
        require(paymasterInputSelector == IPaymasterFlow.general.selector, "Paymaster: Unsupported paymaster flow");

        // `general` paymaster flow accepts the raw `bytes`, so decode it first.
        (bytes memory innerInputs) = abi.decode(_transaction.paymasterInput[4:], (bytes));
        // Get the sender address.
        address sender = address(uint160(_transaction.from));

        // Decode the real paymaster input parameters from the raw bytes.
        try this.decodePaymasterInput(innerInputs) returns (uint256 validUntil, bytes memory signature) {
            // Verify that the timestamp for which transactions from the sender should be
            // paid by the paymaster is not expired.
            require(block.timestamp <= validUntil, "Paymaster: Signature expired");
            approveSenderBySignature(sender, validUntil, signature);
        } catch {
            // If the decoding failed just check that sender was pre-approved.
            require(
                block.timestamp <= approvedSenders[sender],
                "Paymaster: Sender has no permission for sending transaction with this paymaster"
            );
        }

        // Note, that while the minimal amount of ETH needed is tx.gasPrice * tx.gasLimit,
        // neither paymaster nor account are allowed to access this context variable.
        uint256 requiredETH = _transaction.gasLimit * _transaction.maxFeePerGas;

        // The bootloader never returns any data, so it can safely be ignored here.
        (bool success,) = payable(BOOTLOADER_FORMAL_ADDRESS).call{value: requiredETH}("");
        require(success, "Paymaster: Failed to transfer tx fee to the bootloader");

        return (PAYMASTER_VALIDATION_SUCCESS_MAGIC, new bytes(0));
    }

    /// @notice Decodes the paymaster input data into its constituent components.
    /// @param _data The raw bytes input to the paymaster.
    /// @return validUntil The timestamp until which the transaction from the sender is considered valid.
    /// @return signature The ECDSA signature from the paymaster signer that approves the account for fee coverage.
    function decodePaymasterInput(bytes memory _data)
        external
        pure
        returns (uint256 validUntil, bytes memory signature)
    {
        (validUntil, signature) = abi.decode(_data, (uint256, bytes));
    }

    /// @inheritdoc IPaymaster
    function postTransaction(bytes calldata, Transaction calldata, bytes32, bytes32, ExecutionResult, uint256)
        external
        payable
        override
        onlyBootloader
    {
        // Do nothing as the transaction initiator address shouldn't get any refund.
    }

    /// @notice Approves a sender address to use the paymaster for paying fees until a specified timestamp by signature.
    /// @param _sender The address of the sender to be approved.
    /// @param _validUntil The timestamp until which the sender can use paymaster.
    /// @param _signature The signature proving the approval.
    function approveSenderBySignature(address _sender, uint256 _validUntil, bytes memory _signature) public {
        // Generate the EIP-712 digest.
        bytes32 structHash =
            keccak256(abi.encode(APPROVED_TRANSACTION_SENDER_TYPEHASH, _sender, _validUntil, nonces[_sender]++));
        bytes32 digest = _hashTypedDataV4(structHash);
        // Revert if signer doesn't match recovered address. Reverts on address(0) as well.
        require(signer == digest.recover(_signature), "Paymaster: Invalid signer");
        approvedSenders[_sender] = _validUntil;
        emit SenderApproved(_sender, _validUntil);
    }

    /// @notice Withdraw funds from the contract to the specified address.
    /// @param _to The address where to send funds.
    /// @param _token Address of the token to be withdrawn.
    function withdraw(address _to, address _token) public onlyOwner {
        uint256 amount;
        if (_token == address(0)) {
            amount = address(this).balance;
            (bool success,) = _to.call{value: amount}("");
            require(success, "Failed to withdraw ether");
        } else {
            amount = IERC20(_token).balanceOf(address(this));
            // We use safeTransfer to escape any tokens even if they implemented ERC-20 standard wrongly (e.g. don't return bool value)
            IERC20(_token).safeTransfer(_to, amount);
        }
        emit Withdrawn(_token, amount);
    }

    /// @notice Change the active signer address.
    /// @param _signer The new signer address.
    function changeSigner(address _signer) external onlyOwnerOrSigner {
        emit SignerChanged(signer, _signer);
        signer = _signer;
    }

    /// @notice Increments the nonce for a given sender address, effectively canceling the current nonce.
    /// @param _sender The address of the sender whose nonce is to be incremented.
    function cancelNonce(address _sender) external onlyOwnerOrSigner {
        uint256 nonce = nonces[_sender];
        nonces[_sender]++;
        emit NonceCanceled(_sender, nonce);
    }

    /// @notice Approves a sender address to use the paymaster for paying transaction fees until a specified timestamp.
    /// @param _sender The address of the sender to be approved.
    /// @param _validUntil The timestamp until which the sender can use paymaster.
    function approveSender(address _sender, uint256 _validUntil) external onlyOwnerOrSigner {
        approvedSenders[_sender] = _validUntil;
        emit SenderApproved(_sender, _validUntil);
    }

    /// @notice Returns the EIP-712 domain separator for this contract.
    function domainSeparator() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    /// @dev Contract should receive/hold ETH to pay fees as a paymaster.
    receive() external payable {}
}
