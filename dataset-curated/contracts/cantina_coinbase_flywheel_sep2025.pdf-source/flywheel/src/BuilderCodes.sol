// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {ERC721Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC4906} from "@openzeppelin/contracts/interfaces/IERC4906.sol";
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {LibString} from "solady/utils/LibString.sol";
import {EIP712} from "solady/utils/EIP712.sol";
import {SignatureCheckerLib} from "solady/utils/SignatureCheckerLib.sol";

/// @notice Registry for builder codes
///
/// @author Coinbase
contract BuilderCodes is
    Initializable,
    ERC721Upgradeable,
    AccessControlUpgradeable,
    Ownable2StepUpgradeable,
    UUPSUpgradeable,
    EIP712,
    IERC4906
{
    /// @notice EIP-712 storage structure for registry data
    /// @custom:storage-location erc7201:base.flywheel.BuilderCodes
    struct RegistryStorage {
        /// @notice Base URI for referral code metadata
        string uriPrefix;
        /// @dev Mapping of referral code token IDs to payout recipients
        mapping(uint256 tokenId => address payoutAddress) payoutAddresses;
    }

    /// @notice Role identifier for addresses authorized to call register or sign registrations
    bytes32 public constant REGISTER_ROLE = keccak256("REGISTER_ROLE");

    /// @notice Role identifier for addresses authorized to update metadata for one or all codes
    bytes32 public constant METADATA_ROLE = keccak256("METADATA_ROLE");

    /// @notice EIP-712 typehash for registration
    bytes32 public constant REGISTRATION_TYPEHASH =
        keccak256("BuilderCodeRegistration(string code,address initialOwner,address payoutAddress,uint48 deadline)");

    /// @notice Allowed characters for referral codes
    string public constant ALLOWED_CHARACTERS = "0123456789abcdefghijklmonpqrstuvwxyz_";

    /// @notice Allowed characters for referral codes lookup
    /// @dev LibString.to7BitASCIIAllowedLookup(ALLOWED_CHARACTERS)
    uint128 public constant ALLOWED_CHARACTERS_LOOKUP = 10633823847437083212121898993101832192;

    /// @notice EIP-1967 storage slot base for registry mapping using ERC-7201
    /// @dev keccak256(abi.encode(uint256(keccak256("base.flywheel.BuilderCodes")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant REGISTRY_STORAGE_LOCATION =
        0xe3aaf266708e5133bd922e269bb5e8f72a7444c3b231cbf562ddc67a383e5700;

    /// @notice Emitted when a referral code is registered
    ///
    /// @param tokenId Token ID of the referral code
    /// @param code Referral code
    event CodeRegistered(uint256 indexed tokenId, string code);

    /// @notice Emitted when a publisher's default payout address is updated
    ///
    /// @param tokenId Token ID of the referral code
    /// @param payoutAddress New default payout address for all chains
    event PayoutAddressUpdated(uint256 indexed tokenId, address payoutAddress);

    /// @notice Emits when the contract URI is updated (ERC-7572)
    event ContractURIUpdated();

    /// @notice Thrown when call doesn't have required permissions
    error Unauthorized();

    /// @notice Thrown when provided address is invalid (usually zero address)
    error ZeroAddress();

    /// @notice Thrown when signed registration deadline has passed
    error AfterRegistrationDeadline(uint48 deadline);

    /// @notice Thrown when builder code is invalid
    error InvalidCode(string code);

    /// @notice Thrown when builder code is not registered
    error Unregistered(string code);

    /// @notice Thrown when trying to renounce ownership (disabled for security)
    error OwnershipRenunciationDisabled();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initializes the contract (replaces constructor)
    ///
    /// @param initialOwner Address that will own the contract
    /// @param initialRegistrar Address to grant REGISTER_ROLE (can be address(0) to skip)
    function initialize(address initialOwner, address initialRegistrar, string memory uriPrefix) external initializer {
        if (initialOwner == address(0)) revert ZeroAddress();

        __AccessControl_init();
        __ERC721_init("Builder Codes", "BUILDERCODE");
        __Ownable2Step_init();
        _transferOwnership(initialOwner);
        __UUPSUpgradeable_init();
        _getRegistryStorage().uriPrefix = uriPrefix;

        if (initialRegistrar != address(0)) _grantRole(REGISTER_ROLE, initialRegistrar);
    }

    /// @notice Registers a new referral code in the system with a custom value
    ///
    /// @param code Custom builder code for the builder code
    /// @param initialOwner Owner of the builder code
    /// @param payoutAddress Default payout address for all chains
    function register(string memory code, address initialOwner, address payoutAddress)
        external
        onlyRole(REGISTER_ROLE)
    {
        _register(code, initialOwner, payoutAddress);
    }

    /// @notice Registers a new referral code in the system with a signature
    ///
    /// @param code Custom builder code for the builder code
    /// @param initialOwner Owner of the builder code
    /// @param payoutAddress Default payout address for all chains
    /// @param deadline Deadline to submit the registration
    /// @param registrar Address of the registrar
    /// @param signature Signature of the registrar
    function registerWithSignature(
        string memory code,
        address initialOwner,
        address payoutAddress,
        uint48 deadline,
        address registrar,
        bytes memory signature
    ) external {
        // Check deadline has not passed
        if (block.timestamp > deadline) revert AfterRegistrationDeadline(deadline);

        // Check registrar has role
        _checkRole(REGISTER_ROLE, registrar);

        // Check signature is valid
        bytes32 structHash =
            keccak256(abi.encode(REGISTRATION_TYPEHASH, keccak256(bytes(code)), initialOwner, payoutAddress, deadline));
        if (!SignatureCheckerLib.isValidSignatureNow(registrar, _hashTypedData(structHash), signature)) {
            revert Unauthorized();
        }

        _register(code, initialOwner, payoutAddress);
    }

    /// @notice Updates the metadata for a builder code
    ///
    /// @param tokenId Token ID of the builder code
    function updateMetadata(uint256 tokenId) external onlyRole(METADATA_ROLE) {
        emit MetadataUpdate(tokenId);
    }

    /// @notice Updates the base URI for the builder codes
    ///
    /// @param uriPrefix New base URI for the builder codes
    function updateBaseURI(string memory uriPrefix) external onlyRole(METADATA_ROLE) {
        _getRegistryStorage().uriPrefix = uriPrefix;
        emit BatchMetadataUpdate(0, type(uint256).max);
        emit ContractURIUpdated();
    }

    /// @notice Updates the default payout address for a referral code
    ///
    /// @param code Builder code
    /// @param payoutAddress New default payout address
    /// @dev Only callable by referral code owner
    function updatePayoutAddress(string memory code, address payoutAddress) external {
        uint256 tokenId = toTokenId(code);
        if (_requireOwned(tokenId) != msg.sender) revert Unauthorized();
        _updatePayoutAddress(tokenId, payoutAddress);
    }

    /// @notice Gets the default payout address for a referral code
    ///
    /// @param code Builder code
    ///
    /// @return The default payout address
    function payoutAddress(string memory code) external view returns (address) {
        uint256 tokenId = toTokenId(code);
        if (_ownerOf(tokenId) == address(0)) revert Unregistered(code);
        return _getRegistryStorage().payoutAddresses[tokenId];
    }

    /// @notice Gets the default payout address for a referral code
    ///
    /// @param tokenId Token ID of the referral code
    ///
    /// @return The default payout address
    function payoutAddress(uint256 tokenId) external view returns (address) {
        if (_ownerOf(tokenId) == address(0)) revert Unregistered(toCode(tokenId));
        return _getRegistryStorage().payoutAddresses[tokenId];
    }

    /// @notice Returns the URI for a referral code
    ///
    /// @param code Builder code
    ///
    /// @return The URI for the referral code
    function codeURI(string memory code) external view returns (string memory) {
        return tokenURI(toTokenId(code));
    }

    /// @notice Returns the URI for the contract
    ///
    /// @return The URI for the contract
    function contractURI() external view returns (string memory) {
        string memory uriPrefix = _getRegistryStorage().uriPrefix;
        return bytes(uriPrefix).length > 0 ? string.concat(uriPrefix, "contractURI.json") : "";
    }

    /// @notice Returns the URI for a referral code
    ///
    /// @param tokenId Token ID of the referral code
    ///
    /// @return uri The URI for the referral code
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        string memory uriPrefix = _getRegistryStorage().uriPrefix;
        return bytes(uriPrefix).length > 0 ? string.concat(uriPrefix, toCode(tokenId)) : "";
    }

    /// @notice Checks if a referral code exists
    ///
    /// @param code Builder code to check
    ///
    /// @return True if the referral code exists
    function isRegistered(string memory code) public view returns (bool) {
        return _ownerOf(toTokenId(code)) != address(0);
    }

    /// @notice Checks if an address has a role
    ///
    /// @param role The role to check
    /// @param account The address to check
    ///
    /// @return True if the address has the role
    function hasRole(bytes32 role, address account) public view override returns (bool) {
        return account == owner() || super.hasRole(role, account);
    }

    /// @inheritdoc ERC721Upgradeable
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721Upgradeable, AccessControlUpgradeable, IERC165)
        returns (bool)
    {
        return ERC721Upgradeable.supportsInterface(interfaceId)
            || AccessControlUpgradeable.supportsInterface(interfaceId) || interfaceId == bytes4(0x49064906);
    }

    /// @notice Checks if a referral code is valid
    ///
    /// @param code Builder code to check
    ///
    /// @return True if the referral code is valid
    function isValidCode(string memory code) public pure returns (bool) {
        // Early return invalid if code is zero or over 32 bytes/characters
        uint256 length = bytes(code).length;
        if (length == 0 || length > 32) return false;

        // Return if code is 7-bit ASCII matching the allowed characters
        return LibString.is7BitASCII(code, ALLOWED_CHARACTERS_LOOKUP);
    }

    /// @notice Converts a referral code to a token ID
    ///
    /// @param code Builder code to convert
    ///
    /// @return tokenId The token ID for the referral code
    function toTokenId(string memory code) public pure returns (uint256 tokenId) {
        if (!isValidCode(code)) revert InvalidCode(code);
        return uint256(LibString.toSmallString(code));
    }

    /// @notice Converts a token ID to a referral code
    ///
    /// @param tokenId Token ID to convert
    ///
    /// @return code The referral code for the token ID
    function toCode(uint256 tokenId) public pure returns (string memory code) {
        if (bytes32(tokenId) != LibString.normalizeSmallString(bytes32(tokenId))) revert InvalidCode(code);
        code = LibString.fromSmallString(bytes32(tokenId));
        if (!isValidCode(code)) revert InvalidCode(code);
        return code;
    }

    /// @notice Disabled to prevent accidental ownership renunciation
    ///
    /// @dev Overrides OpenZeppelin's renounceOwnership to prevent accidental calls
    function renounceOwnership() public pure override {
        revert OwnershipRenunciationDisabled();
    }

    /// @notice Registers a new referral code
    ///
    /// @param code Referral code
    /// @param initialOwner Owner of the ref code
    /// @param payoutAddress Default payout address for all chains
    function _register(string memory code, address initialOwner, address payoutAddress) internal {
        uint256 tokenId = toTokenId(code);
        _mint(initialOwner, tokenId);
        emit CodeRegistered(tokenId, code);
        _updatePayoutAddress(tokenId, payoutAddress);
    }

    /// @notice Registers a new referral code
    ///
    /// @param tokenId Token ID of the referral code
    /// @param payoutAddress Default payout address for all chains
    function _updatePayoutAddress(uint256 tokenId, address payoutAddress) internal {
        if (payoutAddress == address(0)) revert ZeroAddress();
        _getRegistryStorage().payoutAddresses[tokenId] = payoutAddress;
        emit PayoutAddressUpdated(tokenId, payoutAddress);
    }

    /// @notice Authorization for upgrades
    ///
    /// @param newImplementation Address of new implementation
    function _authorizeUpgrade(address newImplementation) internal view override onlyOwner {}

    /// @notice Returns the domain name and version for the referral codes
    ///
    /// @return name The domain name for the referral codes
    /// @return version The version of the referral codes
    function _domainNameAndVersion() internal pure override returns (string memory name, string memory version) {
        name = "Builder Codes";
        version = "1";
    }

    /// @notice Returns if the domain name and version may change
    ///
    /// @return True if the domain name and version may change
    function _domainNameAndVersionMayChange() internal pure override returns (bool) {
        return true;
    }

    /// @notice Gets the storage reference for the registry
    ///
    /// @return $ Storage reference for the registry
    function _getRegistryStorage() private pure returns (RegistryStorage storage $) {
        assembly {
            $.slot := REGISTRY_STORAGE_LOCATION
        }
    }
}
