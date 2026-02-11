// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface ITokenURIFetcher {
    function onFetchTokenURIData(uint256 id) external view returns (string memory);
}
