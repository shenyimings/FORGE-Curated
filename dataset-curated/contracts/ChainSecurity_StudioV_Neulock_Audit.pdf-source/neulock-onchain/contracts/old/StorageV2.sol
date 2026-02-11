// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts/utils/Base64.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

import {INeuStorageV2} from "../interfaces/INeuStorageV2.sol";
import {INeuV1, INeuTokenV1} from "../interfaces/INeuV1.sol";
import {INeuEntitlementV1} from "../interfaces/IEntitlementV1.sol";

contract NeuStorageV2 is
    Initializable,
    AccessControlUpgradeable,
    UUPSUpgradeable,
    INeuStorageV2
{
    uint256 private constant VERSION = 2;

    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    INeuTokenV1 private _neuContract;
    mapping(address => bytes) private _userdata;
    INeuEntitlementV1 private _entitlementContract;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(
        address defaultAdmin,
        address upgrader,
        address neuContractAddress,
        address entitlementContractAddress
    ) public initializer {
        __AccessControl_init();
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(UPGRADER_ROLE, upgrader);

        _neuContract = INeuTokenV1(neuContractAddress);
        _entitlementContract = INeuEntitlementV1(entitlementContractAddress);

        emit InitializedStorage(VERSION, defaultAdmin, upgrader, neuContractAddress, entitlementContractAddress);
    }

    function initializeV2(address entitlementContractAddress) public reinitializer(2) onlyRole(UPGRADER_ROLE) {
        _entitlementContract = INeuEntitlementV1(entitlementContractAddress);

        emit InitializedStorageV2(entitlementContractAddress);
    }

    function saveData(uint256 tokenId, bytes memory data) external payable {
        // Call with tokenId = 0 if entitlement by token other than the NEU
        require(_entitlementContract.hasEntitlement(msg.sender), "Caller does not have entitlement");
        require(msg.value == 0 || _neuContract.ownerOf(tokenId) == msg.sender, "Cannot add points to unowned NEU");

        _userdata[msg.sender] = data;

        emit DataSaved(tokenId, data);

        if (msg.value > 0) {
            // slither-disable-next-line unused-return (we make this call only for the side effect)
            _neuContract.increaseSponsorPoints{value: msg.value}(tokenId);
        }
    }

    function retrieveData(address owner) external view returns (bytes memory) {
        return _userdata[owner];
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        onlyRole(UPGRADER_ROLE)
        override
    {}
}

