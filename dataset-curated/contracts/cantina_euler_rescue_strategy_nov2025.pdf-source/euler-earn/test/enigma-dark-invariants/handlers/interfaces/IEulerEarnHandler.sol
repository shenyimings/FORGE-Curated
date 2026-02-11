// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IEulerEarnHandler {
    function depositEEV(uint256 _assets, uint8 i, uint8 j) external;

    function mintEEV(uint256 _assets, uint8 i, uint8 j) external;

    function withdrawEEV(uint256 _shares, uint8 i, uint8 j) external;

    function redeemEEV(uint256 _shares, uint8 i, uint8 j) external;
}
