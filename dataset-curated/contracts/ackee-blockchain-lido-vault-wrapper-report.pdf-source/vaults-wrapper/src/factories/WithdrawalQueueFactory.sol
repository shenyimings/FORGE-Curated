// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {WithdrawalQueue} from "src/WithdrawalQueue.sol";

contract WithdrawalQueueFactory {
    function deploy(
        address _pool,
        address _dashboard,
        address _vaultHub,
        address _steth,
        address _vault,
        address _lazyOracle,
        uint256 _minWithdrawalDelayTime,
        bool _isRebalancingSupported
    ) external returns (address impl) {
        impl = address(
            new WithdrawalQueue(
                _pool,
                _dashboard,
                _vaultHub,
                _steth,
                _vault,
                _lazyOracle,
                _minWithdrawalDelayTime,
                _isRebalancingSupported
            )
        );
    }
}
