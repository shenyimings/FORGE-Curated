// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import "../interfaces/IPendle.sol";
import "../utils/Constants.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../utils/TokenUtils.sol";

struct PendleDepositData {
    uint256 minPtOut;
    IPRouter.ApproxParams approxParams;
    IPRouter.LimitOrderData limitOrderData;
}

/// @dev Generic Pendle PT library for interacting with the Pendle router, reduces bytecode size
library PendlePTLib {
    using SafeERC20 for ERC20;
    using TokenUtils for ERC20;

    function swapExactTokenForPt(
        address tokenInSy,
        address market,
        uint256 tokenInAmount,
        bytes calldata pendleData
    ) external {
        ERC20(tokenInSy).checkApprove(address(PENDLE_ROUTER), tokenInAmount);
        uint256 msgValue = tokenInSy == ETH_ADDRESS ? tokenInAmount : 0;
        PendleDepositData memory data = abi.decode(pendleData, (PendleDepositData));

        IPRouter.TokenInput memory tokenInput;
        tokenInput.tokenIn = tokenInSy;
        tokenInput.netTokenIn = tokenInAmount;
        tokenInput.tokenMintSy = tokenInSy;
        // When tokenIn == tokenMintSy then the swap router can be set to
        // empty data. This means that the vault must hold the underlying sy
        // token when we begin the execution.

        PENDLE_ROUTER.swapExactTokenForPt{value: msgValue}(
            address(this),
            address(market),
            data.minPtOut,
            data.approxParams,
            tokenInput,
            data.limitOrderData
        );
    }

    function swapExactPtForToken(
        address pt,
        address market,
        address tokenOutSy,
        uint256 netPtIn,
        bytes calldata data
    ) external returns (uint256 netTokenOut) {
        ERC20(pt).checkApprove(address(PENDLE_ROUTER), netPtIn);

        IPRouter.TokenOutput memory tokenOutput;
        tokenOutput.tokenOut = tokenOutSy;
        tokenOutput.tokenRedeemSy = tokenOutSy;
        // We check the min token out later
        // tokenInput.minTokenOut = 0;
        IPRouter.LimitOrderData memory limitOrderData;
        if (data.length > 0) {
            limitOrderData = abi.decode(data, (IPRouter.LimitOrderData));
        }

        (netTokenOut, , ) = PENDLE_ROUTER.swapExactPtForToken(
            address(this),
            address(market),
            netPtIn,
            tokenOutput,
            limitOrderData
        );
    }

    function redeemExpiredPT(
        IPPrincipalToken pt,
        IPYieldToken yt,
        IStandardizedYield sy,
        address tokenOutSy,
        uint256 netPtIn
    ) external returns (uint256 netTokenOut) {
        // PT Tokens are known to be ERC20 compliant
        pt.transfer(address(yt), netPtIn);
        uint256 netSyOut = yt.redeemPY(address(sy));
        netTokenOut = sy.redeem(address(this), netSyOut, tokenOutSy, 0, true);
    }
}