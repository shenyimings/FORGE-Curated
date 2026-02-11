// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../bridge/interfaces/IL2ETHBridge.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

contract L2CoinBase is OwnableUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {
    address public l2EthBridge;

    receive() external payable {
    }

    constructor(){
        _disableInitializers();
    }

    function initialize(address _l2EthBridge) external initializer {
        OwnableUpgradeable.__Ownable_init();
        l2EthBridge = _l2EthBridge;
    }

    // Withdrawal permission account
    mapping(address => bool) public isWithdrawer;

    // Whitelisted accounts on L1, to which withdrawals can be made
    mapping(address => bool) public whiteListOnL1;

    modifier onlyWithdrawer() {
        // @note In the decentralized mode, it should be only called by a list of validator.
        require(isWithdrawer[_msgSender()], "INVALID_PERMISSION : sender is not withdrawer");
        _;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    event SetL2EthBridge(address indexed l2EthBridge);

    event AddWithdrawer(address indexed newWithdrawer);

    event RemoveWithdrawer(address indexed oldWithdrawer);

    event AddWhiteAddress(address indexed whiteAddress);

    event RemoveWhiteAddress(address indexed whiteAddress);

    event CoinBaseWithdraw(address indexed _target, uint256 indexed amount);

    function setL2EthBridge(address _newL2EthBridge) whenPaused onlyOwner external {
        l2EthBridge = _newL2EthBridge;
        emit SetL2EthBridge(_newL2EthBridge);
    }

    function addWithdrawer(address _newWithdrawer) onlyOwner external {
        isWithdrawer[_newWithdrawer] = true;

        emit AddWithdrawer(_newWithdrawer);
    }

    function removeWithdrawer(address _oldWithdrawer) onlyOwner external {
        isWithdrawer[_oldWithdrawer] = false;

        emit RemoveWithdrawer(_oldWithdrawer);
    }

    function addWhiteAddress(address _whiteAddress) onlyOwner external {
        whiteListOnL1[_whiteAddress] = true;

        emit AddWhiteAddress(_whiteAddress);
    }

    function removeWhiteAddress(address _whiteAddress) onlyOwner external {
        whiteListOnL1[_whiteAddress] = false;

        emit RemoveWhiteAddress(_whiteAddress);
    }

    function withdraw(address _target, uint256 _amount) onlyWithdrawer whenNotPaused nonReentrant public {
        require(whiteListOnL1[_target], "INVALID_PERMISSION : target is not receiver on L1");
        require(_amount <= address(this).balance, "INVALID_PERMISSION : withdraw amount must smaller than or equal to balance");

        bytes memory message_ = abi.encodeCall(IL2ETHBridge.withdraw, (_target, _amount, 0, ""));
        (bool success_, ) = l2EthBridge.call{value : _amount}(message_);
        require(success_, "withdraw failed in L2EthBridge");
        emit CoinBaseWithdraw(_target, _amount);
    }

    function withdrawAll(address _target) onlyWithdrawer external {
        withdraw(_target,address(this).balance);
    }
}