// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.26;

/**
 * @title  Subset of Registrar interface required for source contracts.
 * @author M0 Labs
 */
interface IRegistrarLike {
    /* ============ Interactive Functions ============ */

    /// @notice Adds `account` to `list`.
    function addToList(bytes32 list, address account) external;

    /// @notice Removes `account` from `list`.
    function removeFromList(bytes32 list, address account) external;

    /// @notice Sets the value of `key` to `value`.
    function setKey(bytes32 key, bytes32 value) external;

    /* ============ View/Pure Functions ============ */

    /// @notice Returns the value of `key`.
    function get(bytes32 key) external view returns (bytes32);

    /// @notice Returns whether `list` contains `account` or not.
    function listContains(bytes32 list, address account) external view returns (bool);
}
