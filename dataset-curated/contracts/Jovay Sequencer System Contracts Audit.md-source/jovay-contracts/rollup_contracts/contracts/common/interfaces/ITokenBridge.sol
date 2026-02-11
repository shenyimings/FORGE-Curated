// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface ITokenBridge {
    event TokenMappingChanged(address indexed token, address indexed tokenTo);

    /**
     * set token mapping
     * @param token_; this chain token address
     * @param tokenTo_; target chain token address
     */
    function setTokenMapping(address token_, address tokenTo_) payable external;
}
