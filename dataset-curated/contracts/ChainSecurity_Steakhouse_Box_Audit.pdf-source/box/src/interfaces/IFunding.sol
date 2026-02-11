// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Steakhouse
pragma solidity >=0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IOracle} from "./IOracle.sol";

interface IOracleCallback {
    /// @dev RIs considered to have a price of ORACLE_PRECISION
    function asset() external view returns (address);

    /// @dev Returns an oracle for tokens that are not the asset
    function oracles(IERC20 token) external view returns (IOracle);
}

/**
 * @notice Interface for a funding module
 * @notice `nav` should never revert
 */
interface IFunding {
    // ========== ADMIN ==========
    function addFacility(bytes calldata facilityData) external;
    function removeFacility(bytes calldata facilityData) external;
    function isFacility(bytes calldata facilityData) external view returns (bool);
    function facilities(uint256 index) external view returns (bytes memory);
    function facilitiesLength() external view returns (uint256);

    function addCollateralToken(IERC20 collateralToken) external;
    function removeCollateralToken(IERC20 collateralToken) external;
    function isCollateralToken(IERC20 collateralToken) external view returns (bool);
    function collateralTokens(uint256 index) external view returns (IERC20);
    function collateralTokensLength() external view returns (uint256);

    function addDebtToken(IERC20 debtToken) external;
    function removeDebtToken(IERC20 debtToken) external;
    function isDebtToken(IERC20 debtToken) external view returns (bool);
    function debtTokens(uint256 index) external view returns (IERC20);
    function debtTokensLength() external view returns (uint256);

    // ========== ACTIONS ==========
    function skim(IERC20 token) external;
    function pledge(bytes calldata facilityData, IERC20 collateralToken, uint256 collateralAmount) external;
    function depledge(bytes calldata facilityData, IERC20 collateralToken, uint256 collateralAmount) external;
    function borrow(bytes calldata facilityData, IERC20 debtToken, uint256 borrowAmount) external;
    function repay(bytes calldata facilityData, IERC20 debtToken, uint256 repayAmount) external;

    // ========== POSITION ==========
    function ltv(bytes calldata facilityData) external view returns (uint256);
    function debtBalance(bytes calldata facilityData, IERC20 debtToken) external view returns (uint256);
    function collateralBalance(bytes calldata facilityData, IERC20 collateralToken) external view returns (uint256);
    function debtBalance(IERC20 debtToken) external view returns (uint256);
    function collateralBalance(IERC20 collateralToken) external view returns (uint256);
    function nav(IOracleCallback oraclesProvider) external view returns (uint256);
}
