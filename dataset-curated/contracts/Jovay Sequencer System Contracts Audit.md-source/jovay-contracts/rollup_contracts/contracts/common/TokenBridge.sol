// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./BridgeBase.sol";
import "./interfaces/ITokenBridge.sol";

abstract contract TokenBridge is BridgeBase, ITokenBridge {
    mapping(address => address) public tokenMapping;

    mapping(address => uint256) public balanceOf;

    function setTokenMapping(address token_, address tokenTo_) public payable virtual override onlyOwner whenNotPaused {
        tokenMapping[token_] = tokenTo_;
        emit TokenMappingChanged(token_, tokenTo_);
    }

    function _increaseBalance(address token_, uint256 amount_) internal {
        balanceOf[token_] += amount_;
    }

    function _decreaseBalance(address token_, uint256 amount_) internal {
        require(balanceOf[token_] >= amount_, "TokenBridge: balance not enough");
        balanceOf[token_] -= amount_;
    }

    uint256[50] private __gap;
}
