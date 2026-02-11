// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title LinkPoolNFT
 * @notice NFT for original crowdsale participants
 */
contract LinkPoolNFT is ERC721URIStorage, Ownable {
    address public lpMigration;
    string public baseURI;
    uint256 public totalSupply;

    constructor(address _lpMigration, string memory _baseUri) ERC721("LinkPool OG", "LPOG") {
        lpMigration = _lpMigration;
        baseURI = _baseUri;
    }

    /**
     * @notice mints new NFT
     * @param _to address to mint NFT for
     **/
    function mint(address _to) external {
        require(msg.sender == lpMigration, "LPMigration only");
        uint256 tokenId = ++totalSupply;
        _safeMint(_to, tokenId);
        _setTokenURI(tokenId, "/");
    }

    /**
     * @notice sets baseURI for NFTs
     * @param _baseUri URI to set
     **/
    function setBaseURI(string memory _baseUri) external onlyOwner {
        baseURI = _baseUri;
    }

    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }
}
