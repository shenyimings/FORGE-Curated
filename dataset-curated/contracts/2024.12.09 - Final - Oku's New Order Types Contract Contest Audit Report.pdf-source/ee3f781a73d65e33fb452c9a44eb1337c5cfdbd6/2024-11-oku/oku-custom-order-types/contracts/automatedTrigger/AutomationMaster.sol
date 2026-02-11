// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./IAutomation.sol";
import "../libraries/ArrayMutation.sol";
import "../interfaces/openzeppelin/Ownable.sol";
import "../interfaces/openzeppelin/ERC20.sol";
import "../interfaces/openzeppelin/IERC20.sol";
import "../interfaces/openzeppelin/SafeERC20.sol";
import "../oracle/IPythRelay.sol";

///@notice This contract owns and handles all of the settings and accounting logic for automated swaps
///@notice This contract should not hold any user funds, only collected fees
contract AutomationMaster is IAutomationMaster, Ownable {
    using SafeERC20 for IERC20;

    ///@notice maximum pending orders that may exist at a time, limiting the compute requriement for checkUpkeep
    uint16 public maxPendingOrders;

    ///@notice minumum USD value required to create a new order, in 1e8 terms
    uint256 public minOrderSize;

    ///sub keeper contracts
    IStopLimit public STOP_LIMIT_CONTRACT;
    IBracket public BRACKET_CONTRACT;

    ///each token must have a registered oracle in order to be tradable
    mapping(IERC20 => IPythRelay) public oracles;
    mapping(IERC20 => bytes32) public pythIds;

    ///@notice register Stop Limit and Bracket order contracts
    function registerSubKeepers(
        IStopLimit stopLimitContract,
        IBracket bracketContract
    ) external onlyOwner {
        STOP_LIMIT_CONTRACT = stopLimitContract;
        BRACKET_CONTRACT = bracketContract;
    }

    ///@notice Registered Oracles are expected to return the USD price in 1e8 terms
    function registerOracle(
        IERC20[] calldata _tokens,
        IPythRelay[] calldata _oracles
    ) external onlyOwner {
        require(_tokens.length == _oracles.length, "Array Length Mismatch");
        for (uint i = 0; i < _tokens.length; i++) {
            oracles[_tokens[i]] = _oracles[i];
        }
    }

    ///@notice set max pending orders, limiting checkUpkeep compute requirement
    function setMaxPendingOrders(uint16 _max) external onlyOwner {
        maxPendingOrders = _max;
    }

    ///@param usdValue must be in 1e8 terms
    function setMinOrderSize(uint256 usdValue) external onlyOwner {
        minOrderSize = usdValue;
    }

    ///@notice sweep the entire balance of @param token to the owner
    ///@notice this contract should not hold funds other than collected fees,
    ///which are forwarded here after each transaction
    function sweep(IERC20 token) external onlyOwner {
        token.safeTransfer(owner(), token.balanceOf(address(this)));
    }

    ///@notice Registered Oracles are expected to return the USD price in 1e8 terms
    ///@return exchangeRate should always be in 1e8 terms
    function getExchangeRate(
        IERC20 tokenIn,
        IERC20 tokenOut
    ) external view override returns (uint256 exchangeRate) {
        return _getExchangeRate(tokenIn, tokenOut);
    }

    function _getExchangeRate(
        IERC20 tokenIn,
        IERC20 tokenOut
    ) internal view returns (uint256 exchangeRate) {
        // Retrieve USD prices from oracles, scaled to 1e8
        uint256 priceIn = oracles[tokenIn].currentValue();
        uint256 priceOut = oracles[tokenOut].currentValue();

        // Return the exchange rate in 1e8 terms
        return (priceIn * 1e8) / priceOut;
    }

    ///@notice generate a random and unique order id
    function generateOrderId(address sender) external view override returns (uint96) {
        uint256 hashedValue = uint256(
            keccak256(abi.encodePacked(sender, block.timestamp))
        );
        return uint96(hashedValue);
    }

    ///@notice compute minumum amount received
    ///@return minAmountReceived is in @param tokenOut terms
    ///@param slippageBips is in raw basis points
    function getMinAmountReceived(
        uint256 amountIn,
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint96 slippageBips
    ) external view override returns (uint256 minAmountReceived) {
        uint256 exchangeRate = _getExchangeRate(tokenIn, tokenOut);

        // Adjust for decimal differences between tokens
        uint256 adjustedAmountIn = adjustForDecimals(
            amountIn,
            tokenIn,
            tokenOut
        );

        // Calculate the fair amount out without slippage
        uint256 fairAmountOut = (adjustedAmountIn * exchangeRate) / 1e8;

        // Apply slippage - 10000 bips is equivilant to 100% slippage
        return (fairAmountOut * (10000 - slippageBips)) / 10000;
    }

    ///@notice account for token scale when computing token amounts based on slippage bips
    function adjustForDecimals(
        uint256 amountIn,
        IERC20 tokenIn,
        IERC20 tokenOut
    ) internal view returns (uint256 adjustedAmountIn) {
        uint8 decimalIn = ERC20(address(tokenIn)).decimals();
        uint8 decimalOut = ERC20(address(tokenOut)).decimals();

        if (decimalIn > decimalOut) {
            // Reduce amountIn to match the lower decimals of tokenOut
            return amountIn / (10 ** (decimalIn - decimalOut));
        } else if (decimalIn < decimalOut) {
            // Increase amountIn to match the higher decimals of tokenOut
            return amountIn * (10 ** (decimalOut - decimalIn));
        }
        // If decimals are the same, no adjustment needed
        return amountIn;
    }

    ///@notice determine if a new order meets the minimum order size requirement
    ///Value of @param amountIn of @param tokenIn must meed the minimum USD value
    function checkMinOrderSize(IERC20 tokenIn, uint256 amountIn) external view override {
        uint256 currentPrice = oracles[tokenIn].currentValue();
        uint256 usdValue = (currentPrice * amountIn) /
            (10 ** ERC20(address(tokenIn)).decimals());

        require(usdValue > minOrderSize, "order too small");
    }

    ///@notice check upkeep on all order types
    function checkUpkeep(
        bytes calldata
    )
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        //check stop limit order
        (upkeepNeeded, performData) = STOP_LIMIT_CONTRACT.checkUpkeep("0x");
        if (upkeepNeeded) {
            return (true, performData);
        }

        //check bracket order
        (upkeepNeeded, performData) = BRACKET_CONTRACT.checkUpkeep("0x");
        if (upkeepNeeded) {
            return (true, performData);
        }
    }

    ///@notice perform upkeep on any order type
    function performUpkeep(bytes calldata performData) external override {
        //decode into masterUpkeepData
        MasterUpkeepData memory data = abi.decode(
            performData,
            (MasterUpkeepData)
        );

        //if stop order, we directly pass the upkeep data to the stop order contract
        if (data.orderType == OrderType.STOP_LIMIT) {
            STOP_LIMIT_CONTRACT.performUpkeep(performData);
        }

        //if stop order, we directly pass the upkeep data to the stop order contract
        if (data.orderType == OrderType.BRACKET) {
            BRACKET_CONTRACT.performUpkeep(performData);
        }
    }
}
