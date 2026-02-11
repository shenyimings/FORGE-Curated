// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.19;

interface ILevelMintingEvents {
    /// @notice Event emitted when contract receives ETH
    event Received(address, uint256);

    /// @notice Event emitted when lvlUSD is minted
    event Mint(
        address minter,
        address benefactor,
        address beneficiary,
        address indexed collateral_asset,
        uint256 indexed collateral_amount,
        uint256 indexed lvlusd_amount
    );

    /// @notice Event emitted when funds are redeemed
    event Redeem(
        address redeemer,
        address benefactor,
        address beneficiary,
        address indexed collateral_asset,
        uint256 indexed collateral_amount,
        uint256 indexed lvlusd_amount
    );

    /// @notice Event emitted when reserve wallet is added
    event ReserveWalletAdded(address wallet);

    /// @notice Event emitted when a reserve wallet is removed
    event ReserveWalletRemoved(address wallet);

    /// @notice Event emitted when a supported asset is added
    event AssetAdded(address indexed asset);

    /// @notice Event emitted when a supported asset is removed
    event AssetRemoved(address indexed asset);

    /// @notice Event emitted when a redeemable asset is removed
    event RedeemableAssetRemoved(address indexed asset);

    // @notice Event emitted when a reserve address is added
    event ReserveAddressAdded(address indexed reserve);

    // @notice Event emitted when a reserve address is removed
    event ReserveAddressRemoved(address indexed reserve);

    /// @notice Event emitted when assets are moved to reserve provider wallet
    event ReserveTransfer(
        address indexed wallet,
        address indexed asset,
        uint256 amount
    );

    /// @notice Event emitted when lvlUSD is set
    event lvlUSDSet(address indexed lvlUSD);

    /// @notice Event emitted when the max mint per block is changed
    event MaxMintPerBlockChanged(
        uint256 indexed oldMaxMintPerBlock,
        uint256 indexed newMaxMintPerBlock
    );

    /// @notice Event emitted when the max redeem per block is changed
    event MaxRedeemPerBlockChanged(
        uint256 indexed oldMaxRedeemPerBlock,
        uint256 indexed newMaxRedeemPerBlock
    );

    /// @notice Event emitted when a delegated signer is added, enabling it to sign orders on behalf of another address
    event DelegatedSignerAdded(
        address indexed signer,
        address indexed delegator
    );

    /// @notice Event emitted when a delegated signer is removed
    event DelegatedSignerRemoved(
        address indexed signer,
        address indexed delegator
    );

    event RedeemInitiated(
        address user,
        address token,
        uint collateral_amount,
        uint lvlusd_amount
    );

    event RedeemCompleted(
        address user,
        address token,
        uint collateral_amount,
        uint lvlusd_amount
    );
}
