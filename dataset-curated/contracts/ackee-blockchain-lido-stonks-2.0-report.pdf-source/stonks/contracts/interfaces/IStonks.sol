// SPDX-FileCopyrightText: 2024 Lido <info@lido.fi>
// SPDX-License-Identifier: MIT
pragma solidity 0.8.23;

interface IStonks {
    function assertQuotable() external view;
    function getOrderParameters() external view returns (address tokenFrom, address tokenTo, uint256 orderDurationInSeconds);
    function getPriceTolerance() external view returns (uint256);
    function getMaxImprovementBps() external view returns (uint256);
    function estimateTradeOutput(uint256 amount_) external view returns (uint256);
    function ALLOW_PARTIAL_FILL() external view returns (bool);
    function areSignaturesPaused() external view returns (bool);
    function isCreationPaused() external view returns (bool);
    function isKilled() external view returns (bool);
}
