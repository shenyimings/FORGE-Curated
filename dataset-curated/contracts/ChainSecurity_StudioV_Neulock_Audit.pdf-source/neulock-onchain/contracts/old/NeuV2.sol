// SPDX-License-Identifier: CC0-1.0
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721BurnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721RoyaltyUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

import {IERC7496} from "../interfaces/IERC7496.sol";
import {INeuMetadataV2} from "../interfaces/INeuMetadataV2.sol";
import {INeuV2} from "../interfaces/INeuV2.sol";
import {INeuDaoLockV1} from "../interfaces/ILockV1.sol";

contract NeuV2 is
    INeuV2,
    IERC7496,
    Initializable,
    ERC721Upgradeable,
    ERC721EnumerableUpgradeable,
    AccessControlUpgradeable,
    ERC721BurnableUpgradeable,
    ERC721RoyaltyUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable
{
    uint256 private constant VERSION = 2;

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant POINTS_INCREASER_ROLE = keccak256("POINTS_INCREASER_ROLE");

    uint256 private constant GWEI = 1e9;

    uint256 public weiPerSponsorPoint;
    INeuMetadataV2 private _neuMetadata;
    INeuDaoLockV1 private _neuDaoLock;

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
        __ReentrancyGuard_init();

        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(UPGRADER_ROLE, upgrader);
        _grantRole(OPERATOR_ROLE, operator);

        _setDefaultRoyalty(address(this), 1000); // 10%

        weiPerSponsorPoint = 1e14; // 0.0001 ETH

        emit InitializedNeu(VERSION, defaultAdmin, upgrader, operator);
    }

    function initializeV2(address payable neuDaoLockAddress) public reinitializer(2) onlyRole(UPGRADER_ROLE) {
        __ReentrancyGuard_init();

        _neuDaoLock = INeuDaoLockV1(neuDaoLockAddress);

        emit InitializedNeuV2(neuDaoLockAddress);
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
        emit IERC7496.TraitMetadataURIUpdated();
        _neuMetadata.setTraitMetadataURI(uri);
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);

        // slither-disable-start calls-loop (try-catch mitigates the DoS risk on revert)
        try _neuMetadata.tokenURI(tokenId) returns (string memory result) {
            return result;
        } catch {
            return "";
        }
        // slither-disable-end calls-loop
    }

    function setMetadataContract(address newMetadataContract) external onlyRole(OPERATOR_ROLE) {
        _neuMetadata = INeuMetadataV2(newMetadataContract);

        emit MetadataContractUpdated(newMetadataContract);
    }

    function setDaoLockContract(address payable newDaoLockContract) external onlyRole(OPERATOR_ROLE) {
        _neuDaoLock = INeuDaoLockV1(newDaoLockContract);
        
        emit DaoLockContractUpdated(newDaoLockContract);
    }

    function setStorageContract(address newStorageContract) external onlyRole(OPERATOR_ROLE) {
        _grantRole(POINTS_INCREASER_ROLE, newStorageContract);

        emit StorageContractUpdated(newStorageContract);
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
        _privateMint(msg.sender, seriesIndex, seriesPrice);
    }

    function burn (uint256 tokenId) public override {
        super.burn(tokenId);
        _neuMetadata.deleteTokenMetadata(tokenId);
    }

    function withdraw() external onlyRole(OPERATOR_ROLE) {
        uint256 availableBalance = address(this).balance -
            _neuMetadata.sumAllRefundableTokensValue();

        if (availableBalance > 0) {
            // slither-disable-next-line arbitrary-send-eth (msg.sender is operator, guaranteed by onlyRole check)
            payable(msg.sender).transfer(availableBalance);
        }
    }

    function refund(uint256 tokenId) external {
        require(ownerOf(tokenId) == msg.sender, "Caller is not token owner");

        uint256 refundAmount = _neuMetadata.getRefundAmount(tokenId);

        _privateBurn(tokenId);

        payable(msg.sender).transfer(refundAmount);
    }

    function increaseSponsorPoints(uint256 tokenId) external payable onlyRole(POINTS_INCREASER_ROLE) returns (uint256 newSponsorPoints, uint256 sponsorPointsIncrease) {
        (newSponsorPoints, sponsorPointsIncrease) = _increaseSponsorPoints(tokenId, msg.value);

        // slither-disable-next-line low-level-calls (calling like this is the best practice for sending Ether)
        (bool sent, ) = address(_neuDaoLock).call{value: msg.value}("");
        require(sent, "Failed to send Ether");
    }

    function _increaseSponsorPoints(uint256 tokenId, uint256 value) private nonReentrant() returns (uint256 newSponsorPoints, uint256 sponsorPointsIncrease) {
        sponsorPointsIncrease = value / weiPerSponsorPoint;

        if (sponsorPointsIncrease == 0) {
            revert("Not enough ETH sent");
        }

        newSponsorPoints = _neuMetadata.increaseSponsorPoints(tokenId, sponsorPointsIncrease);

        emit IERC7496.TraitUpdated(bytes32("points"), tokenId, bytes32(newSponsorPoints));
    }

    function setWeiPerSponsorPoint(uint256 newWeiPerSponsorPoint) external onlyRole(OPERATOR_ROLE) {
        require(newWeiPerSponsorPoint >= GWEI, "Must be at least 1 gwei");
        weiPerSponsorPoint = newWeiPerSponsorPoint;

        emit WeiPerSponsorPointUpdated(newWeiPerSponsorPoint);
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

        // slither-disable-next-line calls-loop (an unexpected revert here indicates a bug in our NeuMetadata contract that we would need to fix)
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
            // slither-disable-next-line calls-loop (will only revert if there's a bug in our NeuMetadata contract; we don't want to fail silently)
            isUserMinted[i] = _neuMetadata.isUserMinted(tokenIds[i]);
        }
    }

    function getTokensTraitValues(uint256[] calldata tokenIds, bytes32[] calldata traitKeys) external view returns (bytes32[][] memory traitValues) {
        traitValues = new bytes32[][](tokenIds.length);

        for (uint256 i = 0; i < tokenIds.length; i++) {
            traitValues[i] = getTraitValues(tokenIds[i], traitKeys);
        }
    }

    function isGovernanceToken(uint256 tokenId) external view returns (bool) {
        _requireOwned(tokenId);

        return _neuMetadata.isGovernanceToken(tokenId);
    }

    // The following functions are overrides required by Solidity.

    function _update(address to, uint256 tokenId, address auth) internal override(ERC721Upgradeable, ERC721EnumerableUpgradeable) returns (address) {
        return super._update(to, tokenId, auth);
    }

    function _increaseBalance(address account, uint128 value) internal override(ERC721Upgradeable, ERC721EnumerableUpgradeable) {
        super._increaseBalance(account, value);
    }

    function supportsInterface(bytes4 interfaceId) public view override(
            AccessControlUpgradeable,
            ERC721EnumerableUpgradeable,
            ERC721RoyaltyUpgradeable,
            ERC721Upgradeable
        ) returns (bool)
    {
        return
            super.supportsInterface(interfaceId) ||
            interfaceId == type(IERC7496).interfaceId;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}
}