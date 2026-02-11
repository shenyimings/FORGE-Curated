// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../interfaces/IL1Mailbox.sol";
import "../interfaces/IRollup.sol";
import "../../common/MailBoxBase.sol";
import "../libraries/verifier/WithdrawTrieVerifier.sol";
import "../interfaces/IL1MailQueue.sol";
import "@openzeppelin/contracts/utils/structs/DoubleEndedQueue.sol";

contract L1Mailbox is MailBoxBase, IL1Mailbox, IL1MailQueue {
    using DoubleEndedQueue for DoubleEndedQueue.Bytes32Deque;

    event SetL2GasLimit(uint256 oldGasLimit, uint256 newGasLimit);

    event SetL2FinalizeDepositGasUsed(uint256 oldL2FinalizeDepositGasUsed, uint256 newL2FinalizeDepositGasUsed);

    // double ended msg queue
    // begin is next finalize msg
    // end + 1 is next append msg
    DoubleEndedQueue.Bytes32Deque private msgQueue;

    bytes32 public stableRollingHash;

    // next pending msg index
    uint256 public pendingQueueIndex;

    // init with 0;
    uint256 public nextFinalizeQueueIndex;

    /// @notice The address of Rollup contract.
    address public rollup;

    /// @notice The gaslimit of L2, deposit gas limit must less than this value.
    uint256 public l2GasLimit;

    uint256 public feeBalance;

    address public withdrawer;

    uint256 public l2FinalizeDepositGasUsed;

    uint256 public lastestQueueIndex;

    modifier onlyRollup() {
        require(msg.sender == rollup, "Only callable by the Rollup");
        _;
    }

    modifier onlyWithdrawer() {
        require(msg.sender == withdrawer, "Only callable by the withdrawer");
        _;
    }

    constructor(){
        _disableInitializers();
    }

    /**
     * Contract initialization
     * @param rollup_ rollup contract address
     * @param owner_ contract owner address
     * @param baseFee_ base fee
     */
    function initialize(address rollup_, address owner_, uint256 baseFee_, uint256 _l2GasLimit, uint256 _l2FinalizeDepositGasUsed) external initializer {
        if (rollup_ == address(0) || owner_ == address(0)) {
            revert InvalidInitAddress();
        }

        if (_l2GasLimit < _l2FinalizeDepositGasUsed) {
            revert InvalidL2GasLimit();
        }
        __MailBox_init();

        rollup = rollup_;
        baseFee = baseFee_;
        l2GasLimit = _l2GasLimit;
        l2FinalizeDepositGasUsed = _l2FinalizeDepositGasUsed;
        _transferOwnership(owner_);
    }

    function setRollup(address rollup_) external whenPaused onlyOwner {
        require(rollup_ != address(0), "Invalid rollup address");
        rollup = rollup_;
    }

    function setWithdrawer(address _withdrawer) external onlyOwner {
        require(_withdrawer != address(0), "Invalid withdrawer address");
        withdrawer = _withdrawer;
    }

    function sendMsg(
        address target_,
        uint256 value_,
        bytes calldata msg_,
        uint256 gasLimit_,
        address refundAddress_
    ) external payable override onlyBridge whenNotPaused nonReentrant {
        // compute the actual cross domain message calldata.
        uint256 nonce_ = nextMsgIndex();
        bytes memory data_ = _encodeCall(_msgSender(), target_, value_, nonce_, msg_);

        // Calculate the fee and leave it in the MailBox contract
        uint256 fee_ = estimateMsgFee(gasLimit_);
        require(gasLimit_ < l2GasLimit, "gasLimit must less than L2 config");
        require(gasLimit_ >= l2FinalizeDepositGasUsed, "gas limit must be bigger than or equal to the tx_fee of finalize deposit on Jovay");
        require(msg.value >= fee_ + value_, "Insufficient msg.value");

        bytes32 hash_ = keccak256(data_);
        // normally this won't happen, since each message has different nonce, but just in case.
        _sendMsgCheck(hash_);

        // append message to L1MailQueue
        _appendMsg(_getRollingHash(hash_));

        emit SentMsg(_msgSender(), target_, value_, nonce_, data_, gasLimit_, hash_);

        // refund fee to `refundAddress_`
        unchecked {
            uint256 refund_ = msg.value - fee_ - value_;
            if (refund_ > 0) {
                (bool success_,) = refundAddress_.call{value : refund_}("");
                require(success_, "Failed to refund the fee");
            }
        }
        feeBalance += fee_;
    }

    /**
     * Send L2 message to L1, need to verify the validity of the message through proof,
     * if valid, execute the corresponding message in L1 bridge contract
     * @param sender_; sender L2 bridge contract address
     * @param target_; message receiver L1 bridge contract address
     * @param value_; native token transfer amount
     * @param nonce_; message nonce value
     * @param msg_; message content sent to target_ execution
     * @param proof_; proof information used to prove the validity of the message
     */
    function relayMsgWithProof(
        address sender_,
        address target_,
        uint256 value_,
        uint256 nonce_,
        bytes memory msg_,
        L2MsgProof memory proof_
    ) external payable whenNotPaused nonReentrant {
        require(sender_ == IBridge(target_).toBridge(), "Invalid sender");
        bytes32 hash_ = keccak256(_encodeCall(sender_, target_, value_, nonce_, msg_));

        bytes32 msgRoot_ = IRollup(rollup).getL2MsgRoot(proof_.batchIndex);
        require(
            WithdrawTrieVerifier.verifyMerkleProof(msgRoot_, hash_, nonce_, proof_.merkleProof),
            "Invalid proof"
        );

        (bool success,) = target_.call{value : value_}(msg_);
        require(success, "RelayMsg Failed");
        _receiveMsgCheck(hash_);
        emit RelayedMsg(hash_, nonce_);
    }

    function withdrawDepositFee(address _target, uint256 _amount) external onlyWithdrawer whenNotPaused {
        require(_target.code.length == 0, "INVALID_PARAMETER: withdraw target must be eoa");
        require(_amount <= feeBalance, "INVALID_PARAMETER : withdraw amount must smaller than or equal to fee in mailbox");
        feeBalance -= _amount;
        (bool success,) = _target.call{value : _amount}("");
        require(success, "INTERNAL_ERROR : withdraw fee Failed");
    }

    /**
     * @notice Set new L2 Gas limit for deposit
     */
    function setL2GasLimit(uint256 _l2GasLimit) external onlyOwner {
        if (l2FinalizeDepositGasUsed > _l2GasLimit) {
            revert SetL2GasLimitSmallerThanGasUsed();
        }
        uint256 oldL2GasLimit = l2GasLimit;
        l2GasLimit = _l2GasLimit;
        emit SetL2GasLimit(oldL2GasLimit, _l2GasLimit);
    }

    /**
     * @notice Set new L2 Gas used for finalize deposit
     */
    function setL2FinalizeDepositGasUsed(uint256 _l2FinalizeDepositGasUsed) external onlyOwner {
        if (_l2FinalizeDepositGasUsed > l2GasLimit) {
            revert SetL2FinalizeDepositGasUsedBiggerThanGasLimit();
        }
        uint256 oldL2FinalizeDepositGasUsed = l2FinalizeDepositGasUsed;
        l2FinalizeDepositGasUsed = _l2FinalizeDepositGasUsed;
        emit SetL2FinalizeDepositGasUsed(oldL2FinalizeDepositGasUsed, _l2FinalizeDepositGasUsed);
    }

    /**
     * @notice Returns next message index
     */
    function nextMsgIndex() public view override returns (uint256) {
        return pendingQueueIndex;
    }

    /**
     * @notice Returns message at index
     */
    function getMsg(uint256 _l1MsgCount) external view override returns (bytes32) {
        if (_l1MsgCount == 0) {
            return bytes32(0);
        }
        // totalIndex - 1 == index; index >= nextFinalizeQueueIndex or index = nextFinalizeQueueIndex - 1;
        require(_l1MsgCount >= lastestQueueIndex, "used msg must bigger than lastestQueueIndex");
        require(_l1MsgCount - 1 < pendingQueueIndex, "used msg must smaller than next pending");
        if (_l1MsgCount < lastestQueueIndex + 1) {
            return stableRollingHash;
        }
        return msgQueue.at(_l1MsgCount - lastestQueueIndex - 1);
    }

    /**
      * @notice set lastest queue index  called when pause
     */
    function setLastQueueIndex() external whenPaused onlyOwner {
        lastestQueueIndex = nextFinalizeQueueIndex;
    }

    /**
     * @notice Appends message to queue
     */
    function _appendMsg(bytes32 msg_) internal override {
        msgQueue.pushBack(msg_);
        pendingQueueIndex++;
        emit AppendMsg(pendingQueueIndex, msg_);
    }

    /**
     * @notice Pops messages from queue
     */
    function popMsgs(uint256 _l1MsgCount) external onlyRollup whenNotPaused {
        // l1MsgCount - 1 = index < pendingQueueIndex
        require(_l1MsgCount < pendingQueueIndex + 1, "finalize index must smaller than pendingQueueIndex");
        require(_l1MsgCount >= nextFinalizeQueueIndex, "finalize index must smaller than or equal to l1MsgCount");
        nextFinalizeQueueIndex = _l1MsgCount;
//        while (nextFinalizeQueueIndex < _l1MsgCount) {
//            stableRollingHash = msgQueue.popFront();
//            nextFinalizeQueueIndex++;
//        }
        emit PopMsgs(nextFinalizeQueueIndex);
    }

}
