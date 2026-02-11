// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

contract MockGateway {
    mapping(bytes32 => address) tokens;

    function validateContractCall(bytes32, string calldata, string calldata, bytes32) external pure returns (bool) {
        return true;
    }

    function validateContractCallAndMint(bytes32, string calldata, string calldata, bytes32, string calldata, uint256)
        external
        pure
        returns (bool)
    {
        return true;
    }

    function tokenAddresses(string memory symbol) external view returns (address) {
        bytes32 symbolHash = keccak256(abi.encodePacked(symbol));
        return tokens[symbolHash];
    }

    function saveTokenAddress(string memory symbol, address tokenAddress) external {
        bytes32 symbolHash = keccak256(abi.encodePacked(symbol));
        tokens[symbolHash] = tokenAddress;
    }
}
