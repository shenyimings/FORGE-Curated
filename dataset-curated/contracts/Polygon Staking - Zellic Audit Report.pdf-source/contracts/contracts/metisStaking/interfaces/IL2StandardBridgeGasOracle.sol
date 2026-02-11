// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

interface IL2StandardBridgeGasOracle {
    function minErc20BridgeCost() external view returns (uint256);
}
