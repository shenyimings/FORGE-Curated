// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title IStableWrapper
 * @notice Interface for the StableWrapper contract
 */
interface IStableWrapper {
    // Structs
    struct WithdrawalReceipt {
        uint224 amount;
        uint32 epoch;
    }

    // Events
    event Deposit(address indexed from, address indexed to, uint256 amount);
    event DepositToVault(address indexed user, uint256 amount);
    event WithdrawalInitiated(address indexed user, uint224 amount, uint32 epoch);
    event Withdrawn(address indexed user, uint256 amount);
    event EpochAdvanced(uint32 newEpoch);
    event AssetTransferred(address indexed to, uint256 amount);
    event PermissionedMint(address indexed to, uint256 amount);
    event PermissionedBurn(address indexed from, uint256 amount);
    event AllowIndependenceSet(bool allowIndependence);
    event KeeperSet(address keeper);

    // View Functions
    function asset() external view returns (address);
    function currentEpoch() external view returns (uint256);
    function allowIndependence() external view returns (bool);
    function withdrawalReceipts(address user) external view returns (WithdrawalReceipt memory);

    // State-Changing Functions
    function depositToVault(address from, uint256 amount) external;
    function deposit(address to, uint256 amount) external;
    function initiateWithdrawal(uint224 amount) external;
    function initiateWithdrawalFromVault(address from, uint224 amount) external;
    function completeWithdrawal(address to) external;
    function advanceEpoch() external;
    function setKeeper(address _keeper) external;
    function setAllowIndependence(bool _allowIndependence) external;
    function setAsset(address _asset) external;
    function transferAsset(address to, uint256 amount, address _token) external;
    function permissionedMint(address to, uint256 amount) external;
    function permissionedBurn(address from, uint256 amount) external;

    // ERC20 Interface Functions (since StableWrapper is also an ERC20)
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}
