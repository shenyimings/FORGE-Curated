// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

import {
    IPaymaster, ExecutionResult, PAYMASTER_VALIDATION_SUCCESS_MAGIC, Transaction
} from "./interfaces/IPaymaster.sol";
import {IPaymasterFlow} from "./interfaces/IPaymasterFlow.sol";
import {IAADistributorPaymaster} from "./interfaces/IAADistributorPaymaster.sol";
import {IZkMerkleDistributor} from "./interfaces/IZkMerkleDistributor.sol";

import {BOOTLOADER_FORMAL_ADDRESS} from "./Constants.sol";

/// @title Account Abstraction Distributor paymaster
/// @author Matter Labs
/// @custom:security-contact security@matterlabs.dev
/// @notice This paymaster contract is designed to pay fees for claiming ZK tokens by Account Abstraction wallets.
/// @dev In the general case, a smart wallet can arbitrarily handle the transaction input. That means, the paymaster
/// can't trust the received transaction structure. To provide a good UX for all eligible smart wallets, this paymaster
/// sponsors transactions initiated from all eligible smart wallets, but have a couple of security protections in place:
/// 1) Each account can use the paymaster at most `maxPaidTransactionsPerAccount` times.
/// 2) Each transaction can't use more than `maxSponsoredEth` ether for fees.
///
/// In the result, the maximum funds at risk are limited by the number of smart wallets and `maxSponsoredEth`/
/// `maxPaidTransactionsPerAccount` parameters, while all wallets can get benefit of smooth UX.
contract AADistributorPaymaster is IPaymaster, IAADistributorPaymaster, Ownable {
    using SafeERC20 for IERC20;

    /// @notice The contract that is responsible for ZK token distribution.
    IZkMerkleDistributor public zkMerkleDistributor;

    /// @notice Cached Merkle Root used in the ZK Merkle Distributor for verification.
    bytes32 public CACHED_MERKLE_ROOT;

    /// @notice Tracks the number of paid transactions made by each account.
    mapping(address account => uint256 count) public paidTransactionCount;

    /// @notice Maximum number of transactions that can be paid for by the paymaster per account.
    uint256 public maxPaidTransactionsPerAccount;

    /// @notice Maximum amount of ETH that can be sponsored for a single transaction.
    uint256 public maxSponsoredEth;

    /// @dev Ensures that only the bootloader can call certain functions.
    modifier onlyBootloader() {
        require(msg.sender == BOOTLOADER_FORMAL_ADDRESS, "Only bootloader can call this method");
        // Continue execution if called from the bootloader.
        _;
    }

    /// @param _zkMerkleDistributor The contract that is responsible for ZK token distribution.
    /// @param _maxPaidTransactionsPerAccount The maximum number of transactions each account is allowed to have paid by the paymaster.
    /// @param _maxSponsoredEth The maximum amount of ETH that the paymaster will sponsor for any single transaction.
    constructor(
        IZkMerkleDistributor _zkMerkleDistributor,
        uint256 _maxPaidTransactionsPerAccount,
        uint256 _maxSponsoredEth
    ) {
        require(address(_zkMerkleDistributor) != address(0), "Merkle distributor cannot be address(0)");
        zkMerkleDistributor = _zkMerkleDistributor;
        CACHED_MERKLE_ROOT = zkMerkleDistributor.MERKLE_ROOT();

        maxPaidTransactionsPerAccount = _maxPaidTransactionsPerAccount;
        emit MaxPaidTransactionsPerAccountUpdated(0, _maxPaidTransactionsPerAccount);
        maxSponsoredEth = _maxSponsoredEth;
        emit MaxSponsoredEthUpdated(0, _maxSponsoredEth);
    }

    /// @inheritdoc IPaymaster
    function validateAndPayForPaymasterTransaction(bytes32, bytes32, Transaction calldata _transaction)
        external
        payable
        onlyBootloader
        returns (bytes4, bytes memory)
    {
        address from = address(uint160(uint256(_transaction.from)));
        // Prevent spamming by limiting the number of paid transactions per account.
        uint256 newTransactionCount = paidTransactionCount[from] + 1;
        require(newTransactionCount <= maxPaidTransactionsPerAccount, "Account transaction limit exceeded");
        paidTransactionCount[from] = newTransactionCount;

        // Check that initiator account is a smart wallet.
        require(from.code.length > 0, "Initiator account is an EOA");

        // Check the paymaster input flow for consistency.
        bytes4 paymasterInputSelector = bytes4(_transaction.paymasterInput[0:4]);
        require(paymasterInputSelector == IPaymasterFlow.general.selector, "Paymaster: Unsupported paymaster flow");

        // Extract the proof of inclusion in the Merkle Tree to verify
        // that the account is qualified for the sponsorship.
        bytes memory proofData;

        // The Merkle proof can be stored inside the paymaster input, but if the account calls
        // Distributor we can extract the proof from calldata directly.
        address to = address(uint160(uint256(_transaction.to)));
        if (to == address(zkMerkleDistributor)) {
            bytes4 selector = bytes4(_transaction.data[0:4]);
            require(
                selector == IZkMerkleDistributor.claim.selector,
                "Only claim function is expected to be sponsored for the Merkle Distributor contract"
            );
            // Extract the proof from the calldata as it is a part of claim function anyway.
            proofData = _transaction.data[4:];
        } else {
            (proofData) = abi.decode(_transaction.paymasterInput[4:], (bytes));
        }
        // Verify that account is qualified for the sponsorship.
        (uint256 index, uint256 amount, bytes32[] memory merkleProof) =
            abi.decode(proofData, (uint256, uint256, bytes32[]));
        bytes32 node = keccak256(abi.encodePacked(index, from, amount));
        require(MerkleProof.verify(merkleProof, CACHED_MERKLE_ROOT, node), "Invalid Merkle proof");

        // Note, that while the minimal amount of ETH needed is tx.gasPrice * tx.gasLimit,
        // neither paymaster nor account are allowed to access this context variable.
        uint256 requiredETH = _transaction.gasLimit * _transaction.maxFeePerGas;
        require(requiredETH <= maxSponsoredEth, "Requested ETH exceeds sponsorship limit");

        // The bootloader never returns any data, so it can safely be ignored here.
        (bool success,) = payable(BOOTLOADER_FORMAL_ADDRESS).call{value: requiredETH}("");
        require(success, "Paymaster: Failed to transfer tx fee to the bootloader");

        return (PAYMASTER_VALIDATION_SUCCESS_MAGIC, new bytes(0));
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

    /// @notice Sets a new maximum number of transactions that can be paid for by the paymaster per account.
    /// @param _maxPaidTransactionsPerAccount The new maximum number of transactions per account.
    function setMaxPaidTransactionsPerAccount(uint256 _maxPaidTransactionsPerAccount) public onlyOwner {
        emit MaxPaidTransactionsPerAccountUpdated(maxPaidTransactionsPerAccount, _maxPaidTransactionsPerAccount);
        maxPaidTransactionsPerAccount = _maxPaidTransactionsPerAccount;
    }

    /// @notice Sets a new maximum amount of ETH that can be sponsored for a single transaction.
    /// @param _maxSponsoredEth The new maximum amount of ETH sponsorship per transaction.
    function setMaxSponsoredEth(uint256 _maxSponsoredEth) public onlyOwner {
        emit MaxSponsoredEthUpdated(maxSponsoredEth, _maxSponsoredEth);
        maxSponsoredEth = _maxSponsoredEth;
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

    /// @dev Contract should receive/hold ETH to pay fees as a paymaster.
    receive() external payable {}
}
