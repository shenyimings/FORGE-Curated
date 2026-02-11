// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.20;

import "./ILevelMinting.sol";

interface IAaveReserveManager {
    event DepositedToAave(uint256 amount, address token);
    event WithdrawnFromAave(uint256 amount, address token);

    function depositToAave(address token, uint256 amount) external;

    function withdrawFromAave(address token, uint256 amount) external;

    function convertATokentolvlUSD(
        address token,
        uint256 amount
    ) external returns (uint256);

    function setAaveV3PoolAddress(address newAddress) external;
}
