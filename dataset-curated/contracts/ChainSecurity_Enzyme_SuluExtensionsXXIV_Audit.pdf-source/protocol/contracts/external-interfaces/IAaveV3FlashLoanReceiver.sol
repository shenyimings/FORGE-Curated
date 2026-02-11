// SPDX-License-Identifier: GPL-3.0

/*
    This file is part of the Enzyme Protocol.

    (c) Enzyme Foundation <security@enzyme.finance>

    For the full license information, please view the LICENSE
    file that was distributed with this source code.
*/

pragma solidity >=0.6.0 <0.9.0;

/// @title IAaveV3FlashLoanReceiver interface
/// @author Enzyme Foundation <security@enzyme.finance>
interface IAaveV3FlashLoanReceiver {
    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external returns (bool success_);

    function ADDRESSES_PROVIDER() external view returns (address poolAddressProviderAddress_);

    function POOL() external view returns (address poolAddress_);
}
