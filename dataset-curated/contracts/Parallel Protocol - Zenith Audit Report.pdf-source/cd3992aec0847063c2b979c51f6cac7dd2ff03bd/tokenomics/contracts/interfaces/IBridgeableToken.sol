// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IBridgeableToken {
    function swapLzTokenToPrincipalToken(address _to, uint256 _amount) external;

    function getMaxCreditableAmount() external view returns (uint256);
}
