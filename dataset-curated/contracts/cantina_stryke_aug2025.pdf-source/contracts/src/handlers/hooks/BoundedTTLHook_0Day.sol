// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0 <0.9.0;

import {IHook} from "../../interfaces/IHook.sol";
import {IHandler} from "../../interfaces/IHandler.sol";
import {Ownable} from "openzeppelin-contracts/contracts/access/Ownable.sol";

/// @title BoundedTTLHook_0Day
/// @author 0xcarrot
/// @notice A hook contract that enforces a maximum TTL (Time To Live) of 24 hours for whitelisted applications
/// @dev Implements IHook interface and inherits from Ownable
contract BoundedTTLHook_0Day is IHook, Ownable {
    error ExpiryTooLong();
    error AppNotWhitelisted();

    /// @notice Mapping to store whitelisted applications
    mapping(address => bool) whitelistedApps;

    /// @notice Empty hook function for minting (before)
    function onMintBefore(bytes calldata) external {}
    /// @notice Empty hook function for minting (after)
    function onMintAfter(bytes calldata) external {}
    /// @notice Empty hook function for reserving (before)
    function onReserveBefore(bytes calldata) external {}
    /// @notice Empty hook function for reserving (after)
    function onReserveAfter(bytes calldata) external {}
    /// @notice Empty hook function for burning (before)
    function onBurnBefore(bytes calldata) external {}
    /// @notice Empty hook function for burning (after)
    function onBurnAfter(bytes calldata) external {}
    /// @notice Empty hook function for donating (before)
    function onDonationBefore(bytes calldata) external {}
    /// @notice Empty hook function for donating (after)
    function onDonationAfter(bytes calldata) external {}
    /// @notice Empty hook function for position use (after)
    function onPositionUseAfter(bytes calldata) external {}
    /// @notice Empty hook function for position unuse (before)
    function onPositionUnUseBefore(bytes calldata) external {}
    /// @notice Empty hook function for position unuse (after)
    function onPositionUnUseAfter(bytes calldata) external {}
    /// @notice Empty hook function for wildcard actions (before)
    function onWildcardBefore(bytes calldata) external {}
    /// @notice Empty hook function for wildcard actions (after)
    function onWildcardAfter(bytes calldata) external {}

    /// @notice Constructor to set up the contract
    /// @dev Initializes the Ownable contract with the deployer as the owner
    constructor() Ownable(msg.sender) {}

    /// @notice Checks if a position use is allowed based on expiry time
    /// @dev Reverts if the app is not whitelisted or if the expiry is more than 24 hours in the future
    /// @param _data Encoded data containing the app address and expiry timestamp
    function onPositionUseBefore(bytes calldata _data) external {
        (address app, uint256 expiry) = abi.decode(_data, (address, uint256));
        if (!whitelistedApps[app]) revert AppNotWhitelisted();
        if (expiry - block.timestamp > 24 hours) revert ExpiryTooLong();
    }

    /// @notice Registers the hook with a handler contract
    /// @dev Can only be called by the contract owner
    /// @param _handler Address of the handler contract to register with
    function registerHook(address _handler) external onlyOwner {
        IHandler(_handler).registerHook(
            address(this),
            IHandler.HookPermInfo({
                onMint: false,
                onBurn: false,
                onUse: true,
                onUnuse: false,
                onDonate: false,
                allowSplit: true
            })
        );
    }

    /// @notice Updates the whitelist status of an application
    /// @dev Can only be called by the contract owner
    /// @param app Address of the application to update
    /// @param status New whitelist status for the application
    function updateWhitelistedAppsStatus(address app, bool status) external onlyOwner {
        whitelistedApps[app] = status;
    }
}
