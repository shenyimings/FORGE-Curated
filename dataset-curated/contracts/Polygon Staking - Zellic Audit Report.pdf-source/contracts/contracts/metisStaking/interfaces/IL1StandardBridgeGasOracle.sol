// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

interface IL1StandardBridgeGasOracle {
    function getMinL2Gas() external view returns (uint256);

    function getDiscount() external view returns (uint256);
}
