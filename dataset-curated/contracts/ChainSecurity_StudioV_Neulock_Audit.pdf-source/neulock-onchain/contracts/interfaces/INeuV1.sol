// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface INeuV1 {
  function safeMint ( address to, uint16 seriesIndex ) external;
  function safeMintPublic ( uint16 seriesIndex ) payable external;
  function setMetadataContract ( address newMetadataContract ) external;
  function increaseSponsorPoints(uint256) external payable returns (uint256, uint256);
  function setWeiPerSponsorPoint(uint256 newWeiPerSponsorPoint) external;
  function withdraw (  ) external;
  function refund ( uint256 ) external;
  function getTokensOfOwner(address owner) external view returns (uint256[] memory tokenIds);
  function getTokensWithData(uint256[] calldata tokenIds) external view returns (string[] memory tokenUris, bool[] memory isUserMinted);
  function getTokensTraitValues(uint256[] calldata tokenIds, bytes32[] calldata traitKeys) external view returns (bytes32[][] memory traitValues);
}

interface INeuTokenV1 is INeuV1, IERC721 {}