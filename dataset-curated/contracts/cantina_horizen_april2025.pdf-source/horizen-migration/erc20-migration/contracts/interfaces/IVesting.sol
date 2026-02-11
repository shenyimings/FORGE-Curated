// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.0;

interface IVesting {
    function beneficiary() external view returns(address);
    function startVesting() external;
}