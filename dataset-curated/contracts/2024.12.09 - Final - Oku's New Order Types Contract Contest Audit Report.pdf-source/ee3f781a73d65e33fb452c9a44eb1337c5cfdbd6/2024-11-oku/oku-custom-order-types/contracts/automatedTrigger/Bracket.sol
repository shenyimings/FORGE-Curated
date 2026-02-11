// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./IAutomation.sol";
import "../libraries/ArrayMutation.sol";
import "../interfaces/uniswapV3/UniswapV3Pool.sol";
import "../interfaces/uniswapV3/IPermit2.sol";
import "../interfaces/uniswapV3/ISwapRouter02.sol";
import "../interfaces/openzeppelin/Ownable.sol";
import "../interfaces/openzeppelin/IERC20.sol";
import "../interfaces/openzeppelin/SafeERC20.sol";
import "../interfaces/openzeppelin/ReentrancyGuard.sol";

///@notice This contract owns and handles all logic associated with the following order types:
/// BRACKET_ORDER - automated fill at a fixed takeProfit price OR stop price, with independant slippapge for each option
/// LIMIT_ORDER - BRACKET_ORDER at specified take profit price, with STOP set to 0
/// STOP_ORDER - BRACKET_ORDER at specified stop price, with take profit set to 2 ** 256 - 1
/// In order to configure a LIMIT_ORDER or STOP_ORDER, simply set the take profit or stop price to either 0 for the lower bound or 2^256 - 1 for the upper bound
contract Bracket is Ownable, IBracket, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IAutomationMaster public immutable MASTER;
    IPermit2 public immutable permit2;

    uint96[] public pendingOrderIds;

    mapping(uint96 => Order) public orders;

    constructor(IAutomationMaster _master, IPermit2 _permit2) {
        MASTER = _master;
        permit2 = _permit2;
    }

    function getPendingOrders() external view returns (uint96[] memory) {
        return pendingOrderIds;
    }

    //check upkeep
    function checkUpkeep(
        bytes calldata
    )
        external
        view
        override
        returns (bool upkeepNeeded, bytes memory performData)
    {
        for (uint96 i = 0; i < pendingOrderIds.length; i++) {
            Order memory order = orders[pendingOrderIds[i]];
            (
                bool inRange,
                bool takeProfit,
                uint256 exchangeRate
            ) = checkInRange(order);
            if (inRange) {
                return (
                    true,
                    abi.encode(
                        MasterUpkeepData({
                            orderType: OrderType.BRACKET,
                            target: address(this),
                            txData: "0x",
                            pendingOrderIdx: i,
                            orderId: order.orderId,
                            tokenIn: order.tokenIn,
                            tokenOut: order.tokenOut,
                            slippage: takeProfit
                                ? order.takeProfitSlippage
                                : order.stopSlippage, //bips based on take profit or stop fill
                            amountIn: order.amountIn,
                            exchangeRate: exchangeRate
                        })
                    )
                );
            }
        }
    }

    ///@notice recipient of swap should be this contract,
    ///as we need to account for tokens received.
    ///This contract will then forward the tokens to the user
    /// target refers to some contract where when we send @param performData,
    ///that contract will exchange our tokenIn for tokenOut with at least minAmountReceived
    /// pendingOrderIdx is the index of the pending order we are executing,
    ///this pending order is removed from the array via array mutation
    function performUpkeep(
        bytes calldata performData
    ) external override nonReentrant {
        MasterUpkeepData memory data = abi.decode(
            performData,
            (MasterUpkeepData)
        );
        Order memory order = orders[pendingOrderIds[data.pendingOrderIdx]];

        require(
            order.orderId == pendingOrderIds[data.pendingOrderIdx],
            "Order Fill Mismatch"
        );

        //deduce if we are filling stop or take profit
        (bool inRange, bool takeProfit, ) = checkInRange(order);
        require(inRange, "order ! in range");

        //deduce bips
        uint16 bips;
        takeProfit ? bips = order.takeProfitSlippage : bips = order
            .stopSlippage;

        (uint256 swapAmountOut, uint256 tokenInRefund) = execute(
            data.target,
            data.txData,
            order.amountIn,
            order.tokenIn,
            order.tokenOut,
            bips
        );

        //handle accounting
        //remove from pending array
        pendingOrderIds = ArrayMutation.removeFromArray(
            data.pendingOrderIdx,
            pendingOrderIds
        );

        //handle fee
        (uint256 feeAmount, uint256 adjustedAmount) = applyFee(
            swapAmountOut,
            order.feeBips
        );

        if (feeAmount != 0) {
            order.tokenOut.safeTransfer(address(MASTER), feeAmount);
        }

        //send tokenOut to recipient
        order.tokenOut.safeTransfer(order.recipient, adjustedAmount);

        //refund any unspent tokenIn
        //this should generally be 0 when using exact input for swaps, which is recommended
        if (tokenInRefund != 0) {
            order.tokenIn.safeTransfer(order.recipient, tokenInRefund);
        }

        //emit
        emit OrderProcessed(order.orderId);
    }

    function fillStopLimitOrder(
        bytes calldata swapPayload,
        uint256 takeProfit,
        uint256 stopPrice,
        uint256 amountIn,
        uint96 existingOrderId,
        IERC20 tokenIn,
        IERC20 tokenOut,
        address recipient,
        uint16 existingFeeBips,
        uint16 takeProfitSlippage,
        uint16 stopSlippage,
        bool permit,
        bytes calldata permitPayload
    ) external override nonReentrant {
        require(
            msg.sender == address(MASTER.STOP_LIMIT_CONTRACT()),
            "Only Stop Limit"
        );
        _initializeOrder(
            swapPayload,
            takeProfit,
            stopPrice,
            amountIn,
            existingOrderId,
            tokenIn,
            tokenOut,
            recipient,
            existingFeeBips,
            takeProfitSlippage,
            stopSlippage,
            permit,
            permitPayload
        );
    }

    ///@notice see @IBracket
    function createOrder(
        bytes calldata swapPayload,
        uint256 takeProfit,
        uint256 stopPrice,
        uint256 amountIn,
        IERC20 tokenIn,
        IERC20 tokenOut,
        address recipient,
        uint16 feeBips,
        uint16 takeProfitSlippage,
        uint16 stopSlippage,
        bool permit,
        bytes calldata permitPayload
    ) external override nonReentrant {
        _initializeOrder(
            swapPayload,
            takeProfit,
            stopPrice,
            amountIn,
            0, //no existing order id
            tokenIn,
            tokenOut,
            recipient,
            feeBips,
            takeProfitSlippage,
            stopSlippage,
            permit,
            permitPayload
        );
    }

    ///@notice see @IBracket
    function modifyOrder(
        uint96 orderId,
        uint256 _takeProfit,
        uint256 _stopPrice,
        uint256 amountInDelta,
        IERC20 _tokenOut,
        address _recipient,
        uint16 _takeProfitSlippage,
        uint16 _stopSlippage,
        bool permit,
        bool increasePosition,
        bytes calldata permitPayload
    ) external override nonReentrant {
        //get order
        Order memory order = orders[orderId];

        //only order owner
        require(msg.sender == order.recipient, "only order owner");

        //deduce any amountIn changes
        uint256 newAmountIn = order.amountIn;
        if (amountInDelta != 0) {
            if (increasePosition) {
                newAmountIn += amountInDelta;
                //take funds via permit2
                if (permit) {
                    handlePermit(
                        order.recipient,
                        permitPayload,
                        uint160(amountInDelta),
                        address(order.tokenIn)
                    );
                } else {
                    //legacy transfer, assume prior approval
                    order.tokenIn.safeTransferFrom(
                        order.recipient,
                        address(this),
                        amountInDelta
                    );
                }
            } else {
                //ensure delta is valid
                require(amountInDelta < order.amountIn, "invalid delta");

                //set new amountIn for accounting
                newAmountIn -= amountInDelta;

                //check min order size for new amount
                MASTER.checkMinOrderSize(order.tokenIn, newAmountIn);

                //refund position partially
                order.tokenIn.safeTransfer(order.recipient, amountInDelta);
            }
        }

        //check for oracles
        if (_tokenOut != order.tokenOut) {
            require(
                address(MASTER.oracles(_tokenOut)) != address(0x0),
                "Oracle !exist"
            );
        }

        //construct new order
        Order memory newOrder = Order({
            orderId: orderId,
            takeProfit: _takeProfit,
            stopPrice: _stopPrice,
            amountIn: newAmountIn,
            tokenIn: order.tokenIn,
            tokenOut: _tokenOut,
            feeBips: order.feeBips,
            takeProfitSlippage: _takeProfitSlippage,
            stopSlippage: _stopSlippage,
            recipient: _recipient,
            direction: MASTER.getExchangeRate(order.tokenIn, _tokenOut) >
                _takeProfit
        });

        //store new order
        orders[orderId] = newOrder;
    }

    ///@notice allow administrator to cancel any order
    ///@notice once cancelled, any funds assocaiated with the order are returned to the order recipient
    ///@notice only pending orders can be cancelled
    function adminCancelOrder(uint96 orderId) external onlyOwner {
        Order memory order = orders[orderId];
        require(_cancelOrder(order), "Order not active");
    }

    ///@notice only the order recipient can cancel their order
    ///@notice only pending orders can be cancelled
    function cancelOrder(uint96 orderId) external {
        Order memory order = orders[orderId];
        require(msg.sender == order.recipient, "Only Order Owner");
        require(_cancelOrder(order), "Order not active");
    }

    function procureTokens(
        IERC20 token,
        uint256 amount,
        address owner,
        bool permit,
        bytes calldata permitPayload
    ) internal {
        if (permit) {
            IAutomation.Permit2Payload memory payload = abi.decode(
                permitPayload,
                (IAutomation.Permit2Payload)
            );

            permit2.permit(owner, payload.permitSingle, payload.signature);
            permit2.transferFrom(
                owner,
                address(this),
                uint160(amount),
                address(token)
            );
        } else {
            token.safeTransferFrom(owner, address(this), amount);
        }
    }

    function _initializeOrder(
        bytes calldata swapPayload,
        uint256 takeProfit,
        uint256 stopPrice,
        uint256 amountIn,
        uint96 existingOrderId,
        IERC20 tokenIn,
        IERC20 tokenOut,
        address recipient,
        uint16 feeBips,
        uint16 takeProfitSlippage,
        uint16 stopSlippage,
        bool permit,
        bytes calldata permitPayload
    ) internal {
        //determine if we are doing a swap first
        if (swapPayload.length != 0) {
            SwapParams memory swapParams = abi.decode(
                swapPayload,
                (SwapParams)
            );
            //procure swap token in
            procureTokens(
                swapParams.swapTokenIn,
                swapParams.swapAmountIn,
                msg.sender,
                permit,
                permitPayload
            );

            _createOrderWithSwap(
                swapParams,
                takeProfit,
                stopPrice,
                existingOrderId,
                tokenIn,
                tokenOut,
                recipient,
                feeBips,
                takeProfitSlippage,
                stopSlippage
            );
        } else {
            //no swap
            procureTokens(tokenIn, amountIn, msg.sender, permit, permitPayload);

            _createOrder(
                takeProfit,
                stopPrice,
                amountIn,
                existingOrderId,
                tokenIn,
                tokenOut,
                recipient,
                feeBips,
                takeProfitSlippage,
                stopSlippage
            );
        }
    }

    function _createOrderWithSwap(
        SwapParams memory swapParams,
        uint256 takeProfit,
        uint256 stopPrice,
        uint96 existingOrderId,
        IERC20 tokenIn,
        IERC20 tokenOut,
        address recipient,
        uint16 feeBips,
        uint16 takeProfitSlippage,
        uint16 stopSlippage
    ) internal {
        require(swapParams.swapSlippage <= 10000, "BIPS > 10k");

        //execute the swap
        (uint256 swapAmountOut, uint256 tokenInRefund) = execute(
            swapParams.swapTarget,
            swapParams.txData,
            swapParams.swapAmountIn,
            swapParams.swapTokenIn,
            tokenIn,
            swapParams.swapSlippage
        );

        _createOrder(
            takeProfit,
            stopPrice,
            swapAmountOut,
            existingOrderId,
            tokenIn,
            tokenOut,
            recipient,
            feeBips,
            takeProfitSlippage,
            stopSlippage
        );
        //refund any unspent tokenIn
        //this should generally be 0 when using exact input for swaps, which is recommended
        if (tokenInRefund != 0) {
            swapParams.swapTokenIn.safeTransfer(recipient, tokenInRefund);
        }
    }

    function _createOrder(
        uint256 takeProfit,
        uint256 stopPrice,
        uint256 amountIn,
        uint96 existingOrderId,
        IERC20 tokenIn,
        IERC20 tokenOut,
        address recipient,
        uint16 feeBips,
        uint16 takeProfitSlippage,
        uint16 stopSlippage
    ) internal {
        //verify both oracles exist, as we need both to calc the exchange rate
        require(
            address(MASTER.oracles(tokenIn)) != address(0x0) &&
                address(MASTER.oracles(tokenIn)) != address(0x0),
            "Oracle !exist"
        );
        require(
            pendingOrderIds.length < MASTER.maxPendingOrders(),
            "Max Order Count Reached"
        );
        require(
            stopSlippage <= 10000 &&
                takeProfitSlippage <= 10000 &&
                feeBips <= 10000,
            "BIPS > 10k"
        );

        MASTER.checkMinOrderSize(tokenIn, amountIn);

        //generate random but unique order id if there is not an existing orderId from a stop limit order
        if (existingOrderId == 0) {
            existingOrderId = MASTER.generateOrderId(msg.sender);
        }

        //construct order
        orders[existingOrderId] = Order({
            orderId: existingOrderId,
            takeProfit: takeProfit,
            stopPrice: stopPrice,
            amountIn: amountIn,
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            recipient: recipient,
            takeProfitSlippage: takeProfitSlippage,
            feeBips: feeBips,
            stopSlippage: stopSlippage,
            direction: MASTER.getExchangeRate(tokenIn, tokenOut) > takeProfit //exchangeRate in/out > takeProfit
        });

        //store pending order
        pendingOrderIds.push(existingOrderId);

        emit OrderCreated(existingOrderId);
    }

    function _cancelOrder(Order memory order) internal returns (bool) {
        for (uint96 i = 0; i < pendingOrderIds.length; i++) {
            if (pendingOrderIds[i] == order.orderId) {
                //remove from pending array
                pendingOrderIds = ArrayMutation.removeFromArray(
                    i,
                    pendingOrderIds
                );

                //refund tokenIn amountIn to recipient
                order.tokenIn.safeTransfer(order.recipient, order.amountIn);

                //emit event
                emit OrderCancelled(order.orderId);

                return true;
            }
        }
        return false;
    }

    ///@notice execute swap transaction
    ///@param target is the contract to which we are sending @param txData to perform the swap
    ///@param tokenIn is the token to sell for @param tokenOut
    ///@param bips ensures that we received at least the minimum amount of @param tokenOut after the swap
    function execute(
        address target,
        bytes memory txData,
        uint256 amountIn,
        IERC20 tokenIn,
        IERC20 tokenOut,
        uint16 bips
    ) internal returns (uint256 swapAmountOut, uint256 tokenInRefund) {
        //update accounting
        uint256 initialTokenIn = tokenIn.balanceOf(address(this));
        uint256 initialTokenOut = tokenOut.balanceOf(address(this));

        //approve
        tokenIn.safeApprove(target, amountIn);

        //perform the call
        (bool success, bytes memory result) = target.call(txData);

        if (success) {
            uint256 finalTokenIn = tokenIn.balanceOf(address(this));
            require(finalTokenIn >= initialTokenIn - amountIn, "over spend");
            uint256 finalTokenOut = tokenOut.balanceOf(address(this));

            //if success, we expect tokenIn balance to decrease by amountIn
            //and tokenOut balance to increase by at least minAmountReceived
            require(
                finalTokenOut - initialTokenOut >
                    MASTER.getMinAmountReceived(
                        amountIn,
                        tokenIn,
                        tokenOut,
                        bips
                    ),
                "Too Little Received"
            );

            swapAmountOut = finalTokenOut - initialTokenOut;
            tokenInRefund = amountIn - (initialTokenIn - finalTokenIn);
        } else {
            //force revert
            revert TransactionFailed(result);
        }
    }

    ///@notice handle signature and acquisition of asset with permit2
    function handlePermit(
        address owner,
        bytes calldata permitPayload,
        uint160 amount,
        address token
    ) internal {
        Permit2Payload memory payload = abi.decode(
            permitPayload,
            (Permit2Payload)
        );

        permit2.permit(owner, payload.permitSingle, payload.signature);
        permit2.transferFrom(owner, address(this), amount, token);
    }
    ///@notice determine @param order order is fillable
    ///
    function checkInRange(
        Order memory order
    )
        internal
        view
        returns (bool inRange, bool takeProfit, uint256 exchangeRate)
    {
        exchangeRate = MASTER.getExchangeRate(order.tokenIn, order.tokenOut);
        if (order.direction) {
            //check for take profit price
            if (exchangeRate <= order.takeProfit) {
                return (true, true, exchangeRate);
            }
            //check for stop price
            if (exchangeRate >= order.stopPrice) {
                return (true, false, exchangeRate);
            }
        } else {
            //check for take profit price
            if (exchangeRate >= order.takeProfit) {
                return (true, true, exchangeRate);
            }
            //check for stop price
            if (exchangeRate <= order.stopPrice) {
                return (true, false, exchangeRate);
            }
        }
    }

    ///@notice apply the protocol fee to @param amount
    ///@notice fee is in the form of tokenOut after a successful performUpkeep
    function applyFee(
        uint256 amount,
        uint16 feeBips
    ) internal pure returns (uint256 feeAmount, uint256 adjustedAmount) {
        if (feeBips != 0) {
            //determine adjusted amount and fee amount
            adjustedAmount = (amount * (10000 - feeBips)) / 10000;
            feeAmount = amount - adjustedAmount;
        } else {
            return (0, amount);
        }
    }
}
