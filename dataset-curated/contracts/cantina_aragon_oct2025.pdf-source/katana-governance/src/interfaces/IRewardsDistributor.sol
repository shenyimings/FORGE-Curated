// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IRewardsDistributor {
    function claim(
        address[] calldata users,
        address[] calldata tokens,
        uint256[] calldata amounts,
        bytes32[][] calldata proofs
    )
        external;

    function toggleOperator(address user, address operator) external;
}
