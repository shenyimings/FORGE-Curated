// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Steakhouse Financial
pragma solidity 0.8.28;

import "@morpho-blue/libraries/ConstantsLib.sol";
import {MathLib} from "@morpho-blue/libraries/MathLib.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IFunding, IOracleCallback} from "./interfaces/IFunding.sol";
import {ErrorsLib} from "./libraries/ErrorsLib.sol";

/**
 * @title FundingBase
 * @notice Abstract base contract for funding modules (Aave, Morpho, etc.)
 * @dev Contains common functionality shared across all funding module implementations
 */
abstract contract FundingBase is IFunding {
    using SafeERC20 for IERC20;
    using MathLib for uint256;
    using EnumerableSet for EnumerableSet.Bytes32Set;
    using EnumerableSet for EnumerableSet.AddressSet;

    // ========== STORAGE ==========

    address public immutable owner;

    EnumerableSet.Bytes32Set internal facilitiesSet;
    EnumerableSet.AddressSet internal collateralTokensSet;
    EnumerableSet.AddressSet internal debtTokensSet;

    // ========== INITIALIZATION ==========

    /**
     * @notice Allows the contract to receive native currency
     * @dev Required for skimming native currency back to the Box
     */
    receive() external payable {}

    /**
     * @notice Fallback function to receive native currency
     * @dev Required for skimming native currency back to the Box
     */
    fallback() external payable {}

    constructor(address _owner) {
        require(_owner != address(0), ErrorsLib.InvalidAddress());
        owner = _owner;
    }

    // ========== ABSTRACT FUNCTIONS ==========

    /// @notice Calculate the net asset value of the funding module
    /// @dev Must be implemented by each module with protocol-specific logic
    function nav(IOracleCallback oraclesProvider) public view virtual returns (uint256);

    /// @notice Check if a facility is currently in use (has positions)
    /// @dev Must be implemented by each module with protocol-specific logic
    function _isFacilityUsed(bytes calldata facilityData) internal view virtual returns (bool);

    /// @notice Get the total collateral balance for a specific token
    /// @dev Must be implemented by each module with protocol-specific logic
    function _collateralBalance(IERC20 collateralToken) internal view virtual returns (uint256);

    /// @notice Get the total debt balance for a specific token
    /// @dev Must be implemented by each module with protocol-specific logic
    function _debtBalance(IERC20 debtToken) internal view virtual returns (uint256);

    // ========== COMMON ADMIN FUNCTIONS ==========

    function isFacility(bytes calldata facilityData) public view override returns (bool) {
        bytes32 facilityHash = keccak256(facilityData);
        return facilitiesSet.contains(facilityHash);
    }

    function facilitiesLength() external view returns (uint256) {
        return facilitiesSet.length();
    }

    function addCollateralToken(IERC20 collateralToken) external virtual override {
        require(msg.sender == owner, ErrorsLib.OnlyOwner());
        require(collateralTokensSet.add(address(collateralToken)), ErrorsLib.AlreadyWhitelisted());
    }

    function isCollateralToken(IERC20 collateralToken) public view override returns (bool) {
        return collateralTokensSet.contains(address(collateralToken));
    }

    function collateralTokensLength() external view returns (uint256) {
        return collateralTokensSet.length();
    }

    function collateralTokens(uint256 index) external view returns (IERC20) {
        return IERC20(collateralTokensSet.at(index));
    }

    function addDebtToken(IERC20 debtToken) external virtual override {
        require(msg.sender == owner, ErrorsLib.OnlyOwner());
        require(debtTokensSet.add(address(debtToken)), ErrorsLib.AlreadyWhitelisted());
    }

    function isDebtToken(IERC20 debtToken) public view override returns (bool) {
        return debtTokensSet.contains(address(debtToken));
    }

    function debtTokensLength() external view returns (uint256) {
        return debtTokensSet.length();
    }

    function debtTokens(uint256 index) external view returns (IERC20) {
        return IERC20(debtTokensSet.at(index));
    }

    // ========== COMMON ACTIONS ==========

    function skim(IERC20 token) external override {
        require(msg.sender == owner, ErrorsLib.OnlyOwner());

        uint256 navBefore = nav(IOracleCallback(owner));
        uint256 balance;

        if (address(token) != address(0)) {
            // ERC-20 tokens
            balance = token.balanceOf(address(this));
            require(balance > 0, ErrorsLib.InvalidAmount());
            token.safeTransfer(owner, balance);
        } else {
            // ETH
            balance = address(this).balance;
            require(balance > 0, ErrorsLib.InvalidAmount());
            payable(owner).transfer(balance);
        }

        uint256 navAfter = nav(IOracleCallback(owner));
        require(navBefore == navAfter, ErrorsLib.SkimChangedNav());
    }

    /**
     * @notice Executes multiple calls in a single transaction
     * @param data Array of encoded function calls
     * @dev Allows EOAs to execute multiple operations atomically
     */
    function multicall(bytes[] calldata data) external {
        uint256 length = data.length;
        for (uint256 i = 0; i < length; i++) {
            (bool success, bytes memory returnData) = address(this).delegatecall(data[i]);
            if (!success) {
                assembly ("memory-safe") {
                    revert(add(32, returnData), mload(returnData))
                }
            }
        }
    }

    // ========== COMMON VIEW FUNCTIONS ==========

    function debtBalance(IERC20 debtToken) external view override returns (uint256) {
        return _debtBalance(debtToken);
    }

    function collateralBalance(IERC20 collateralToken) external view override returns (uint256) {
        return _collateralBalance(collateralToken);
    }

    // ========== ENUMERABLE SET GETTERS ==========

    /// @notice Get all facility hashes as an array
    function facilitiesArray() external view returns (bytes32[] memory) {
        uint256 length = facilitiesSet.length();
        bytes32[] memory allFacilities = new bytes32[](length);
        for (uint256 i = 0; i < length; i++) {
            allFacilities[i] = facilitiesSet.at(i);
        }
        return allFacilities;
    }

    /// @notice Get all collateral token addresses as an array
    function collateralTokensArray() external view returns (address[] memory) {
        uint256 length = collateralTokensSet.length();
        address[] memory allTokens = new address[](length);
        for (uint256 i = 0; i < length; i++) {
            allTokens[i] = collateralTokensSet.at(i);
        }
        return allTokens;
    }

    /// @notice Get all debt token addresses as an array
    function debtTokensArray() external view returns (address[] memory) {
        uint256 length = debtTokensSet.length();
        address[] memory allTokens = new address[](length);
        for (uint256 i = 0; i < length; i++) {
            allTokens[i] = debtTokensSet.at(i);
        }
        return allTokens;
    }
}
