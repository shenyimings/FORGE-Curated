// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IEulerEarnAdminHandler {
    function submitTimelock(uint256 _newTimelock, uint8 i) external;

    function setFee(uint256 _newTimelock, uint8 i) external;

    function setFeeRecipient(bool zeroFeeRecipient, uint8 i) external;

    function submitCap(uint256 _newSupplyCap, uint8 i, uint8 j) external;

    function submitMarketRemoval(uint8 i, uint8 j) external;

    function revokePendingTimelock(uint8 i) external;

    function revokePendingCap(uint8 i, uint8 j) external;

    function revokePendingMarketRemoval(uint8 i, uint8 j) external;

    function acceptTimelock(uint8 i) external;

    function acceptCap(uint8 i, uint8 j) external;

    function setSupplyQueue(uint8 i, uint8 j) external;
}
