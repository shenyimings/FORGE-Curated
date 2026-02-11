// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.28;

interface INeuMetadataV1 {
  function addSeries(bytes8 name, uint64 priceInGwei, uint32 firstToken, uint32 maxTokens, uint16 fgColorRGB565, uint16 bgColorRGB565, uint16 accentColorRGB565, bool makeAvailable) external returns (uint16);
  function createTokenMetadata ( uint16 seriesIndex, uint256 originalPrice ) external returns ( uint256 tokenId, bool governance );
  function deleteTokenMetadata ( uint256 tokenId ) external;
  function getAvailableSeries (  ) external view returns ( uint16[] memory );
  function getRefundAmount ( uint256 tokenId ) external view returns ( uint256 );
  function getSeries ( uint16 seriesIndex ) external view returns ( bytes8 name, uint256 priceInGwei, uint256 firstToken, uint256 maxTokens, uint256 mintedTokens, uint256 burntTokens, bool isAvailable, string memory logoSvg );
  function getSeriesMintingPrice ( uint16 seriesIndex ) external view returns ( uint256 );
  function getTraitMetadataURI (  ) external view returns ( string memory );
  function getTraitValue ( uint256 tokenId, bytes32 traitKey ) external view returns ( bytes32 );
  function getTraitValues ( uint256 tokenId, bytes32[] calldata traitKeys ) external view returns ( bytes32[] memory traitValues );
  function increaseSponsorPoints ( uint256 tokenId, uint256 sponsorPointsIncrease ) external returns ( uint256 );
  function isSeriesAvailable ( uint16 seriesIndex ) external view returns ( bool );
  function isUserMinted(uint256 tokenId) external view returns (bool);
  function setLogoContract(address logoContract) external;
  function setPriceInGwei ( uint16 seriesIndex, uint64 price ) external;
  function setSeriesAvailability ( uint16 seriesIndex, bool available ) external;
  function setTraitMetadataURI ( string calldata uri ) external;
  function sumAllRefundableTokensValue (  ) external view returns ( uint256 );
  function tokenURI ( uint256 tokenId ) external view returns ( string memory );
}
