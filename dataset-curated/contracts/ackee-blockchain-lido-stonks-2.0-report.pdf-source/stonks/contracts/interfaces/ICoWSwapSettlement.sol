// SPDX-FileCopyrightText: 2024 Lido <info@lido.fi>
// SPDX-License-Identifier: MIT

pragma solidity 0.8.23;

interface ICoWSwapSettlement {
    function domainSeparator() external view returns (bytes32);
}
