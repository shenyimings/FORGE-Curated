// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IFunding} from "./../interfaces/IFunding.sol";
import {IOracle} from "./../interfaces/IOracle.sol";
import {ISwapper} from "./../interfaces/ISwapper.sol";

library EventsLib {
    // ========== FACTORIES ==========
    event BoxCreated(
        address indexed box,
        address indexed asset,
        address indexed owner,
        address curator,
        string name,
        string symbol,
        uint256 maxSlippage,
        uint256 slippageEpochDuration,
        uint256 shutdownSlippageDuration,
        uint256 shutdownWarmup
    );

    // ========== ACCESS CONTROL ==========
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event CuratorUpdated(address indexed previousCurator, address indexed newCurator);
    event GuardianUpdated(address indexed previousGuardian, address indexed newGuardian);
    event AllocatorUpdated(address indexed account, bool isAllocator);
    event FeederUpdated(address indexed account, bool isFeeder);

    // ========== INVESTMENT MANAGEMENT ==========
    event Allocation(
        IERC20 indexed token,
        uint256 assets,
        uint256 expectedTokens,
        uint256 actualTokens,
        int256 slippagePct,
        ISwapper indexed swapper,
        bytes data
    );
    event Deallocation(
        IERC20 indexed token,
        uint256 tokens,
        uint256 expectedAssets,
        uint256 actualAssets,
        int256 slippagePct,
        ISwapper indexed swapper,
        bytes data
    );
    event Reallocation(
        IERC20 indexed fromToken,
        IERC20 indexed toToken,
        uint256 tokensFrom,
        uint256 expectedTokensTo,
        uint256 actualTokensTo,
        int256 slippagePct,
        ISwapper indexed swapper,
        bytes data
    );
    event Pledge(IFunding indexed fundingModule, bytes facilityData, IERC20 collateralToken, uint256 collateralAmount);
    event Depledge(IFunding indexed fundingModule, bytes facilityData, IERC20 collateralToken, uint256 collateralAmount);
    event Borrow(IFunding indexed fundingModule, bytes facilityData, IERC20 debtToken, uint256 borrowAmount);
    event Repay(IFunding indexed fundingModule, bytes facilityData, IERC20 debtToken, uint256 repayAmount);
    event Flash(address indexed caller, IERC20 indexed token, uint256 amount);

    // ========== MISC ==========
    event SlippageAccumulated(uint256 amount, uint256 total);
    event SlippageEpochReset(uint256 newEpochStart);
    event MaxSlippageUpdated(uint256 previousMaxSlippage, uint256 newMaxSlippage);
    event Skim(IERC20 indexed token, address indexed recipient, uint256 amount);

    // ========== CONFIGURATION ==========
    event TokenAdded(IERC20 indexed token, IOracle indexed oracle);
    event TokenRemoved(IERC20 indexed token);
    event TokenOracleChanged(IERC20 indexed token, IOracle indexed oracle);
    event FundingModuleAdded(IFunding indexed fundingModule);
    event FundingFacilityAdded(IFunding indexed fundingModule, bytes facilityData);
    event FundingCollateralAdded(IFunding indexed fundingModule, IERC20 collateralToken);
    event FundingDebtAdded(IFunding indexed fundingModule, IERC20 debtToken);
    event FundingModuleRemoved(IFunding indexed fundingModule);
    event FundingFacilityRemoved(IFunding indexed fundingModule, bytes facilityData);
    event FundingCollateralRemoved(IFunding indexed fundingModule, IERC20 collateralToken);
    event FundingDebtRemoved(IFunding indexed fundingModule, IERC20 debtToken);
    event SkimRecipientUpdated(address indexed previousRecipient, address indexed newRecipient);
    event Shutdown(address indexed guardian);
    event Recover(address indexed guardian);

    // ========== TIMELOCK ==========
    event TimelockSubmitted(bytes4 indexed selector, bytes data, uint256 executableAt, address who);
    event TimelockRevoked(bytes4 indexed selector, bytes data, address who);
    event TimelockIncreased(bytes4 indexed selector, uint256 newDuration, address who);
    event TimelockDecreased(bytes4 indexed selector, uint256 newDuration, address who);
    event TimelockExecuted(bytes4 indexed selector, bytes data, address who);
}
