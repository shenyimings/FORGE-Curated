// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title IAuth
 * @author Tadle Team
 * @notice Interface for authentication and access control management
 * @dev Provides functions for managing sandbox administrators and system admins
 */
interface IAuth {
    /// @notice Add a new sandbox administrator
    /// @param admin Address to be granted sandbox admin privileges
    function addSandboxAdmin(address admin) external;

    /// @notice Remove an existing sandbox administrator
    /// @param admin Address to have sandbox admin privileges revoked
    function removeSandboxAdmin(address admin) external;

    /// @notice Check if an address is a sandbox administrator for a specific account
    /// @param sandboxAccount The sandbox account to check against
    /// @param admin The address to verify admin status for
    /// @return True if the address is a sandbox admin, false otherwise
    function isSandboxAdmin(
        address sandboxAccount,
        address admin
    ) external view returns (bool);

    /// @notice Check if an address is a system administrator
    /// @param account The address to verify admin status for
    /// @return True if the address is a system admin, false otherwise
    function isAdmin(address account) external view returns (bool);
}

/**
 * @title TadleDefaultImplementation
 * @author Tadle Team
 * @notice Default implementation contract for Tadle sandbox accounts
 * @dev Handles user management and token receiving capabilities
 * @custom:security Implements access control through Auth contract integration
 * @custom:token-support Supports ERC721, ERC1155, and ETH receiving
 */
contract TadleDefaultImplementation {
    /// @dev Auth contract address for access control
    /// @notice Immutable reference to the authentication contract
    address public immutable auth;

    /// @dev Emitted when a user is enabled as sandbox admin
    /// @param user Address of the user that was enabled
    event LogEnableUser(address indexed user);

    /// @dev Emitted when a user is disabled as sandbox admin
    /// @param user Address of the user that was disabled
    event LogDisableUser(address indexed user);

    /**
     * @dev Initialize contract with auth contract address
     * @param _auth Address of the auth contract
     * @notice Sets up the contract with authentication system integration
     * @custom:validation Ensures auth address is not zero
     */
    constructor(address _auth) {
        require(
            _auth != address(0),
            "TadleDefaultImplementation: auth address cannot be zero"
        );
        auth = _auth;
    }

    /**
     * @dev Enable new user as sandbox admin
     * @param user Address to be enabled
     * @notice Grants sandbox admin privileges to the specified user
     * @custom:access-control Caller must be existing sandbox admin or system admin
     * @custom:validation User address must be non-zero
     */
    function enable(address user) public {
        require(
            IAuth(auth).isSandboxAdmin(address(this), msg.sender) ||
                IAuth(auth).isAdmin(msg.sender),
            "TadleDefaultImplementation: caller must be sandbox admin or system admin"
        );
        require(
            user != address(0),
            "TadleDefaultImplementation: user address cannot be zero"
        );
        IAuth(auth).addSandboxAdmin(user);
        emit LogEnableUser(user);
    }

    /**
     * @dev Disable existing user as sandbox admin
     * @param user Address to be disabled
     * @notice Revokes sandbox admin privileges from the specified user
     * @custom:access-control Caller must be existing sandbox admin or system admin
     * @custom:validation User address must be non-zero
     */
    function disable(address user) public {
        require(
            IAuth(auth).isSandboxAdmin(address(this), msg.sender) ||
                IAuth(auth).isAdmin(msg.sender),
            "TadleDefaultImplementation: caller must be sandbox admin or system admin"
        );
        require(
            user != address(0),
            "TadleDefaultImplementation: user address cannot be zero"
        );
        IAuth(auth).removeSandboxAdmin(user);
        emit LogDisableUser(user);
    }

    /**
     * @dev Implementation of IERC721Receiver interface
     * @notice Allows this contract to receive ERC721 tokens
     * @return bytes4 The selector to confirm token transfer
     * @custom:token-support Enables NFT receiving capability
     */
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return 0x150b7a02;
    }

    /**
     * @dev Implementation of IERC1155Receiver interface
     * @notice Allows this contract to receive single ERC1155 tokens
     * @return bytes4 The selector to confirm token transfer
     * @custom:token-support Enables single ERC1155 token receiving capability
     */
    function onERC1155Received(
        address,
        address,
        uint256,
        uint256,
        bytes memory
    ) external pure returns (bytes4) {
        return 0xf23a6e61;
    }

    /**
     * @dev Implementation of IERC1155Receiver interface
     * @notice Allows this contract to receive batched ERC1155 tokens
     * @return bytes4 The selector to confirm batch token transfer
     * @custom:token-support Enables batch ERC1155 token receiving capability
     */
    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    ) external pure returns (bytes4) {
        return 0xbc197c81;
    }

    /**
     * @dev Fallback function to receive ETH transfers
     * @notice Enables the contract to accept plain ETH transfers
     * @custom:payable Accepts ETH without function call data
     */
    receive() external payable {}
}
