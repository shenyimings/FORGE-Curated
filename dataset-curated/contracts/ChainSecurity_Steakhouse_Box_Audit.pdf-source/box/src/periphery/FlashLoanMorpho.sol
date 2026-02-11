// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2025 Steakhouse Financial
pragma solidity ^0.8.28;

import {IMorpho} from "@morpho-blue/interfaces/IMorpho.sol";
import {MathLib} from "@morpho-blue/libraries/MathLib.sol";
import {MorphoLib} from "@morpho-blue/libraries/periphery/MorphoLib.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IBox} from "../interfaces/IBox.sol";
import {IFunding} from "../interfaces/IFunding.sol";
import {ISwapper} from "../interfaces/ISwapper.sol";
import {ErrorsLib} from "../libraries/ErrorsLib.sol";

interface IMorphoFlashLoanCallback {
    /// @notice Callback called when a flash loan occurs.
    /// @dev The callback is called only if data is not empty.
    /// @param assets The amount of assets that was flash loaned.
    /// @param data Arbitrary data passed to the `flashLoan` function.
    function onMorphoFlashLoan(uint256 assets, bytes calldata data) external;
}

interface IBoxFlashCallback {
    function onBoxFlash(IERC20 token, uint256 amount, bytes calldata data) external;
}

contract FlashLoanMorpho is IMorphoFlashLoanCallback, IBoxFlashCallback {
    using SafeERC20 for IERC20;
    using MorphoLib for IMorpho;
    using MathLib for uint256;

    IMorpho public immutable MORPHO;
    address internal _box = address(0);

    constructor(address morpho) {
        MORPHO = IMorpho(morpho);
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

    function onMorphoFlashLoan(uint256 assets, bytes calldata data) external {
        require(msg.sender == address(MORPHO), ErrorsLib.OnlyMorpho());

        bytes4 operation = abi.decode(bytes(data), (bytes4));

        IBox box;
        IERC20 loanToken;

        if (operation == FlashLoanMorpho.leverage.selector) {
            (operation, box, , , , loanToken, , , ) = abi.decode(
                data,
                (bytes4, IBox, IFunding, bytes, IERC20, IERC20, uint256, ISwapper, bytes)
            );
        } else if (operation == FlashLoanMorpho.deleverage.selector) {
            (operation, box, , , , , loanToken, , , ) = abi.decode(
                data,
                (bytes4, IBox, IFunding, bytes, IERC20, uint256, IERC20, uint256, ISwapper, bytes)
            );
        } else if (operation == FlashLoanMorpho.refinance.selector) {
            (operation, box, , , , , , , loanToken, ) = abi.decode(
                data,
                (bytes4, IBox, IFunding, bytes, IFunding, bytes, IERC20, uint256, IERC20, uint256)
            );
        } else {
            revert("Invalid operation");
        }

        // Approve the box to pull the flash loan amount
        loanToken.forceApprove(address(box), assets);

        // Call box.flash which will call back to us
        box.flash(loanToken, assets, data);

        // Repay the flash loan to Morpho
        loanToken.forceApprove(msg.sender, assets);
    }

    function onBoxFlash(IERC20, uint256, bytes calldata data) external {
        require(msg.sender == _box, ErrorsLib.OnlyBox());
        bytes4 operation = abi.decode(bytes(data), (bytes4));

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

        if (operation == FlashLoanMorpho.leverage.selector) {
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
            box.borrow(fundingModule, facilityData, loanToken, loanAmount);

            // The borrowed tokens are now in the Box and will be transferred back by box.flash()
        } else if (operation == FlashLoanMorpho.deleverage.selector) {
            (operation, , fundingModule, facilityData, collateralToken, collateralAmount, loanToken, loanAmount, swapper, swapData) = abi
                .decode(data, (bytes4, IBox, IFunding, bytes, IERC20, uint256, IERC20, uint256, ISwapper, bytes));

            // Deleverage: repay debt, withdraw collateral, swap collateral to loan tokens
            if (loanAmount == type(uint256).max) {
                loanAmount = fundingModule.debtBalance(facilityData, loanToken);
            }

            // The Box already has the flash loan tokens, use them to repay debt
            box.repay(fundingModule, facilityData, loanToken, loanAmount);

            // Withdraw collateral (goes to the Box)
            box.depledge(fundingModule, facilityData, collateralToken, collateralAmount);

            // Have the Box swap its collateral tokens to loan tokens
            _swap(box, swapper, swapData, collateralToken, loanToken, collateralAmount);
        } else if (operation == FlashLoanMorpho.refinance.selector) {
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
                loanAmount = fundingModule.debtBalance(facilityData, loanToken);
            }
            if (collateralAmount == type(uint256).max) {
                collateralAmount = fundingModule.collateralBalance(facilityData, collateralToken);
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

        bytes4 operation = FlashLoanMorpho.leverage.selector;
        bytes memory data = abi.encode(
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

        MORPHO.flashLoan(address(loanToken), loanAmount, data);

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
            loanAmount = fundingModule.debtBalance(facilityData, loanToken);
        }

        bytes4 operation = FlashLoanMorpho.deleverage.selector;
        bytes memory data = abi.encode(
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

        MORPHO.flashLoan(address(loanToken), loanAmount, data);
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
            loanAmount = fromFundingModule.debtBalance(fromFacilityData, loanToken);
        }
        if (collateralAmount == type(uint256).max) {
            collateralAmount = fromFundingModule.collateralBalance(fromFacilityData, collateralToken);
        }

        bytes4 operation = FlashLoanMorpho.refinance.selector;
        bytes memory data = abi.encode(
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

        MORPHO.flashLoan(address(loanToken), loanAmount, data);
        _box = address(0);
    }
}
