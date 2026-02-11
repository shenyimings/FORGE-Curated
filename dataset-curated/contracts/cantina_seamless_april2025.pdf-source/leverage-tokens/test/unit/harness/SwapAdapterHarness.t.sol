// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

// Dependency imports
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// Internal imports
import {ISwapAdapter} from "src/interfaces/periphery/ISwapAdapter.sol";
import {SwapAdapter} from "src/periphery/SwapAdapter.sol";

contract SwapAdapterHarness is SwapAdapter {
    function exposed_swapExactInputAerodrome(
        uint256 inputAmount,
        uint256 minOutputAmount,
        ISwapAdapter.SwapContext memory swapContext
    ) external returns (uint256 outputAmount) {
        return _swapExactInputAerodrome(inputAmount, minOutputAmount, swapContext);
    }

    function exposed_swapExactInputAerodromeSlipstream(
        uint256 inputAmount,
        uint256 minOutputAmount,
        ISwapAdapter.SwapContext memory swapContext
    ) external returns (uint256 outputAmount) {
        return _swapExactInputAerodromeSlipstream(inputAmount, minOutputAmount, swapContext);
    }

    function exposed_swapExactInputUniV2(
        uint256 inputAmount,
        uint256 minOutputAmount,
        ISwapAdapter.SwapContext memory swapContext
    ) external returns (uint256 outputAmount) {
        return _swapExactInputUniV2(inputAmount, minOutputAmount, swapContext);
    }

    function exposed_swapExactInputUniV3(
        uint256 inputAmount,
        uint256 minOutputAmount,
        ISwapAdapter.SwapContext memory swapContext
    ) external returns (uint256 outputAmount) {
        return _swapExactInputUniV3(inputAmount, minOutputAmount, swapContext);
    }

    function exposed_swapExactOutputAerodrome(
        uint256 outputAmount,
        uint256 maxInputAmount,
        ISwapAdapter.SwapContext memory swapContext
    ) external returns (uint256 inputAmount) {
        return _swapExactOutputAerodrome(outputAmount, maxInputAmount, swapContext);
    }

    function exposed_swapExactOutputAerodromeSlipstream(
        uint256 outputAmount,
        uint256 maxInputAmount,
        ISwapAdapter.SwapContext memory swapContext
    ) external returns (uint256 inputAmount) {
        return _swapExactOutputAerodromeSlipstream(outputAmount, maxInputAmount, swapContext);
    }

    function exposed_swapExactOutputUniV2(
        uint256 outputAmount,
        uint256 maxInputAmount,
        ISwapAdapter.SwapContext memory swapContext
    ) external returns (uint256 inputAmount) {
        return _swapExactOutputUniV2(outputAmount, maxInputAmount, swapContext);
    }

    function exposed_swapExactOutputUniV3(
        uint256 outputAmount,
        uint256 maxInputAmount,
        ISwapAdapter.SwapContext memory swapContext
    ) external returns (uint256 inputAmount) {
        return _swapExactOutputUniV3(outputAmount, maxInputAmount, swapContext);
    }
}
