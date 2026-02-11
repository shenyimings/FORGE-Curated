// SPDX-FileCopyrightText: 2024 Lido <info@lido.fi>
// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

interface IAmountConverter {
    function getExpectedOut(
        address tokenFrom_,
        address tokenTo_,
        uint256 amountFrom_
    ) external view returns (uint256);
}
