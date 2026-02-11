// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

import { SafeERC20, IERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { IBridgeCoordinatorL1Outbound } from "../interfaces/IBridgeCoordinatorL1Outbound.sol";
import { IGenericShare } from "../interfaces/IGenericShare.sol";
import { IERC7575Vault } from "../interfaces/IERC7575Vault.sol";
import { IWhitelabeledUnit } from "../interfaces/IWhitelabeledUnit.sol";

/**
 * @title GenericDepositor
 * @notice Helper contract to automate deposits into the GUSD vault system
 * @dev Users must approve this contract to spend their assets before calling deposit/mint functions
 * The contract automatically resolves the correct vault for each asset type
 * and handles all necessary approvals and transfers on behalf of users.
 */
contract GenericDepositor {
    using SafeERC20 for IERC20;

    /**
     *  @notice The Generic unit token that represents shares across all vaults
     */
    IGenericShare public immutable unitToken;
    /**
     * @notice The bridge coordinator for cross-chain operations
     */
    IBridgeCoordinatorL1Outbound public immutable bridgeCoordinator;

    /**
     * @dev Thrown when no vault exists for the specified asset
     */
    error NoVaultForAsset();
    /**
     * @dev Thrown when the vault's asset doesn't match the provided asset
     */
    error AssetMismatch();
    /**
     * @dev Thrown when zero assets are specified for deposit
     */
    error ZeroAssets();
    /**
     * @dev Thrown when zero shares are specified for minting
     */
    error ZeroShares();
    /**
     * @dev Thrown when the receiver address is zero
     */
    error ZeroReceiver();
    /**
     * @dev Thrown when the actual mint amount doesn't match the expected amount
     */
    error MintAmountMismatch();

    /**
     * @dev Initializes the GenericDepositor with required contract references
     * @param _unitToken The Generic unit token contract
     * @param _bridgeCoordinator The bridge coordinator for cross-chain operations
     */
    constructor(IGenericShare _unitToken, IBridgeCoordinatorL1Outbound _bridgeCoordinator) {
        unitToken = _unitToken;
        bridgeCoordinator = _bridgeCoordinator;
    }

    /**
     * @notice Deposits assets into the appropriate vault and mints shares to the caller
     * @dev Automatically resolves the correct vault for the given asset
     * @param asset The ERC20 token to deposit (USDC, USDT, or USDS)
     * @param whitelabel The whitelabeled unit token address, or address(0) for standard units
     * @param assets The amount of assets to deposit
     * @return shares The number of shares minted to the caller
     */
    function deposit(IERC20 asset, address whitelabel, uint256 assets) external returns (uint256 shares) {
        shares = _deposit(asset, whitelabel, assets, msg.sender);
    }

    /**
     * @notice Mints a specific amount of shares by depositing the required assets
     * @dev Calculates the required asset amount using previewMint and deposits that amount
     * @param asset The ERC20 token to deposit (USDC, USDT, or USDS)
     * @param whitelabel The whitelabeled unit token address, or address(0) for standard units
     * @param shares The exact number of shares to mint
     * @return assets The amount of assets that were deposited
     */
    function mint(IERC20 asset, address whitelabel, uint256 shares) external returns (uint256 assets) {
        assets = _mint(asset, whitelabel, shares, msg.sender);
    }

    /**
     * @notice Deposits assets and immediately bridges the resulting shares to another chain
     * @dev Combines deposit and bridge operations in a single transaction
     * @param asset The ERC20 token to deposit (USDC, USDT, or USDS)
     * @param assets The amount of assets to deposit
     * @param bridgeType The type of bridge to use
     * @param chainId The destination chain ID
     * @param remoteRecipient The recipient address on the destination chain (as bytes32)
     * @param bridgeParams Additional parameters required by the bridge
     * @return shares The number of shares minted
     * @return messageId The bridge message ID for tracking
     */
    function depositAndBridge(
        IERC20 asset,
        uint256 assets,
        uint16 bridgeType,
        uint256 chainId,
        bytes32 remoteRecipient,
        bytes32 whitelabel,
        bytes calldata bridgeParams
    )
        external
        payable
        returns (uint256 shares, bytes32 messageId)
    {
        shares = _deposit(asset, address(0), assets, address(this));
        messageId = _bridge(bridgeType, chainId, msg.sender, remoteRecipient, whitelabel, shares, bridgeParams);
    }

    /**
     * @notice Mints a specific amount of shares and immediately bridges them to another chain
     * @dev Combines mint and bridge operations in a single transaction
     * @param asset The ERC20 token to deposit (USDC, USDT, or USDS)
     * @param shares The exact number of shares to mint
     * @param bridgeType The type of bridge to use
     * @param chainId The destination chain ID
     * @param remoteRecipient The recipient address on the destination chain (as bytes32)
     * @param whitelabel The whitelabeled unit token address on the destination chain
     * @param bridgeParams Additional parameters required by the bridge
     * @return assets The amount of assets that were deposited
     * @return messageId The bridge message ID for tracking
     */
    function mintAndBridge(
        IERC20 asset,
        uint256 shares,
        uint16 bridgeType,
        uint256 chainId,
        bytes32 remoteRecipient,
        bytes32 whitelabel,
        bytes calldata bridgeParams
    )
        external
        payable
        returns (uint256 assets, bytes32 messageId)
    {
        assets = _mint(asset, address(0), shares, address(this));
        messageId = _bridge(bridgeType, chainId, msg.sender, remoteRecipient, whitelabel, shares, bridgeParams);
    }

    /**
     * @notice Deposits assets and predeposits the resulting shares for later bridging
     * @dev Predeposited shares can be bridged later via the bridge coordinator
     * @param asset The ERC20 token to deposit (USDC, USDT, or USDS)
     * @param assets The amount of assets to deposit
     * @param chainNickname A human-readable identifier for the destination chain
     * @param remoteRecipient The recipient address on the destination chain (as bytes32)
     * @return shares The number of shares minted and predeposited
     */
    function depositAndPredeposit(
        IERC20 asset,
        uint256 assets,
        bytes32 chainNickname,
        bytes32 remoteRecipient
    )
        external
        returns (uint256 shares)
    {
        shares = _deposit(asset, address(0), assets, address(this));
        _predeposit(chainNickname, msg.sender, remoteRecipient, shares);
    }

    /**
     * @notice Mints a specific amount of shares and predeposits them for later bridging
     * @dev Predeposited shares can be bridged later via the bridge coordinator
     * @param asset The ERC20 token to deposit (USDC, USDT, or USDS)
     * @param shares The exact number of shares to mint
     * @param chainNickname A human-readable identifier for the destination chain
     * @param remoteRecipient The recipient address on the destination chain (as bytes32)
     * @return assets The amount of assets that were deposited
     */
    function mintAndPredeposit(
        IERC20 asset,
        uint256 shares,
        bytes32 chainNickname,
        bytes32 remoteRecipient
    )
        external
        returns (uint256 assets)
    {
        assets = _mint(asset, address(0), shares, address(this));
        _predeposit(chainNickname, msg.sender, remoteRecipient, shares);
    }

    /**
     * @dev Internal function to handle asset deposits into the appropriate vault
     * @param asset The ERC20 token to deposit
     * @param whitelabel The whitelabeled unit token address, or address(0) for standard units
     * @param assets The amount of assets to deposit
     * @param receiver The address that will receive the minted shares
     * @return shares The number of shares minted
     */
    function _deposit(
        IERC20 asset,
        address whitelabel,
        uint256 assets,
        address receiver
    )
        internal
        returns (uint256 shares)
    {
        IERC7575Vault vault = IERC7575Vault(unitToken.vault(address(asset)));
        require(address(vault) != address(0), NoVaultForAsset());
        require(vault.asset() == address(asset), AssetMismatch());
        require(assets > 0, ZeroAssets());
        require(receiver != address(0), ZeroReceiver());

        asset.safeTransferFrom(msg.sender, address(this), assets);
        asset.forceApprove(address(vault), assets);

        if (whitelabel == address(0)) {
            shares = IERC7575Vault(vault).deposit(assets, receiver);
        } else {
            shares = IERC7575Vault(vault).deposit(assets, address(this));
            IERC20(unitToken).forceApprove(whitelabel, shares);
            IWhitelabeledUnit(whitelabel).wrap(receiver, shares);

            // Note: If whitelabel contract is malicious and doesn't pull the expected amount of shares,
            // the shares stay in the depositor contract, effectively locking them.
            // This does not affect the vault, the underlying assets, or other users.
        }
    }

    /**
     * @dev Internal function to mint a specific amount of shares by depositing assets
     * @param asset The ERC20 token to deposit
     * @param whitelabel The whitelabeled unit token address, or address(0) for standard units
     * @param shares The exact number of shares to mint
     * @param receiver The address that will receive the minted shares
     * @return assets The amount of assets that were deposited
     */
    function _mint(
        IERC20 asset,
        address whitelabel,
        uint256 shares,
        address receiver
    )
        internal
        returns (uint256 assets)
    {
        IERC7575Vault vault = IERC7575Vault(unitToken.vault(address(asset)));
        require(address(vault) != address(0), NoVaultForAsset());
        require(vault.asset() == address(asset), AssetMismatch());
        require(shares > 0, ZeroShares());
        require(receiver != address(0), ZeroReceiver());

        assets = vault.previewMint(shares);

        asset.safeTransferFrom(msg.sender, address(this), assets);
        asset.forceApprove(address(vault), assets);

        if (whitelabel == address(0)) {
            require(vault.mint(shares, receiver) == assets, MintAmountMismatch());
        } else {
            require(vault.mint(shares, address(this)) == assets, MintAmountMismatch());
            IERC20(unitToken).forceApprove(whitelabel, shares);
            IWhitelabeledUnit(whitelabel).wrap(receiver, shares);

            // Note: If whitelabel contract is malicious and doesn't pull the expected amount of shares,
            // the shares stay in the depositor contract, effectively locking them.
            // This does not affect the vault, the underlying assets, or other users.
        }
    }

    /**
     * @dev Internal function to bridge Generic units to another chain
     * @param bridgeType The type of bridge to use
     * @param chainId The destination chain ID
     * @param onBehalf The address initiating the bridge operation
     * @param remoteRecipient The recipient address on the destination chain
     * @param whitelabel The whitelabeled unit token address on the destination chain
     * @param units The number of units to bridge
     * @param bridgeParams Additional parameters required by the bridge
     * @return messageId The bridge message ID for tracking
     */
    function _bridge(
        uint16 bridgeType,
        uint256 chainId,
        address onBehalf,
        bytes32 remoteRecipient,
        bytes32 whitelabel,
        uint256 units,
        bytes calldata bridgeParams
    )
        internal
        returns (bytes32 messageId)
    {
        IERC20(unitToken).forceApprove(address(bridgeCoordinator), units);
        messageId = bridgeCoordinator.bridge{ value: msg.value }(
            bridgeType, chainId, onBehalf, remoteRecipient, address(0), whitelabel, units, bridgeParams
        );
    }

    /**
     * @dev Internal function to predeposit Generic units for later bridging
     * @param chainNickname A human-readable identifier for the destination chain
     * @param onBehalf The address initiating the predeposit operation
     * @param remoteRecipient The recipient address on the destination chain
     * @param units The number of units to predeposit
     */
    function _predeposit(
        bytes32 chainNickname,
        address onBehalf,
        bytes32 remoteRecipient,
        uint256 units
    )
        internal
    {
        IERC20(unitToken).forceApprove(address(bridgeCoordinator), units);
        bridgeCoordinator.predeposit(chainNickname, onBehalf, remoteRecipient, units);
    }
}
