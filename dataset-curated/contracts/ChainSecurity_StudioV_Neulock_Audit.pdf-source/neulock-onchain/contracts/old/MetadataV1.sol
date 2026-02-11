// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.27;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/utils/Base64.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import {IERC7496} from "../interfaces/IERC7496.sol";
import {INeuMetadataV1} from "../interfaces/INeuMetadataV1.sol";
import {NeuLogoV1} from "./LogoV1.sol";
import {Bytes8Utils} from "../lib/Utils.sol";

using Bytes8Utils for bytes8;
using Strings for uint256;

struct Series {
    bytes8 name;
    uint64 priceInGwei;
    uint32 firstToken;
    uint32 maxTokens;
    uint32 mintedTokens;
    uint32 burntTokens;
    uint16 fgColorRGB565;
    uint16 bgColorRGB565;
    uint16 accentColorRGB565;
}

struct TokenMetadata {
    uint64 originalPriceInGwei;
    uint64 sponsorPoints;
    uint40 mintedAt;
}

contract NeuMetadataV1 is
    Initializable,
    AccessControlUpgradeable,
    UUPSUpgradeable,
    INeuMetadataV1
{
    bytes32 public constant NEU_ROLE = keccak256("NEU_ROLE");
    bytes32 public constant STORAGE_ROLE = keccak256("STORAGE_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    uint256 private constant REFUND_WINDOW = 7 days;

    string _traitMetadataURI;
    mapping(uint256 => TokenMetadata) private _tokenMetadata;
    Series[] private _series;
    uint16[] private _availableSeries;
    NeuLogoV1 private _logo;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address defaultAdmin,
        address upgrader,
        address operator,
        address neuContract,
        address logoContract
    ) public initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(UPGRADER_ROLE, upgrader);
        _grantRole(OPERATOR_ROLE, operator);
        _grantRole(NEU_ROLE, neuContract);

        _logo = NeuLogoV1(logoContract);
    }

    function createTokenMetadata(uint16 seriesIndex, uint256 originalPrice) external onlyRole(NEU_ROLE) returns (
        uint256 tokenId,
        bool governance
    ) {
        require(seriesIndex < _series.length, "Invalid series index");
        require(_series[seriesIndex].mintedTokens < _series[seriesIndex].maxTokens, "Series has been fully minted");

        tokenId = _series[seriesIndex].firstToken + _series[seriesIndex].mintedTokens;

        _setTokenMetadata(tokenId, TokenMetadata({
            originalPriceInGwei: uint64(originalPrice / 1e9),
            sponsorPoints: 0,
            mintedAt: uint40(block.timestamp)
        }));

        _series[seriesIndex].mintedTokens++;

        if (_series[seriesIndex].mintedTokens == _series[seriesIndex].maxTokens) {
            _removeAvailableSeries(seriesIndex);
        }

        governance = _givesGovernanceAccess(seriesIndex);
    }

    function deleteTokenMetadata(uint256 tokenId) external onlyRole(NEU_ROLE) {
        require(_metadataExists(tokenId), "Token metadata does not exist");

        uint16 seriesIndex = _seriesOfToken(tokenId);

        _series[seriesIndex].burntTokens++;
        delete _tokenMetadata[tokenId];
    }

    function setTraitMetadataURI(string calldata uri) external onlyRole(NEU_ROLE) {
        _setTraitMetadataURI(uri);
    }

    function tokenURI(uint256 tokenId) external view returns (string memory) {
        return string(abi.encodePacked(
            "data:application/json;base64,",
            Base64.encode(_makeJsonMetadata(tokenId))));
    }

    function isUserMinted(uint256 tokenId) external view returns (bool) {
        return _metadataExists(tokenId) && _tokenMetadata[tokenId].originalPriceInGwei > 0;
    }

    function getTraitValue(uint256 tokenId, bytes32 traitKey) external view returns (bytes32) {
        return _getTraitValue(tokenId, traitKey);
    }

    function getTraitValues(uint256 tokenId, bytes32[] calldata traitKeys) external view returns (bytes32[] memory traitValues) {
        uint256 length = traitKeys.length;
        traitValues = new bytes32[](length);

        for (uint256 i = 0; i < length; ) {
            bytes32 traitKey = traitKeys[i];
            traitValues[i] = _getTraitValue(tokenId, traitKey);
            unchecked {
                ++i;
            }
        }
    }

    function getTraitMetadataURI() external view returns (string memory) {
        // Return the trait metadata URI.
        return _traitMetadataURI;
    }

    function addSeries(bytes8 name, uint64 priceInGwei, uint32 firstToken, uint32 maxTokens, uint16 fgColorRGB565, uint16 bgColorRGB565, uint16 accentColorRGB565, bool makeAvailable) external onlyRole(OPERATOR_ROLE) returns (uint16) {
        uint16 seriesIndex = uint16(_series.length);
        uint256 maxToken = firstToken + maxTokens - 1;

        for (uint16 i = 0; i < _series.length; i++) {
            require(_series[i].name != name, "Series name already exists");
            require(maxToken < _series[i].firstToken || firstToken >= _series[i].firstToken + _series[i].maxTokens, "Series overlaps with existing");
        }

        _series.push(Series({
            name: name,
            priceInGwei: priceInGwei,
            firstToken: firstToken,
            maxTokens: maxTokens,
            mintedTokens: 0,
            burntTokens: 0,
            fgColorRGB565: fgColorRGB565,
            bgColorRGB565: bgColorRGB565,
            accentColorRGB565: accentColorRGB565
        }));

        if (makeAvailable) {
            _availableSeries.push(seriesIndex);
        }

        return seriesIndex;
    }

    function getSeries(uint16 seriesIndex) external view returns (
        bytes8 name,
        uint256 priceInGwei,
        uint256 firstToken,
        uint256 maxTokens,
        uint256 mintedTokens,
        uint256 burntTokens,
        bool isAvailable,
        string memory logoSvg
    ) {
        require(seriesIndex < _series.length, "Invalid series index");

        Series memory series = _series[seriesIndex];

        name = series.name;
        priceInGwei = series.priceInGwei;
        firstToken = series.firstToken;
        maxTokens = series.maxTokens;
        mintedTokens = series.mintedTokens;
        burntTokens = series.burntTokens;
        isAvailable = _isSeriesAvailable(seriesIndex);
        logoSvg = _logo.makeLogo(
            _makeMaskedTokenId(series), series.name.toString(), series.fgColorRGB565, series.bgColorRGB565, series.accentColorRGB565);
    }

    function isSeriesAvailable(uint16 seriesIndex) external view returns (bool) {
        return _isSeriesAvailable(seriesIndex);
    }

    function setSeriesAvailability(uint16 seriesIndex, bool available) external onlyRole(OPERATOR_ROLE) {
        require(seriesIndex < _series.length, "Invalid series index");

        if (available) {
            Series memory series = _series[seriesIndex];

            if (series.mintedTokens == series.maxTokens) {
                revert("Series has been fully minted");
            }
        }

        bool isAlreadyAvailable = _isSeriesAvailable(seriesIndex);

        if (available && !isAlreadyAvailable) {
            _availableSeries.push(seriesIndex);
        } else if (!available && isAlreadyAvailable) {
            _removeAvailableSeries(seriesIndex);
        }
    }

    function getAvailableSeries() external view returns(uint16[] memory) {
        return _availableSeries;
    }

    function setPriceInGwei(uint16 seriesIndex, uint64 price) external onlyRole(OPERATOR_ROLE) {
        require(seriesIndex < _series.length, "Invalid series index");
        _series[seriesIndex].priceInGwei = price;
    }

    function getSeriesMintingPrice(uint16 seriesIndex) external view returns (uint256) {
        require(_isSeriesAvailable(seriesIndex), "Public minting not available");

        return uint256(_series[seriesIndex].priceInGwei) * 1e9;
    }

    function sumAllRefundableTokensValue() external view returns (uint256) {
        uint256 totalValue = 0;

        for (uint16 s = 0; s < _series.length; s++) {
            for (uint256 i = _series[s].firstToken + _series[s].mintedTokens - 1; i >= _series[s].firstToken; i--) {
                TokenMetadata memory metadata = _tokenMetadata[i];

                if (!_metadataExists(i)) {
                    // Token has been burned
                    continue;
                }

                if (block.timestamp - metadata.mintedAt > REFUND_WINDOW) {
                    // All tokens before this one in the series are also expired
                    break;
                }

                totalValue += metadata.originalPriceInGwei;
            }
        }

        return totalValue * 1e9;
    }

    function getRefundAmount(uint256 tokenId) external view returns (uint256) {
        TokenMetadata memory metadata = _tokenMetadata[tokenId];

        require(metadata.originalPriceInGwei > 0, "Token is not refundable");
        require(block.timestamp - metadata.mintedAt < REFUND_WINDOW, "Refund window has passed");

        return metadata.originalPriceInGwei * 1e9;
    }

    function setLogoContract(address logoContract) external onlyRole(OPERATOR_ROLE) {
        _logo = NeuLogoV1(logoContract);
    }

    function _setTokenMetadata(
        uint256 tokenId,
        TokenMetadata memory metadata
    ) internal {
        // This function is to be called only on token mint. Won't emit TraitUpdated event.
        _tokenMetadata[tokenId] = metadata;
    }

    function increaseSponsorPoints(uint256 tokenId, uint256 sponsorPointsIncrease) external onlyRole(NEU_ROLE) returns (uint256) {
        TokenMetadata memory metadata = _tokenMetadata[tokenId];

        uint256 newSponsorPoints = metadata.sponsorPoints + sponsorPointsIncrease;

        _tokenMetadata[tokenId] = TokenMetadata({
            originalPriceInGwei: metadata.originalPriceInGwei,
            sponsorPoints: uint64(newSponsorPoints),
            mintedAt: metadata.mintedAt
        });

        return newSponsorPoints;
    }

    function _isSeriesAvailable(uint16 seriesIndex) private view returns (bool) {
        for (uint256 i = 0; i < _availableSeries.length; i++) {
            if (_availableSeries[i] == seriesIndex) {
                return true;
            }
        }

        return false;
    }

    function _removeAvailableSeries(uint16 seriesIndex) private {
        for (uint256 i = 0; i < _availableSeries.length; i++) {
            if (_availableSeries[i] == seriesIndex) {
                _availableSeries[i] = _availableSeries[_availableSeries.length - 1];
                _availableSeries.pop();
                return;
            }
        }
    }

    function _getTraitValue(uint256 tokenId, bytes32 traitKey) private view returns (bytes32) {
        TokenMetadata memory metadata = _tokenMetadata[tokenId];

        if (traitKey == "points") {
            return bytes32(uint256(metadata.sponsorPoints));
        } else {
            revert("Trait key not found");
        }
    }

    function _makeJsonMetadata(uint256 tokenId) internal view returns (bytes memory) {
        TokenMetadata memory metadata = _tokenMetadata[tokenId];
        uint16 seriesIndex = _seriesOfToken(tokenId);
        Series memory series = _series[seriesIndex];
        string memory governance = _givesGovernanceAccess(seriesIndex) ? "Yes" : "No";
        string memory seriesName = series.name.toString();
        string memory tokenName = string(abi.encodePacked(tokenId.toString(), ' ', seriesName));
        string memory logoSvg = Base64.encode(bytes(_logo.makeLogo(
            tokenId.toString(), seriesName, series.fgColorRGB565, series.bgColorRGB565, series.accentColorRGB565)));

        return abi.encodePacked(
            '{"description": "Neulock Password Manager membership NFT - neulock.app", "name": "NEU #',
            tokenName,
            '", "image": "data:image/svg+xml;base64,',
            logoSvg,
            '", "attributes": [{"trait_type": "Series", "value": "',
            seriesName,
            '"},{"trait_type": "Governance Access", "value": "',
            governance,
            '"},{"trait_type": "Series Max Supply", "value": ',
            uint256(series.maxTokens).toString(),
            '},{"trait_type": "Mint Date", "display_type": "date", "value": ',
            uint256(metadata.mintedAt).toString(),
            '}]}'
        );
    }

    function _seriesOfToken(uint256 tokenId) private view returns (uint16) {
        for (uint16 i = 0; i < _series.length; i++) {
            if (tokenId >= _series[i].firstToken && tokenId < _series[i].firstToken + _series[i].maxTokens) {
                return i;
            }
        }

        revert("Token does not belong to any series");
    }

    function _makeMaskedTokenId(Series memory series) private pure returns (string memory) {
        uint256 lastToken = series.firstToken + series.maxTokens - 1;
        bytes memory lastTokenBytes = bytes(lastToken.toString());
        bytes memory firstTokenBytes = bytes(uint256(series.firstToken).toString());

        bool stoppedMatching = firstTokenBytes.length != lastTokenBytes.length;
        bytes memory result = new bytes(lastTokenBytes.length);

        for (uint256 i = 0; i < result.length; i++) {
            if (!stoppedMatching && firstTokenBytes.length > i && lastTokenBytes[i] == firstTokenBytes[i]) {
                result[i] = lastTokenBytes[i];
            } else {
                stoppedMatching = true;
                result[i] = "x";
            }
        }

        return string(result);
    }

    function _metadataExists(uint256 tokenId) private view returns (bool) {
        return _tokenMetadata[tokenId].mintedAt != 0;
    }

    function _givesGovernanceAccess(uint16 seriesIndex) private view returns (bool) {
        // Tokens whose name do not start with "WAGMI" give governance access
        bytes32 wagmiNamePrefix = "WAGMI";

        for (uint256 i = 0; i < 5; i++) {
            if (_series[seriesIndex].name[i] != wagmiNamePrefix[i]) {
                return true;
            }
        }

        return false;
    }

    function _setTraitMetadataURI(string memory uri) internal virtual {
        // Set the new trait metadata URI.
        _traitMetadataURI = uri;
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        onlyRole(UPGRADER_ROLE)
        override
    {}
}
