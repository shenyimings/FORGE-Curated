// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2025 Steakhouse Financial
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IBox} from "../interfaces/IBox.sol";
import {IFunding} from "../interfaces/IFunding.sol";
import {ISwapper} from "../interfaces/ISwapper.sol";
import {ErrorsLib} from "../libraries/ErrorsLib.sol";

interface IPoolAddressesProviderAave {
    function getPool() external view returns (address);
}

interface IPool {
    function flashLoan(
        address receiverAddress,
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata modes,
        address onBehalfOf,
        bytes calldata params,
        uint16 referralCode
    ) external;

    function FLASHLOAN_PREMIUM_TOTAL() external view returns (uint128);
}

interface IFlashLoanReceiver {
    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external returns (bool);

    function ADDRESSES_PROVIDER() external view returns (IPoolAddressesProviderAave);

    function POOL() external view returns (IPool);
}

interface IBoxFlashCallback {
    function onBoxFlash(IERC20 token, uint256 amount, bytes calldata data) external;
}

contract FlashLoanAave is IFlashLoanReceiver, IBoxFlashCallback {
    using SafeERC20 for IERC20;

    IPoolAddressesProviderAave public immutable override ADDRESSES_PROVIDER;
    IPool public immutable override POOL;
    address internal _box = address(0);

    constructor(IPoolAddressesProviderAave addressesProvider) {
        ADDRESSES_PROVIDER = addressesProvider;
        POOL = IPool(addressesProvider.getPool());
    }

    function _swap(IBox box, ISwapper swapper, bytes memory swapData, IERC20 fromToken, IERC20 toToken, uint256 amount) internal {
        if (address(fromToken) == box.asset()) {
            box.allocate(toToken, amount, swapper, swapData);
        } else if (address(toToken) == box.asset()) {
            box.deallocate(fromToken, amount, swapper, swapData);
        } else {
            box.reallocate(fromToken, toToken, amount, swapper, swapData);
        }
    }

    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external override returns (bool) {
        require(msg.sender == address(POOL), ErrorsLib.OnlyPool());
        require(initiator == address(this), ErrorsLib.OnlyThisContract());

        bytes4 operation = abi.decode(params, (bytes4));

        IBox box;
        IERC20 loanToken = IERC20(assets[0]);
        uint256 loanAmount = amounts[0];
        uint256 totalAmountToRepay = loanAmount + premiums[0];

        if (operation == FlashLoanAave.leverage.selector) {
            (operation, box, , , , , , , ) = abi.decode(params, (bytes4, IBox, IFunding, bytes, IERC20, IERC20, uint256, ISwapper, bytes));
        } else if (operation == FlashLoanAave.deleverage.selector) {
            (operation, box, , , , , , , , ) = abi.decode(
                params,
                (bytes4, IBox, IFunding, bytes, IERC20, uint256, IERC20, uint256, ISwapper, bytes)
            );
        } else if (operation == FlashLoanAave.refinance.selector) {
            (operation, box, , , , , , , , ) = abi.decode(
                params,
                (bytes4, IBox, IFunding, bytes, IFunding, bytes, IERC20, uint256, IERC20, uint256)
            );
        } else {
            revert("Invalid operation");
        }

        // Approve the box to pull the flash loan amount
        loanToken.forceApprove(address(box), loanAmount);

        // Call box.flash which will call back to us
        box.flash(loanToken, loanAmount, params);

        // After box.flash, we should have loanAmount back
        // We need totalAmountToRepay. The premium should come from the extra we borrowed in onBoxFlash
        uint256 currentBalance = loanToken.balanceOf(address(this));
        require(currentBalance >= totalAmountToRepay, "Insufficient balance for repayment");

        // Approve the pool to pull the repayment amount
        loanToken.forceApprove(address(POOL), totalAmountToRepay);

        return true;
    }

    function onBoxFlash(IERC20 token, uint256 amount, bytes calldata data) external {
        require(msg.sender == _box, ErrorsLib.OnlyBox());
        bytes4 operation = abi.decode(data, (bytes4));

        IBox box = IBox(msg.sender);
        IFunding fundingModule;
        bytes memory facilityData;
        IFunding fundingModule2;
        bytes memory facilityData2;
        IERC20 collateralToken;
        uint256 collateralAmount;
        IERC20 loanToken;
        uint256 loanAmount;
        ISwapper swapper;
        bytes memory swapData;

        if (operation == FlashLoanAave.leverage.selector) {
            (operation, , fundingModule, facilityData, collateralToken, loanToken, loanAmount, swapper, swapData) = abi.decode(
                data,
                (bytes4, IBox, IFunding, bytes, IERC20, IERC20, uint256, ISwapper, bytes)
            );

            // At this point, the Box already has the flash loan tokens (transferred by box.flash)

            // Record collateral balance before swap
            uint256 beforeCollateral = collateralToken.balanceOf(address(box));

            // Have Box perform the swap using its allocation functions
            _swap(box, swapper, swapData, loanToken, collateralToken, loanAmount);

            // Check how much collateral was received in the Box
            uint256 afterCollateral = collateralToken.balanceOf(address(box));
            uint256 collateralReceived = afterCollateral - beforeCollateral;

            // Have the Box pledge its own collateral to the funding module
            box.pledge(fundingModule, facilityData, collateralToken, collateralReceived);

            // Have the Box borrow loan tokens (they go to the Box)
            // We need to borrow extra to cover the flash loan premium
            uint128 flashLoanPremiumTotal = POOL.FLASHLOAN_PREMIUM_TOTAL(); // basis points (10000 = 100%)
            uint256 premium = (loanAmount * flashLoanPremiumTotal) / 10000;
            uint256 totalBorrowAmount = loanAmount + premium;
            // Note: Premium rate is queried dynamically from Aave pool
            box.borrow(fundingModule, facilityData, loanToken, totalBorrowAmount);

            // Note: For Aave flash loans, this contract needs to have a small balance
            // to cover the flash loan premium. The premium is queried dynamically from the pool.

            // The borrowed tokens are now in the Box and will be transferred back by box.flash()
        } else if (operation == FlashLoanAave.deleverage.selector) {
            (operation, , fundingModule, facilityData, collateralToken, collateralAmount, loanToken, loanAmount, swapper, swapData) = abi
                .decode(data, (bytes4, IBox, IFunding, bytes, IERC20, uint256, IERC20, uint256, ISwapper, bytes));

            // Deleverage: repay debt, withdraw collateral, swap collateral to loan tokens
            if (loanAmount == type(uint256).max) {
                loanAmount = fundingModule.debtBalance(loanToken);
            }

            // The Box already has the flash loan tokens, use them to repay debt
            box.repay(fundingModule, facilityData, loanToken, loanAmount);

            // Withdraw collateral (goes to the Box)
            box.depledge(fundingModule, facilityData, collateralToken, collateralAmount);

            // Have the Box swap its collateral tokens to loan tokens
            _swap(box, swapper, swapData, collateralToken, loanToken, collateralAmount);
        } else if (operation == FlashLoanAave.refinance.selector) {
            (
                operation,
                ,
                fundingModule,
                facilityData,
                fundingModule2,
                facilityData2,
                collateralToken,
                collateralAmount,
                loanToken,
                loanAmount
            ) = abi.decode(data, (bytes4, IBox, IFunding, bytes, IFunding, bytes, IERC20, uint256, IERC20, uint256));

            // Refinance: repay old debt, withdraw collateral, pledge to new module, borrow from new module
            if (loanAmount == type(uint256).max) {
                loanAmount = fundingModule.debtBalance(loanToken);
            }
            if (collateralAmount == type(uint256).max) {
                collateralAmount = fundingModule.collateralBalance(collateralToken);
            }

            // Repay the old debt
            box.repay(fundingModule, facilityData, loanToken, loanAmount);

            // Withdraw collateral from old module
            box.depledge(fundingModule, facilityData, collateralToken, collateralAmount);

            // Pledge collateral to new module
            box.pledge(fundingModule2, facilityData2, collateralToken, collateralAmount);

            // Borrow from new module
            box.borrow(fundingModule2, facilityData2, loanToken, loanAmount);
        } else {
            revert("Invalid operation");
        }
    }

    function leverage(
        IBox box,
        IFunding fundingModule,
        bytes calldata facilityData,
        ISwapper swapper,
        bytes calldata swapData,
        IERC20 collateralToken,
        IERC20 loanToken,
        uint256 loanAmount
    ) external {
        require(box.isAllocator(msg.sender), ErrorsLib.OnlyAllocators());
        _box = address(box);

        bytes4 operation = FlashLoanAave.leverage.selector;
        bytes memory params = abi.encode(
            operation,
            address(box),
            fundingModule,
            facilityData,
            collateralToken,
            loanToken,
            loanAmount,
            swapper,
            swapData
        );

        address[] memory assets = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        uint256[] memory modes = new uint256[](1);

        assets[0] = address(loanToken);
        amounts[0] = loanAmount;
        modes[0] = 0; // 0 = no open debt, flash loan must be paid back

        POOL.flashLoan(address(this), assets, amounts, modes, address(this), params, 0);
        _box = address(0);
    }

    function deleverage(
        IBox box,
        IFunding fundingModule,
        bytes calldata facilityData,
        ISwapper swapper,
        bytes calldata swapData,
        IERC20 collateralToken,
        uint256 collateralAmount,
        IERC20 loanToken,
        uint256 loanAmount
    ) external {
        require(box.isAllocator(msg.sender), ErrorsLib.OnlyAllocators());
        _box = address(box);

        if (loanAmount == type(uint256).max) {
            loanAmount = fundingModule.debtBalance(loanToken);
        }

        bytes4 operation = FlashLoanAave.deleverage.selector;
        bytes memory params = abi.encode(
            operation,
            address(box),
            fundingModule,
            facilityData,
            collateralToken,
            collateralAmount,
            loanToken,
            loanAmount,
            swapper,
            swapData
        );

        address[] memory assets = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        uint256[] memory modes = new uint256[](1);

        assets[0] = address(loanToken);
        amounts[0] = loanAmount;
        modes[0] = 0;

        POOL.flashLoan(address(this), assets, amounts, modes, address(this), params, 0);
        _box = address(0);
    }

    function refinance(
        IBox box,
        IFunding fromFundingModule,
        bytes calldata fromFacilityData,
        IFunding toFundingModule,
        bytes calldata toFacilityData,
        IERC20 collateralToken,
        uint256 collateralAmount,
        IERC20 loanToken,
        uint256 loanAmount
    ) external {
        require(box.isAllocator(msg.sender), ErrorsLib.OnlyAllocators());
        _box = address(box);

        if (loanAmount == type(uint256).max) {
            loanAmount = fromFundingModule.debtBalance(loanToken);
        }
        if (collateralAmount == type(uint256).max) {
            collateralAmount = fromFundingModule.collateralBalance(collateralToken);
        }

        bytes4 operation = FlashLoanAave.refinance.selector;
        bytes memory params = abi.encode(
            operation,
            address(box),
            fromFundingModule,
            fromFacilityData,
            toFundingModule,
            toFacilityData,
            collateralToken,
            collateralAmount,
            loanToken,
            loanAmount
        );

        address[] memory assets = new address[](1);
        uint256[] memory amounts = new uint256[](1);
        uint256[] memory modes = new uint256[](1);

        assets[0] = address(loanToken);
        amounts[0] = loanAmount;
        modes[0] = 0;

        POOL.flashLoan(address(this), assets, amounts, modes, address(this), params, 0);
        _box = address(0);
    }
}
