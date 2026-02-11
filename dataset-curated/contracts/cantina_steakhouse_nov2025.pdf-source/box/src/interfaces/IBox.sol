// SPDX-License-Identifier: MIT
// Copyright (c) 2025 Steakhouse
pragma solidity >=0.8.0;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IFunding} from "./IFunding.sol";
import {IOracle} from "./IOracle.sol";
import {ISwapper} from "./ISwapper.sol";

/// @notice Callback interface for Box flash loans
interface IBoxFlashCallback {
    function onBoxFlash(IERC20 token, uint256 amount, bytes calldata data) external;
}

interface IBox is IERC4626 {
    /* FUNCTIONS */

    // ========== STATE FUNCTIONS ==========
    function asset() external view returns (address);
    function slippageEpochDuration() external view returns (uint256);
    function shutdownSlippageDuration() external view returns (uint256);
    function shutdownWarmup() external view returns (uint256);
    function owner() external view returns (address);
    function curator() external view returns (address);
    function guardian() external view returns (address);
    function shutdownTime() external view returns (uint256);
    function skimRecipient() external view returns (address);
    function isAllocator(address account) external view returns (bool);
    function isFeeder(address account) external view returns (bool);
    function tokens(uint256 index) external view returns (IERC20);
    function oracles(IERC20 token) external view returns (IOracle);
    function maxSlippage() external view returns (uint256);
    function accumulatedSlippage() external view returns (uint256);
    function slippageEpochStart() external view returns (uint256);
    function executableAt(bytes calldata data) external view returns (uint256);

    // ========== INVESTMENT MANAGEMENT ==========
    function skim(IERC20 token) external;
    function allocate(
        IERC20 token,
        uint256 assetsAmount,
        ISwapper swapper,
        bytes calldata data
    ) external returns (uint256 expected, uint256 received);
    function deallocate(
        IERC20 token,
        uint256 tokensAmount,
        ISwapper swapper,
        bytes calldata data
    ) external returns (uint256 expected, uint256 received);
    function reallocate(
        IERC20 from,
        IERC20 to,
        uint256 tokensAmount,
        ISwapper swapper,
        bytes calldata data
    ) external returns (uint256 expected, uint256 received);

    // ========== SIMPLE FUNDING OPERATIONS ==========
    function pledge(IFunding fundingModule, bytes calldata facilityData, IERC20 collateralToken, uint256 collateralAmount) external;
    function depledge(IFunding fundingModule, bytes calldata facilityData, IERC20 collateralToken, uint256 collateralAmount) external;
    function borrow(IFunding fundingModule, bytes calldata facilityData, IERC20 debtToken, uint256 borrowAmount) external;
    function repay(IFunding fundingModule, bytes calldata facilityData, IERC20 debtToken, uint256 repayAmount) external;

    // ========== COMPLEX FUNDING OPERATIONS WITH FLASHLOAN AND SWAPPER ==========
    function flash(IERC20 flashToken, uint256 flashAmount, bytes calldata data) external;

    // ========== EMERGENCY ==========
    function shutdown() external;
    function recover() external;

    // ========== ADMIN FUNCTIONS ==========
    function setSkimRecipient(address newSkimRecipient) external;
    function transferOwnership(address newOwner) external;
    function setCurator(address newCurator) external;
    function setGuardian(address newGuardian) external;
    function setIsAllocator(address account, bool newIsAllocator) external;

    // ========== TIMELOCK GOVERNANCE ==========
    function submit(bytes calldata data) external;
    function timelock(bytes4 selector) external view returns (uint256);
    function revoke(bytes calldata data) external;
    function increaseTimelock(bytes4 selector, uint256 newDuration) external;
    function decreaseTimelock(bytes4 selector, uint256 newDuration) external;
    function abdicateTimelock(bytes4 selector) external;

    // ========== TIMELOCKED FUNCTIONS ==========
    function setIsFeeder(address account, bool newIsFeeder) external;
    function setMaxSlippage(uint256 newMaxSlippage) external;
    function addToken(IERC20 token, IOracle oracle) external;
    function removeToken(IERC20 token) external;
    function changeTokenOracle(IERC20 token, IOracle oracle) external;

    // ========== VIEW FUNCTIONS ==========
    function isToken(IERC20 token) external view returns (bool);
    function isTokenOrAsset(IERC20 token) external view returns (bool);
    function tokensLength() external view returns (uint256);
    function isShutdown() external view returns (bool);
    function isWinddown() external view returns (bool);

    // ========== FUNDING ADMIN FUNCTIONS ==========
    function addFunding(IFunding fundingModule) external;
    function addFundingFacility(IFunding fundingModule, bytes calldata facilityData) external;
    function addFundingCollateral(IFunding fundingModule, IERC20 collateralToken) external;
    function addFundingDebt(IFunding fundingModule, IERC20 debtToken) external;
    function removeFunding(IFunding fundingModule) external;
    function removeFundingFacility(IFunding fundingModule, bytes calldata facilityData) external;
    function removeFundingCollateral(IFunding fundingModule, IERC20 collateralToken) external;
    function removeFundingDebt(IFunding fundingModule, IERC20 debtToken) external;

    // ========== FUNDING VIEW FUNCTIONS ==========
    function fundings(uint256 index) external view returns (IFunding);
    function fundingsLength() external view returns (uint256);
    function isFunding(IFunding fundingModule) external view returns (bool);
}
