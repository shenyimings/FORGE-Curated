// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.28;

interface INeuStorageV1 {
    function saveData(uint256 tokenId, bytes memory data) external payable;
    function retrieveData(address owner) external view returns (bytes memory);
}
