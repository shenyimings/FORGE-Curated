// SPDX-License-Identifier: CC0-1.0
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.27;

import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721RoyaltyUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import {IERC7496} from "../interfaces/IERC7496.sol";
import {INeuMetadataV1} from "../interfaces/INeuMetadataV1.sol";
import {INeuV1} from "../interfaces/INeuV1.sol";
import {TokenMetadata} from "./MetadataV1.sol";

contract NeuV1 is
    INeuV1,
    IERC7496,
    Initializable,
    ERC721Upgradeable,
    ERC721EnumerableUpgradeable,
    AccessControlUpgradeable,
    ERC721BurnableUpgradeable,
    ERC721RoyaltyUpgradeable,
    UUPSUpgradeable
{
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant POINTS_INCREASER_ROLE = keccak256("POINTS_INCREASER_ROLE");

    uint256 public weiPerSponsorPoint;
    INeuMetadataV1 private _neuMetadata;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address defaultAdmin,
        address upgrader,
        address operator
    ) public initializer {
        __ERC721_init("Neulock", "NEU");
        __ERC721Enumerable_init();
        __AccessControl_init();
        __ERC721Burnable_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(UPGRADER_ROLE, upgrader);
        _grantRole(OPERATOR_ROLE, operator);

        _setDefaultRoyalty(address(this), 1000); // 10%

        weiPerSponsorPoint = 1e14; // 0.0001 ETH
    }

    function getTraitMetadataURI()
        external
        view
        override
        returns (string memory uri)
    {
        return _neuMetadata.getTraitMetadataURI();
    }

    function _setTraitMetadataURI(string calldata uri) private {
        _neuMetadata.setTraitMetadataURI(uri);
        emit IERC7496.TraitMetadataURIUpdated();
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);

        try _neuMetadata.tokenURI(tokenId) returns (string memory result) {
            return result;
        } catch {
            return "";
        }
    }

    function setMetadataContract(
        address newMetadataContract
    ) external onlyRole(OPERATOR_ROLE) {
        _neuMetadata = INeuMetadataV1(newMetadataContract);
    }

    function setStorageContract(
        address newStorageContract
    ) external onlyRole(OPERATOR_ROLE) {
        _grantRole(POINTS_INCREASER_ROLE, newStorageContract);
    }

    function _privateMint(
        address to,
        uint16 seriesIndex,
        uint256 originalPrice
    ) private returns (uint256 tokenId, bool governance) {
        (tokenId, governance) = _neuMetadata.createTokenMetadata(seriesIndex, originalPrice);

        _safeMint(to, tokenId);
    }

    function _privateBurn(uint256 tokenId) private {
        _burn(tokenId);
        _neuMetadata.deleteTokenMetadata(tokenId);
    }

    function safeMint(address to, uint16 seriesIndex) public override onlyRole(OPERATOR_ROLE) {
        _privateMint(to, seriesIndex, 0);
    }

    function safeMintPublic(uint16 seriesIndex) external payable {
        uint256 seriesPrice = _neuMetadata.getSeriesMintingPrice(seriesIndex);

        require(msg.value >= seriesPrice, "Not enough ETH sent");
        (uint256 tokenId, bool governance) = _privateMint(msg.sender, seriesIndex, seriesPrice);

        if (governance && msg.value >= weiPerSponsorPoint) {
            _increaseSponsorPoints(tokenId, msg.value);
        }
    }

    function burn (uint256 tokenId) public override {
        super.burn(tokenId);
        _neuMetadata.deleteTokenMetadata(tokenId);
    }

    function withdraw() external onlyRole(OPERATOR_ROLE) {
        uint256 availableBalance = address(this).balance -
            _neuMetadata.sumAllRefundableTokensValue();

        if (availableBalance > 0) {
            payable(msg.sender).transfer(availableBalance);
        }
    }

    function refund(uint256 tokenId) external {
        require(ownerOf(tokenId) == msg.sender, "Caller is not token owner");

        uint256 refundAmount = _neuMetadata.getRefundAmount(tokenId);

        _privateBurn(tokenId);

        payable(msg.sender).transfer(refundAmount);
    }

    function increaseSponsorPoints(uint256 tokenId) external payable onlyRole(POINTS_INCREASER_ROLE) returns (uint256, uint256) {
        return _increaseSponsorPoints(tokenId, msg.value);
    }

    function _increaseSponsorPoints(uint256 tokenId, uint256 value) private returns (uint256, uint256) {
        uint256 sponsorPointsIncrease = value / weiPerSponsorPoint;

        if (sponsorPointsIncrease == 0) {
            revert("Not enough ETH sent");
        }

        uint256 newSponsorPoints = _neuMetadata.increaseSponsorPoints(tokenId, sponsorPointsIncrease);

        emit IERC7496.TraitUpdated(bytes32("points"), tokenId, bytes32(newSponsorPoints));

        return (newSponsorPoints, sponsorPointsIncrease);
    }

    function setWeiPerSponsorPoint(uint256 newWeiPerSponsorPoint) external onlyRole(OPERATOR_ROLE) {
        require(newWeiPerSponsorPoint >= 1e9, "Must be at least 1 gwei");
        weiPerSponsorPoint = newWeiPerSponsorPoint;
    }

    function setTrait(
        uint256 /*tokenId*/,
        bytes32 /*traitKey*/,
        bytes32 /*newValue*/
    ) pure public {
        // We won't allow setting any trait individually.
        revert("Trait cannot be set");
    }

    function getTraitValue(
        uint256 tokenId,
        bytes32 traitKey
    ) public view returns (bytes32 traitValue) {
        _requireOwned(tokenId);

        return _neuMetadata.getTraitValue(tokenId, traitKey);
    }

    function getTraitValues(
        uint256 tokenId,
        bytes32[] calldata traitKeys
    ) public view virtual override returns (bytes32[] memory traitValues) {
        _requireOwned(tokenId);

        return _neuMetadata.getTraitValues(tokenId, traitKeys);
    }

    function setTraitMetadataURI(
        string calldata uri
    ) external onlyRole(OPERATOR_ROLE) {
        _setTraitMetadataURI(uri);
    }

    function getTokensOfOwner(address owner) public view returns (uint256[] memory tokenIds) {
        uint256 tokenCount = balanceOf(owner);

        tokenIds = new uint256[](tokenCount);

        for (uint256 i = 0; i < tokenCount; i++) {
            tokenIds[i] = tokenOfOwnerByIndex(owner, i);
        }
    }

    function getTokensWithData(uint256[] calldata tokenIds) external view returns (string[] memory tokenUris, bool[] memory isUserMinted) {
        tokenUris = new string[](tokenIds.length);
        isUserMinted = new bool[](tokenIds.length);

        for (uint256 i = 0; i < tokenIds.length; i++) {
            tokenUris[i] = tokenURI(tokenIds[i]);
            isUserMinted[i] = _neuMetadata.isUserMinted(tokenIds[i]);
        }
    }

    function getTokensTraitValues(uint256[] calldata tokenIds, bytes32[] calldata traitKeys) external view returns (bytes32[][] memory traitValues) {
        traitValues = new bytes32[][](tokenIds.length);

        for (uint256 i = 0; i < tokenIds.length; i++) {
            traitValues[i] = getTraitValues(tokenIds[i], traitKeys);
        }
    }

    // The following functions are overrides required by Solidity.

    function _update(
        address to,
        uint256 tokenId,
        address auth
    )
        internal
        override(ERC721Upgradeable, ERC721EnumerableUpgradeable)
        returns (address)
    {
        return super._update(to, tokenId, auth);
    }

    function _increaseBalance(
        address account,
        uint128 value
    ) internal override(ERC721Upgradeable, ERC721EnumerableUpgradeable) {
        super._increaseBalance(account, value);
    }

    function supportsInterface(
        bytes4 interfaceId
    )
        public
        view
        override(
            AccessControlUpgradeable,
            ERC721EnumerableUpgradeable,
            ERC721RoyaltyUpgradeable,
            ERC721Upgradeable
        )
        returns (bool)
    {
        return
            super.supportsInterface(interfaceId) ||
            interfaceId == type(IERC7496).interfaceId;
    }

    function _authorizeUpgrade(
        address newImplementation
    ) internal override onlyRole(UPGRADER_ROLE) {}
}