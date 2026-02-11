// SPDX-License-Identifier: MIT

pragma solidity 0.8.24;

interface IAADistributorPaymaster {
    event MaxPaidTransactionsPerAccountUpdated(uint256 oldMax, uint256 newMax);

    event MaxSponsoredEthUpdated(uint256 oldMax, uint256 newMax);
}
