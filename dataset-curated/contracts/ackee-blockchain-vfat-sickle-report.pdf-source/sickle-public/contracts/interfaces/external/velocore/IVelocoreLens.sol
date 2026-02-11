// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

type Token is bytes32;

interface IVelocoreLens {
    function spotPrice(
        Token base,
        Token quote,
        uint256 amount
    ) external returns (uint256);
}
