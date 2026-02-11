// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IBridgeBase {
    error InvalidInitAddress();
    error ErrorCallerIsNotMailBox();

    function pause() external;

    function unpause() external;
}