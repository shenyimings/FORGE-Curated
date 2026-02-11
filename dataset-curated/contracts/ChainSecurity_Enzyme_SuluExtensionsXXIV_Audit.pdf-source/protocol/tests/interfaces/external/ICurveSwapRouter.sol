// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.6.0 <0.9.0;

interface ICurveSwapRouter {
    function get_best_rate(address _outgoingAssetAddress, address _incomingAssetAddress, uint256 _outgoingAssetAmount)
        external
        view
        returns (address bestPoolAddress_, uint256 amountReceived_);
}
