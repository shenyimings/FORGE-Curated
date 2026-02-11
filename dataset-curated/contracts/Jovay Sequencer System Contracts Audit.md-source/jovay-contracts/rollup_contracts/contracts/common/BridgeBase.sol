// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;


import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {AddressUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";

import "./interfaces/IBridgeBase.sol";

abstract contract BridgeBase is OwnableUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable, IBridgeBase {
    using AddressUpgradeable for address;

    address public mailBox;

    address public toBridge;

    modifier onlyMailBox() {
        // check caller is mailBox
        if (_msgSender() != mailBox) {
            revert ErrorCallerIsNotMailBox();
        }
        _;
    }

    constructor(){
        _disableInitializers();
    }

    function initialize(address mailBox_, address toBridge_, address owner) external initializer {
        OwnableUpgradeable.__Ownable_init();
        PausableUpgradeable.__Pausable_init();
        ReentrancyGuardUpgradeable.__ReentrancyGuard_init();

        require(mailBox_ != address(0) && toBridge_ != address(0) && owner != address(0), "initialize contract address must not zero");
        mailBox = mailBox_;
        toBridge = toBridge_;
        _transferOwnership(owner);
    }

    function setMailBox(address mailBox_) external whenPaused onlyOwner {
        require(mailBox_ != address(0), "mailBox cannot be set to 0");
        mailBox = mailBox_;
    }

    function setToBridge(address toBridge_) external whenPaused onlyOwner {
        require(toBridge_ != address(0), "toBridge cannot be set to 0");
        toBridge = toBridge_;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    // function _doCallback(address to_, bytes memory msg_) internal {
    //     if (msg_.length > 0 && to_.code.length > 0) {
    //         (bool success,) = to_.call(msg_);
    //         require(success, "LayerBase: callback failed");
    //     }
    // }

    function mailBoxCall(bytes memory msg_) internal {
        mailBox.functionCallWithValue(msg_, msg.value, "LayerBase: mailbox call failed");
    }

    uint256[50] private __gap;
}
