// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/**
 * @title FeaturePausable
 * @notice Generic feature pausable helper that allows inheriting contracts to gate arbitrary flows
 * @dev Stores paused states per feature id and exposes internal checks plus pause/unpause helpers
 */
abstract contract FeaturePausable {
    // =================================================================================
    // STORAGE
    // =================================================================================

    /// @custom:storage-location erc7201:pool.storage.FeaturePausable
    struct FeaturePausableStorage {
        mapping(bytes32 featureId => bool isPaused) isFeaturePaused;
    }

    // keccak256(abi.encode(uint256(keccak256("pool.storage.FeaturePausable")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant FEATURE_PAUSABLE_STORAGE_LOCATION =
        0x15990678dc6e70d79055b1ed64b76145ce68c29f966eaa9eea39165e8a41bd00;

    function _getFeaturePausableStorage() private pure returns (FeaturePausableStorage storage $) {
        assembly {
            $.slot := FEATURE_PAUSABLE_STORAGE_LOCATION
        }
    }

    // =================================================================================
    // EVENTS
    // =================================================================================

    event FeaturePaused(bytes32 indexed featureId, address indexed account);
    event FeatureUnpaused(bytes32 indexed featureId, address indexed account);

    // =================================================================================
    // ERRORS
    // =================================================================================

    error FeaturePauseEnforced(bytes32 featureId);
    error FeaturePauseExpected(bytes32 featureId);

    // =================================================================================
    // PUBLIC METHODS
    // =================================================================================

    /**
     * @notice Check if a feature is paused
     * @param _featureId Feature identifier
     * @return isPaused True if paused
     */
    function isFeaturePaused(bytes32 _featureId) public view returns (bool isPaused) {
        isPaused = _getFeaturePausableStorage().isFeaturePaused[_featureId];
    }

    // =================================================================================
    // CHECK HELPERS
    // =================================================================================

    /**
     * @notice Revert if a feature is paused
     * @param _featureId Feature identifier
     */
    function _checkFeatureNotPaused(bytes32 _featureId) internal view {
        if (isFeaturePaused(_featureId)) revert FeaturePauseEnforced(_featureId);
    }

    /**
     * @notice Revert if a feature is not paused
     * @param _featureId Feature identifier
     */
    function _checkFeaturePaused(bytes32 _featureId) internal view {
        if (!isFeaturePaused(_featureId)) revert FeaturePauseExpected(_featureId);
    }

    // =================================================================================
    // PAUSE/UNPAUSE HELPERS
    // =================================================================================

    /**
     * @notice Pause a feature
     * @param _featureId Feature identifier
     */
    function _pauseFeature(bytes32 _featureId) internal {
        _checkFeatureNotPaused(_featureId);
        _getFeaturePausableStorage().isFeaturePaused[_featureId] = true;
        emit FeaturePaused(_featureId, msg.sender);
    }

    /**
     * @notice Resume a feature
     * @param _featureId Feature identifier
     */
    function _resumeFeature(bytes32 _featureId) internal {
        _checkFeaturePaused(_featureId);
        _getFeaturePausableStorage().isFeaturePaused[_featureId] = false;
        emit FeatureUnpaused(_featureId, msg.sender);
    }
}
