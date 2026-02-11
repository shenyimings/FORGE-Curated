// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

interface ICurveStableSwapNG {
    function add_liquidity(
        uint256[] calldata _amounts,
        uint256 _minMintAmount,
        address _receiver
    ) external returns (uint256);

    function calc_token_amount(
        uint256[] calldata _amounts,
        bool _isDeposit
    ) external view returns (uint256);
}
