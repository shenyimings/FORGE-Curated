// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

library BondingCurveLib {
    function getSPECAmountForTokens(
        uint256 tokenAmount,
        address token,
        uint256 currentSPECReserve
    ) external view returns (uint256) {
        uint256 currentTokenReserve = IERC20(token).balanceOf(address(this));
        uint256 newTokenReserve = currentTokenReserve + tokenAmount;
        uint256 k = currentSPECReserve * currentTokenReserve;
        uint256 newSPECReserve = k / newTokenReserve;
        uint256 specAmount = currentSPECReserve - newSPECReserve;
        return specAmount;
    }
}
