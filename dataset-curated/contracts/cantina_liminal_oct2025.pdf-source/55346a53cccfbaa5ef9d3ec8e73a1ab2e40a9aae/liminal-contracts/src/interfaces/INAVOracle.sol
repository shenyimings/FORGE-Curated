// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.28;

/**
 * @title INAVOracle
 * @notice Interface for a contract to manage NAV
 */
interface INAVOracle {
    function getNAV() external view returns (uint256);
    function increaseTotalAssets(uint256 amount) external;
    function decreaseTotalAssets(uint256 amount) external;
}
