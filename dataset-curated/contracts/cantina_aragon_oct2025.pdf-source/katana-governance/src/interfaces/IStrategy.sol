// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IStrategy {
    /// @notice Emitted when assets are deposited by creating a lock and merging to master token
    /// @param depositor The address that deposited the assets
    /// @param tokenId The temporary token ID created before merging
    /// @param amount The amount of assets deposited
    event Deposited(address indexed depositor, uint256 tokenId, uint256 amount);

    /// @notice Emitted when assets are withdrawn by splitting the master token
    /// @param receiver The address that received the split token
    /// @param tokenId The new token ID created from the split
    /// @param amount The amount of assets withdrawn
    event Withdrawn(address indexed receiver, uint256 tokenId, uint256 amount);

    /// @notice Emitted when the strategy is retired and master token transferred back to vault
    /// @param vault The vault address that received the master token
    /// @param masterTokenId The master token ID that was transferred
    event StrategyRetired(address indexed vault, uint256 masterTokenId);

    /// @notice Handles deposit by creating lock and merging to master token
    /// @param _assets Amount of assets to deposit
    function deposit(uint256 _assets) external;

    /// @notice Handles withdrawal by splitting master token and transferring to receiver
    /// @param _receiver The address to receive the split token
    /// @param _assets Amount of assets to withdraw
    function withdraw(address _receiver, uint256 _assets) external returns (uint256);

    /// @notice When vault decides to change strategy, it needs to
    ///         retire old strategy(i.e get masterTokenId back).
    function retireStrategy() external;

    /// @notice Returns the total assets managed by the strategy
    /// @return The total amount of assets locked in the master token
    function totalAssets() external view returns (uint256);
}
