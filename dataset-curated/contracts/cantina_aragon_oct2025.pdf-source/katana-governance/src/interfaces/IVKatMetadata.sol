// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/**
 * @title IVKatMetadata Interface
 * @author Aragon
 * @notice Interface for the VKatMetadata sidecar contract that stores user preferences for vKAT NFTs
 * @dev This contract is designed to be UUPS-upgradable and decouples application-specific metadata from the core
 * locking contract
 */
interface IVKatMetadata {
    struct VKatMetaDataV1 {
        uint16[] rewardTokenWeights; // Relative weights, to be normalized by the consumer
        address[] rewardTokens;
    }

    /// @notice Emitted when a user sets or updates their preferences
    event PreferencesSet(address indexed account, VKatMetaDataV1 preferences);

    /// @notice Emitted when admin sets/updates the default preferences.
    event DefaultPreferencesSet(VKatMetaDataV1 preferences);

    /// @notice Emitted when a new reward token is added by the owner
    event RewardTokenAdded(address indexed token);

    /// @notice Emitted when a reward token is removed by the owner
    event RewardTokenRemoved(address indexed token);

    error NotOwner();
    error TokenNotWhitelisted(address token);
    error TokenAlreadyInWhitelist(address token);
    error TokenNotInWhitelist(address token);
    error LengthMismatch();
    error ZeroAddress();
    error DuplicateRewardToken();
    error ReservedAddressCannotBeRemoved();

    // ======= Administrative Functions ======

    /**
     * @notice Adds a new token to the list of allowed reward tokens
     * @dev Can only be called by authorised caller
     * @param _rewardToken The address of the ERC20 token to add
     */
    function addRewardToken(address _rewardToken) external;

    /**
     * @notice Removes a token from the list of allowed reward tokens
     * @dev Can only be called by authorised caller. Off-chain consumers are responsible for ignoring user preferences
     * for removed tokens
     * @param _rewardToken The address of the ERC20 token to remove
     */
    function removeRewardToken(address _rewardToken) external;

    /**
     * @notice Sets a default preference. This is what is returned for
     * a tokenId that doesn't have custom preferences set.
     * @param _defaultPreferences The new default preferences.
     */
    function setDefaultPreferences(VKatMetaDataV1 calldata _defaultPreferences) external;

    // ======= User-Facing Functions =======

    /**
     * @notice Sets the preferences for a given vKAT NFT
     * @dev The caller must be the owner or approved caller of the _tokenId. Reward token weights are relative and do
     * not need to sum to a specific value
     * @param _prefs The preference struct containing the desired settings
     */
    function setPreferences(VKatMetaDataV1 calldata _prefs) external;

    // --- View Functions ---

    /**
     * @notice Retrieves the preferences for a given token, returning defaults if none are set
     * @dev Checks for token existence. If token no longer exists, reverts If custom preferences exist, returns them.
     * Otherwise, returns the system default
     * @param _account The address for which to return preferences.
     * @return A VKatMetaDataV1 struct with the account's preferences
     */
    function getPreferencesOrDefault(address _account) external view returns (VKatMetaDataV1 memory);

    /**
     * @notice Checks if a token is on the allowed reward tokens list
     * @param _token The address of the token to check
     * @return True if the token is allowed, false otherwise
     */
    function isRewardToken(address _token) external view returns (bool);

    /**
     * @notice Returns the address of the kat token
     * @return The address of the kat token
     */
    function kat() external view returns (address);

    /**
     * @notice Returns the default preferences applied to vKAT NFTs without custom settings
     * @return The default VKatMetaDataV1 struct
     */
    function getDefaultPreferences() external view returns (VKatMetaDataV1 memory);

    /**
     * @notice Returns the list of all allowed reward tokens.
     */
    function allowedRewardTokens() external view returns (address[] memory);
}
