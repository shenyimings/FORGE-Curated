// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {Unauthorized, InvalidUpgrade, Paused} from "../interfaces/Errors.sol";
import {ADDRESS_REGISTRY} from "../utils/Constants.sol";

/// @notice A proxy that allows for a timelocked upgrade and selective pausing of the implementation
/// @dev All storage slots are offset to avoid conflicts with the implementation
contract TimelockUpgradeableProxy layout at (2 ** 128) is ERC1967Proxy {

    event UpgradeInitiated(address indexed newImplementation, uint32 upgradeValidAt);

    uint32 public constant UPGRADE_DELAY = 7 days;

    /// @notice Mapping of selector to whether it is whitelisted during a paused state
    mapping(bytes4 => bool) public whitelistedSelectors;

    /// @notice The address of the new implementation
    address public newImplementation;

    /// @notice The timestamp at which the upgrade will be valid
    uint32 public upgradeValidAt;

    /// @notice Whether the proxy is paused
    bool public isPaused;

    constructor(
        address _logic,
        bytes memory _data
    ) ERC1967Proxy(_logic, _data) { }

    receive() external payable {
        // Allow ETH transfers to succeed
    }

    /// @notice Initiates an upgrade and sets the upgrade delay.
    /// @param _newImplementation The address of the new implementation.
    function initiateUpgrade(address _newImplementation) external {
        if (msg.sender != ADDRESS_REGISTRY.upgradeAdmin()) revert Unauthorized(msg.sender);
        newImplementation = _newImplementation;
        if (_newImplementation == address(0)) {
            // Setting the new implementation to the zero address will cancel
            // any pending upgrade.
            upgradeValidAt = 0;
        } else {
            upgradeValidAt = uint32(block.timestamp) + UPGRADE_DELAY;
        }
        emit UpgradeInitiated(_newImplementation, upgradeValidAt);
    }

    /// @notice Executes an upgrade, only the upgradeAdmin can execute this to allow for a post upgrade function call.
    function executeUpgrade(bytes calldata data) external {
        if (msg.sender != ADDRESS_REGISTRY.upgradeAdmin()) revert Unauthorized(msg.sender);
        if (block.timestamp < upgradeValidAt) revert InvalidUpgrade();
        if (newImplementation == address(0)) revert InvalidUpgrade();
        ERC1967Utils.upgradeToAndCall(newImplementation, data);
    }

    function pause() external {
        if (msg.sender != ADDRESS_REGISTRY.pauseAdmin()) revert Unauthorized(msg.sender);
        isPaused = true;
    }

    function unpause() external {
        if (msg.sender != ADDRESS_REGISTRY.pauseAdmin()) revert Unauthorized(msg.sender);
        isPaused = false;
    }

    /// @dev Allows the pause admin to whitelist selectors that can be called even if the proxy is paused, this
    /// is useful for allowing vaults to continue to exit funds but not initiate new entries, for example.
    function whitelistSelectors(bytes4[] calldata selectors, bool isWhitelisted) external {
        if (msg.sender != ADDRESS_REGISTRY.pauseAdmin()) revert Unauthorized(msg.sender);
        for (uint256 i; i < selectors.length; i++) whitelistedSelectors[selectors[i]] = isWhitelisted;
    }

    function getImplementation() external view returns (address) {
        return _implementation();
    }

    function _fallback() internal override {
        // Allows some whitelisted selectors to be called even if the proxy is paused
        if (isPaused && whitelistedSelectors[msg.sig] == false) revert Paused();
        super._fallback();
    }
}