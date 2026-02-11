// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

contract L1GasOracle is OwnableUpgradeable {
    uint256 public l1FeePerByte;

    // the fee of da for last batch
    uint256 public lastBatchDaFee;

    // the fee of commit and verify for last batch
    uint256 public lastBatchExecFee;

    // the tx length of all tx in last batch
    uint256 public lastBatchByteLength;

    // The changing trend of the current block base fee and blob base fee compared to the previous batch
    uint256 public blobBaseFeeScala;
    uint256 public baseFeeScala;

    // the constant profit of one batch
    uint256 public l1Profit;

    // the constant parameter for the whole fee of L1
    uint256 public totalScala;

    // relayer is who can send L1 fee to jovay
    mapping(address => bool) public isRelayer;

    // the lower limit of tx length in one batch
    uint256 private constant MIN_TX_LENGTH_LIMIT = 6 * 128 * 1024;

    // the lower limit of tx length in one batch
    uint256 private constant MAX_TX_LENGTH_LIMIT = 1e9;

    // the upper limit of L1 base fee
    uint256 private constant MAX_L1_BASE_FEE_LIMIT = 1e9;

    // the upper limit of L1 blob base fee
    uint256 private constant MAX_L1_BLOB_BASE_FEE_LIMIT = 1e9;

    // the upper limit of the sum of commit and verify tx's gas used;
    uint256 public maxL1ExecGasUsedLimit;

    // the max limit of blob gas used, mainnet is 6blobs;
    uint256 public maxL1BlobGasUsedLimit;

    constructor(){
        _disableInitializers();
    }

    function initialize(uint256 _lastBatchDaFee, uint256 _lastBatchExecFee, uint256 _lastBatchByteLength) external initializer {
        OwnableUpgradeable.__Ownable_init();
        lastBatchDaFee = _lastBatchDaFee;
        lastBatchExecFee = _lastBatchExecFee;
        maxL1ExecGasUsedLimit = 1e6;
        maxL1BlobGasUsedLimit = 6 * 128 * 1024;
        totalScala = 110;
        blobBaseFeeScala = 100;
        baseFeeScala = 100;
        if (_lastBatchByteLength < MIN_TX_LENGTH_LIMIT) {
            lastBatchByteLength = MIN_TX_LENGTH_LIMIT;
        } else {
            lastBatchByteLength = _lastBatchByteLength;
        }
        CalcL1FeePerByte();
        isRelayer[_msgSender()] = true;
    }

    function CalcL1FeePerByte() internal {
        l1FeePerByte = (((lastBatchDaFee * blobBaseFeeScala / 100) + (lastBatchExecFee * baseFeeScala / 100) + l1Profit) / lastBatchByteLength);
        l1FeePerByte = l1FeePerByte * totalScala / 100;
    }

    modifier onlyRelayer() {
        // @note In the decentralized mode, it should be only called by a list of validator.
        require(isRelayer[_msgSender()], "INVALID_PERMISSION : sender is not relayer");
        _;
    }

    event SetNewBatchBlobFeeAndTxFee(uint256 _lastBatchDaFee, uint256 _lastBatchExecFee, uint256 _lastBatchByteLength);

    event SetBlobBaseFeeScalaAndTxFeeScala(uint256 _baseFeeScala, uint256 _blobBaseFeeScala);

    event SetL1Profit(uint256 _l1Profit);

    event SetTotalScala(uint256 _totalScala);

    event SetMaxL1ExecGasUsedLimit(uint256 _maxL1ExecGasUsedLimit);

    event SetMaxL1BlobGasUsedLimit(uint256 _maxL1BlobGasUsedLimit);

    event AddRelayer(address relayer);

    event RemoveRelayer(address oldRelayer);

    function setNewBatchBlobFeeAndTxFee(uint256 _lastBatchDaFee,
        uint256 _lastBatchExecFee,
        uint256 _lastBatchByteLength) onlyRelayer external {
        if (_lastBatchByteLength < MIN_TX_LENGTH_LIMIT) {
            _lastBatchByteLength = MIN_TX_LENGTH_LIMIT;
        }
        if (_lastBatchByteLength > MAX_TX_LENGTH_LIMIT) {
            _lastBatchByteLength = MAX_TX_LENGTH_LIMIT;
        }
        if (_lastBatchExecFee > MAX_L1_BASE_FEE_LIMIT * maxL1ExecGasUsedLimit) {
            _lastBatchExecFee = MAX_L1_BASE_FEE_LIMIT * maxL1ExecGasUsedLimit;
        }
        if (_lastBatchDaFee > MAX_L1_BLOB_BASE_FEE_LIMIT * maxL1BlobGasUsedLimit) {
            _lastBatchDaFee = MAX_L1_BLOB_BASE_FEE_LIMIT * maxL1BlobGasUsedLimit;
        }
        lastBatchByteLength = _lastBatchByteLength;
        lastBatchDaFee = _lastBatchDaFee;
        lastBatchExecFee = _lastBatchExecFee;
        CalcL1FeePerByte();

        emit SetNewBatchBlobFeeAndTxFee(_lastBatchDaFee, _lastBatchExecFee, _lastBatchByteLength);
    }

    function setBlobBaseFeeScalaAndTxFeeScala(uint256 _baseFeeScala,
        uint256 _blobBaseFeeScala) onlyRelayer external {
        require(_baseFeeScala != 0 && _blobBaseFeeScala != 0, "scala must not be zero");
        baseFeeScala = _baseFeeScala;
        blobBaseFeeScala = _blobBaseFeeScala;
        CalcL1FeePerByte();
        emit SetBlobBaseFeeScalaAndTxFeeScala(_baseFeeScala, _blobBaseFeeScala);
    }

    function setL1Profit(uint256 _l1Profit) onlyOwner external {
        l1Profit = _l1Profit;
        CalcL1FeePerByte();

        emit SetL1Profit(_l1Profit);
    }

    function setTotalScala(uint256 _totalScala) onlyOwner external {
        totalScala = _totalScala;
        CalcL1FeePerByte();

        emit SetTotalScala(_totalScala);
    }

    function setMaxL1ExecGasUsedLimit(uint256 _maxL1ExecGasUsedLimit) onlyOwner external {
        maxL1ExecGasUsedLimit = _maxL1ExecGasUsedLimit;
        CalcL1FeePerByte();

        emit SetMaxL1ExecGasUsedLimit(_maxL1ExecGasUsedLimit);
    }

    function setMaxL1BlobGasUsedLimit(uint256 _maxL1BlobGasUsedLimit) onlyOwner external {
        maxL1BlobGasUsedLimit = _maxL1BlobGasUsedLimit;
        CalcL1FeePerByte();

        emit SetMaxL1BlobGasUsedLimit(_maxL1BlobGasUsedLimit);
    }

    function addRelayer(address _newRelayer) onlyOwner external {
        isRelayer[_newRelayer] = true;

        emit AddRelayer(_newRelayer);
    }

    function removeRelayer(address _oldRelayer) onlyOwner external {
        isRelayer[_oldRelayer] = false;

        emit RemoveRelayer(_oldRelayer);
    }

    function getTxL1Fee(uint256 txLength) external view returns(uint256){
        return l1FeePerByte * txLength;
    }
}