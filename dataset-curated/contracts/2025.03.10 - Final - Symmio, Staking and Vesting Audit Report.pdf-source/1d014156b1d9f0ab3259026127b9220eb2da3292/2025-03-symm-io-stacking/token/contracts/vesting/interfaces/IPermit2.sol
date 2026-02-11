// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.18;

interface IPermit2 {
    function approve(address token, address spender, uint160 amount, uint48 expiration) external;
}
