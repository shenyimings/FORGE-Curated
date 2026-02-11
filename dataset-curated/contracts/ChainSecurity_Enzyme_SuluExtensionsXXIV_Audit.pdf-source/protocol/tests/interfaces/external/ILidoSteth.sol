// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.6.0 <0.9.0;

interface ILidoSteth {
    function getPooledEthByShares(uint256 _sharesAmount) external view returns (uint256 ethAmount_);

    function submit(address _referral) external payable;
}
