// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

import "./interfaces/IMailBoxBase.sol";
import "./interfaces/IGasPriceOracle.sol";
interface IRelay {
    function relayMsg(
        address sender_,
        address target_,
        uint256 value_,
        uint256 msgNonce_,
        bytes calldata msg_
    ) external;
}

interface IBridge {
    function toBridge() external returns (address);
}

abstract contract MailBoxBase is OwnableUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable, IMailBoxBase, IGasPriceOracle {
    bytes32 public rollingHash;

    mapping(bytes32 => bool) public sendMsgMap;

    mapping(bytes32 => bool) public receiveMsgMap;

    uint256 public baseFee;

    /// @notice The address of Bridge contract.
    mapping(address => bool) public isBridge;

    modifier onlyBridge() {
        require(isBridge[_msgSender()], "INVALID_PERMISSION : sender is not bridge");
        _;
    }

    function __MailBox_init() internal onlyInitializing {
        OwnableUpgradeable.__Ownable_init();
        PausableUpgradeable.__Pausable_init();
        ReentrancyGuardUpgradeable.__ReentrancyGuard_init();
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function estimateMsgFee(uint256 gasLimit_) public view override returns (uint256) {
        return gasLimit_ * baseFee;
    }

    function setBaseFee(uint256 _newBaseFee) external onlyOwner {
        uint256 oldBaseFee = baseFee;
        baseFee = _newBaseFee;
        emit BaseFeeChanged(oldBaseFee, _newBaseFee);
    }

    // function nextMsgIndex() public view override virtual returns (uint256);

    /**
     * @notice Appends message to queue
     */
    function _appendMsg(bytes32 msg_) internal virtual;

    function _sendMsgCheck(bytes32 hash_) internal {
        require(!sendMsgMap[hash_], "L1 duplicated message");
        sendMsgMap[hash_] = true;
    }

    function _receiveMsgCheck(bytes32 hash_) internal {
        require(!receiveMsgMap[hash_], "L2 duplicated message");
        receiveMsgMap[hash_] = true;
    }

    function _msgExistCheck(bytes32 hash_) internal view {
        require(receiveMsgMap[hash_], "L2 message not exist");
    }

    function _encodeCall(
        address sender_,
        address target_,
        uint256 value_,
        uint256 msgNonce_,
        bytes memory msg_
    ) internal pure returns (bytes memory) {
        return abi.encodeCall(IRelay.relayMsg, (sender_, target_, value_, msgNonce_, msg_));
    }

    receive() external payable {}

    /// @notice Add an account to the bridge list.
    /// @param _bridge The address of bridge to add.
    function addBridge(address _bridge) external onlyOwner {
        isBridge[_bridge] = true;
    }

    /// @notice Remove an account from the bridge list.
    /// @param _bridge The address of account to remove.
    function removeBridge(address _bridge) external onlyOwner {
        isBridge[_bridge] = false;
    }

    function _getRollingHash(bytes32 msgHash) internal returns (bytes32 newRollingHash){
        bytes32 localRollingHash = rollingHash;
        assembly {
            let dataStart := mload(0x40)
            mstore(0x40, add(dataStart, 0x40))
            mstore(dataStart, localRollingHash)
            mstore(add(dataStart, 0x20), msgHash)
            newRollingHash := keccak256(dataStart, 0x40)
        }
        rollingHash = newRollingHash;
    }

    uint256[50] private __gap;
}
