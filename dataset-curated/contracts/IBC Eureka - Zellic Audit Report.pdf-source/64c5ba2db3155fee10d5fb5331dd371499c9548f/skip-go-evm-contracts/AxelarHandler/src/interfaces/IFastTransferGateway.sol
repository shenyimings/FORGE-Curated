// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

interface IFastTransferGateway {
    function submitOrder(
        bytes32 sender,
        bytes32 recipient,
        uint256 amountIn,
        uint256 amountOut,
        uint32 destinationDomain,
        uint64 timeoutTimestamp,
        bytes calldata data
    ) external returns (bytes32);

    function token() external view returns (address);
}
