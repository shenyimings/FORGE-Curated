// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IVaultNFT {
    event Sweep(uint256 tokenId, address receiver);
    event TokenIdWithdrawn(uint256 indexed tokenId, address indexed receiver);
    event TokenIdDepositted(uint256 indexed tokenId, address indexed sender);

    error CannotTransferMasterToken();
    error MasterTokenAlreadySet();
    error TokenIdCannotBeZero();

    /// @notice Allows to set up masterTokenId and strategy initially.
    function initializeMasterTokenAndStrategy(uint256 _tokenId, address _strategy) external;

    /// @notice deposit tokenId into the vault.
    /// @dev The assets amount derivation is up to the implementation.
    function depositTokenId(uint256 _tokenId, address _receiver) external returns (uint256 shares);

    /// @notice Withdraws shares through custom logic of strategy
    ///         and returns the new tokenId that holds `_assets`.
    function withdrawTokenId(uint256 _assets, address _receiver, address _owner) external returns (uint256 tokenId);

    /// @notice send veNFT mistakenly transferred to vault to `_receiver`.
    function recoverNFT(uint256 _tokenId, address _receiver) external;

    /// @notice Defines the minimum amount needed to initialize the master token.
    ///         Ensures the vault is not empty at start and protects against inflation attacks.
    function minMasterTokenInitAmount() external view returns (uint256);
}
