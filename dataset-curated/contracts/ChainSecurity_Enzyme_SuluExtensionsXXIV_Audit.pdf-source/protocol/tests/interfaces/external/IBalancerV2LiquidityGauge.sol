// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.6.0 <0.9.0;

interface IBalancerV2LiquidityGauge {
    function lp_token() external view returns (address lpToken_);
}
