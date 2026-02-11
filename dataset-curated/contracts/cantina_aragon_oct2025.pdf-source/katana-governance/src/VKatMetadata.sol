// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { EnumerableSet } from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import { DaoAuthorizableUpgradeable as DaoAuthorizable } from
    "@aragon/osx-commons-contracts/src/permission/auth/DaoAuthorizableUpgradeable.sol";
import { IDAO } from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";

import { IVKatMetadata } from "src/interfaces/IVKatMetadata.sol";
import { VotingEscrow } from "@setup/GaugeVoterSetup_v1_4_0.sol";

contract VKatMetadata is IVKatMetadata, DaoAuthorizable, UUPSUpgradeable {
    using EnumerableSet for EnumerableSet.AddressSet;

    /// @notice The bytes32 identifier for admin role functions.
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    /// @notice Expresses a preference to auto-compound rewards into vKat.
    address public constant AUTOCOMPOUND_RESERVED_ADDRESS = address(type(uint160).max);

    /// @notice The preferences per user.
    mapping(address => VKatMetaDataV1) private preferences;

    /// @notice The list of whitelisted tokens added by admin.
    EnumerableSet.AddressSet internal rewardTokens;

    /// @notice The default preferences that will be used if user hasn't set it.
    VKatMetaDataV1 private defaultPreferences;

    /// @notice The address of kat token.
    address public kat;

    constructor() {
        _disableInitializers();
    }

    function initialize(address _dao, address _kat, address[] calldata _rewardTokens) external initializer {
        __DaoAuthorizableUpgradeable_init(IDAO(_dao));

        kat = _kat;

        // whitelist reward tokens.
        for (uint256 i = 0; i < _rewardTokens.length; i++) {
            address token = _rewardTokens[i];
            rewardTokens.add(token);
            emit RewardTokenAdded(token);
        }

        // add KAT as a reward token.
        rewardTokens.add(kat);
        emit RewardTokenAdded(kat);

        // add the reserved address for auto-compounding.
        rewardTokens.add(AUTOCOMPOUND_RESERVED_ADDRESS);
        emit RewardTokenAdded(AUTOCOMPOUND_RESERVED_ADDRESS);

        // Set the default preferences to auto-compound into vKat.
        uint16[] memory _weights = new uint16[](1);
        address[] memory _tokens = new address[](1);
        VKatMetaDataV1 memory _defaultPreferences =
            VKatMetaDataV1({ rewardTokenWeights: _weights, rewardTokens: _tokens });
        _defaultPreferences.rewardTokens[0] = AUTOCOMPOUND_RESERVED_ADDRESS;
        _defaultPreferences.rewardTokenWeights[0] = 1;
        _setDefaultPreferences(_defaultPreferences);
    }

    // ============= Admin Functions ====================

    /// @inheritdoc IVKatMetadata
    function addRewardToken(address _token) external auth(ADMIN_ROLE) {
        if (_token == address(0)) {
            revert ZeroAddress();
        }

        bool added = rewardTokens.add(_token);
        if (!added) {
            revert TokenAlreadyInWhitelist(_token);
        }

        emit RewardTokenAdded(_token);
    }

    /// @inheritdoc IVKatMetadata
    function removeRewardToken(address _token) external auth(ADMIN_ROLE) {
        if (_token == AUTOCOMPOUND_RESERVED_ADDRESS || _token == kat) {
            revert ReservedAddressCannotBeRemoved();
        }

        bool removed = rewardTokens.remove(_token);
        if (!removed) {
            revert TokenNotInWhitelist(_token);
        }

        emit RewardTokenRemoved(_token);
    }

    /// @inheritdoc IVKatMetadata
    function setDefaultPreferences(VKatMetaDataV1 memory _preferences) external auth(ADMIN_ROLE) {
        _setDefaultPreferences(_preferences);
    }

    // ============ User Specific Functions =============

    /// @inheritdoc IVKatMetadata
    function setPreferences(VKatMetaDataV1 calldata _preferences) public virtual {
        _validatePreferences(_preferences);
        preferences[msg.sender] = _preferences;

        emit PreferencesSet(msg.sender, _preferences);
    }

    // =========== View Functions ==============

    /// @inheritdoc IVKatMetadata
    function isRewardToken(address _token) public view returns (bool) {
        return rewardTokens.contains(_token);
    }

    /// @inheritdoc IVKatMetadata
    function getPreferencesOrDefault(address _account) public view returns (VKatMetaDataV1 memory) {
        VKatMetaDataV1 memory preferences_ = preferences[_account];

        if (preferences_.rewardTokens.length == 0) {
            preferences_ = getDefaultPreferences();
        }

        return preferences_;
    }

    /// @inheritdoc IVKatMetadata
    function getDefaultPreferences() public view virtual returns (VKatMetaDataV1 memory) {
        return defaultPreferences;
    }

    /// @inheritdoc IVKatMetadata
    function allowedRewardTokens() external view returns (address[] memory) {
        return rewardTokens.values();
    }

    /// @dev Helper function to validate the new default preferences and set it.
    function _setDefaultPreferences(VKatMetaDataV1 memory _preferences) internal virtual {
        _validatePreferences(_preferences);

        defaultPreferences = _preferences;
        emit DefaultPreferencesSet(_preferences);
    }

    function _validatePreferences(VKatMetaDataV1 memory _preferences) internal virtual {
        if (_preferences.rewardTokens.length != _preferences.rewardTokenWeights.length) {
            revert LengthMismatch();
        }

        address[] memory tokens = _preferences.rewardTokens;

        for (uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];

            // Validate that reward token is already
            // added by admin in a whitelist.
            if (!isRewardToken(token)) {
                revert TokenNotWhitelisted(token);
            }

            // Ensure for no duplicate addresses
            for (uint256 j = i + 1; j < tokens.length; j++) {
                if (tokens[j] == token) {
                    revert DuplicateRewardToken();
                }
            }
        }
    }

    // =========== Upgrade Related Functions ===========
    function _authorizeUpgrade(address) internal override auth(ADMIN_ROLE) { }

    function implementation() external view returns (address) {
        return _getImplementation();
    }

    /// @dev Reserved storage space to allow for layout changes in the future.
    uint256[44] private __gap;
}
