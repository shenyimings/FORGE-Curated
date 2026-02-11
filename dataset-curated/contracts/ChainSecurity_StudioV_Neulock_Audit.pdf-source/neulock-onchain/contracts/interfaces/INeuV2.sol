// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {INeuV1} from "./INeuV1.sol";

interface INeuV2 is INeuV1 {
    event InitializedNeu(uint256 VERSION, address defaultAdmin, address upgrader, address operator);
    event InitializedNeuV2(address neuDaoLockAddress);
    event MetadataContractUpdated(address metadataContract);
    event DaoLockContractUpdated(address daoLockContract);
    event StorageContractUpdated(address storageContract);
    event WeiPerSponsorPointUpdated(uint256 weiPerSponsorPoint);

    function setDaoLockContract(address payable newDaoLockContract) external;
    function isGovernanceToken(uint256 tokenId) external view returns (bool);
}

interface INeuTokenV2 is INeuV2, IERC721 {}