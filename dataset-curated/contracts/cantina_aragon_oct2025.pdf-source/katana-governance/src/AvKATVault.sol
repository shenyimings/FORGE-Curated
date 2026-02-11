// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { IERC20Upgradeable as IERC20 } from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import { ERC4626Upgradeable as ERC4626 } from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { ERC721HolderUpgradeable as ERC721Holder } from
    "@openzeppelin/contracts-upgradeable/token/ERC721/utils/ERC721HolderUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { PausableUpgradeable as Pausable } from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";

import { SafeERC20Upgradeable as SafeERC20 } from
    "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

import { VotingEscrow, Lock as LockNFT } from "@setup/GaugeVoterSetup_v1_4_0.sol";

import { DaoAuthorizableUpgradeable as DaoAuthorizable } from
    "@aragon/osx-commons-contracts/src/permission/auth/DaoAuthorizableUpgradeable.sol";
import { IDAO } from "@aragon/osx-commons-contracts/src/dao/IDAO.sol";

import { IStrategyNFT as IStrategy } from "src/interfaces/IStrategyNFT.sol";
import { IVaultNFT } from "src/interfaces/IVaultNFT.sol";
import { console2 as console } from "forge-std/console2.sol";

contract AvKATVault is Initializable, IVaultNFT, ERC721Holder, Pausable, ERC4626, UUPSUpgradeable, DaoAuthorizable {
    using SafeERC20 for IERC20;

    /// @notice bytes32 identifier for admin role functions.
    bytes32 public constant VAULT_ADMIN_ROLE = keccak256("VAULT_ADMIN_ROLE");

    /// @notice bytes32 identifier of sweeper that can withdraw mistakenly depositted funds.
    bytes32 public constant SWEEPER_ROLE = keccak256("SWEEPER_ROLE");

    /// @notice The escrow contract address.
    VotingEscrow public escrow;

    /// @notice The nft contract that escrow mints in exchange of erc20 tokens.
    LockNFT public lockNft;

    /// @notice The strategy contract that holds the master token and handles escrow operations.
    IStrategy public strategy;

    /// @notice The address of default strategy that will handle deposit/withdrawals
    ///         in case custom strategy is set to zero.
    IStrategy public defaultStrategy;

    /// The single tokenId that this vault will hold and
    /// will contain all users' token ids accumulated.
    uint256 public masterTokenId;

    error MasterTokenNotSet();
    error SameStrategyNotAllowed();
    error MinMasterTokenInitAmountTooLow();
    error DefaultStrategyCannotBeZero();

    event StrategySet(address strategy);
    event AssetsDonated(uint256 assets);

    constructor() {
        _disableInitializers();
    }

    /// @param _dao The dao address.
    /// @param _escrow The escrow contract providing the asset and NFT tokens.
    /// @param _defaultStrategy The address of default strategy that handles deposit/withdraws
    ///        In case admin chooses to remove custom strategy.
    /// @param _name The name of the share token minted by this vault.
    /// @param _symbol The symbol of the share token minted by this vault.
    function initialize(
        address _dao,
        address _escrow,
        address _defaultStrategy,
        string memory _name,
        string memory _symbol
    )
        external
        initializer
    {
        __DaoAuthorizableUpgradeable_init(IDAO(_dao));
        __ERC20_init(_name, _symbol);

        escrow = VotingEscrow(_escrow);

        __ERC4626_init(IERC20(escrow.token()));

        lockNft = LockNFT(escrow.lockNFT());

        if (_defaultStrategy == address(0)) {
            revert DefaultStrategyCannotBeZero();
        }

        // Note: `strategy` is not set here since it should only be assigned
        // once the master token is initialized.
        // See `initializeMasterTokenAndStrategy` for details.
        defaultStrategy = IStrategy(_defaultStrategy);

        // Always start with paused state to ensure that deposits/withdrawals can not occur.
        // Once `initializeMasterTokenAndStrategy` is called(which fills in vault), it's safer
        // to unpause at that point to avoid loses with inflation attack situations.
        _pause();
    }

    /// @notice Pauses the contract, disallowing deposits/withdrawals.
    function pause() external auth(VAULT_ADMIN_ROLE) {
        _pause();
    }

    /// @notice Unpauses the contract, allowing deposits/withdrawals.
    function unpause() external auth(VAULT_ADMIN_ROLE) {
        _unpause();
    }

    /// @inheritdoc IVaultNFT
    /// @dev Initializes the vault with a master token and strategy. This function:
    ///      1. Transfers an existing NFT token from sender to become the vault's master token
    ///      2. Mints vault shares to sender proportional to the token's locked amount
    ///      3. Sets the strategy (uses defaultStrategy if _strategy is address(0))
    ///      4. Transfers the master token to the selected strategy for management
    ///
    ///      Requirements:
    ///      - Can only be called once (masterTokenId must be 0)
    ///      - Token must exist (_tokenId != 0) and be owned/approved by sender
    ///      - Token's locked amount must meet minimum threshold for security
    ///      - Caller must have VAULT_ADMIN_ROLE
    ///
    ///      After this call, the vault becomes operational and can accept deposits/withdrawals.
    ///      Until this is called, most vault operations will revert.
    function initializeMasterTokenAndStrategy(
        uint256 _tokenId,
        address _strategy
    )
        public
        virtual
        auth(VAULT_ADMIN_ROLE)
    {
        if (_tokenId == 0) revert TokenIdCannotBeZero();
        if (masterTokenId != 0) revert MasterTokenAlreadySet();

        // To start vault with non-trivial amount to avoid inflation attack,
        // require that `_tokenId` contains at least `minMasterTokenInitAmount()`.
        uint256 assetAmount = _getTokenIdAmount(_tokenId);
        if (assetAmount < minMasterTokenInitAmount()) {
            revert MinMasterTokenInitAmountTooLow();
        }

        uint256 shares = convertToShares(assetAmount);

        // Transfer `_tokenId` from sender and set it to masterTokenId
        lockNft.safeTransferFrom(msg.sender, address(this), _tokenId);
        masterTokenId = _tokenId;

        // If _strategy is zero address, it will use default strategy.
        // This automatically will transfer masterTokenId either
        // to defaultStrategy or sender's passed strategy.
        _setStrategy(_strategy);

        // mint shares to the sender.
        _mint(msg.sender, shares);
    }

    /// @notice Allows to change a strategy contract.
    /// @param _strategy The new strategy contract.
    function setStrategy(address _strategy) public auth(VAULT_ADMIN_ROLE) {
        _setStrategy(_strategy);
    }

    /*//////////////////////////////////////////////////////////////
                        ERC4626 OVERRIDDEN LOGIC
    //////////////////////////////////////////////////////////////*/

    /// @dev Delegates to the active strategy which holds the master token
    ///      and tracks the actual asset amounts.
    /// @return Total amount of underlying assets managed by the vault.
    ///         Returns 0 if no strategy is set (vault not initialized),
    ///         otherwise returns the total locked amount from the strategy's master token.
    function totalAssets() public view virtual override returns (uint256) {
        if (address(strategy) == address(0)) {
            return 0;
        }

        return strategy.totalAssets();
    }

    /// @notice Transfer `assets` from caller to Vault, then to Strategy.
    ///      User must have approved `Vault` for this.
    function _deposit(
        address _caller,
        address _receiver,
        uint256 _assets,
        uint256 _shares
    )
        internal
        virtual
        override
        whenNotPaused
    {
        super._deposit(_caller, _receiver, _assets, _shares);

        // Approve strategy so it can transfer `_assets`.
        IERC20(asset()).approve(address(strategy), _assets);

        // Strategy handles createLock and merge to masterTokenId
        strategy.deposit(_assets);
    }

    /// @notice Overrides withdraw function from ERC4626 to allow
    ///         custom logic through strategy.
    function _withdraw(
        address _caller,
        address _receiver,
        address _owner,
        uint256 _assets,
        uint256 _shares
    )
        internal
        virtual
        override
        whenNotPaused
    {
        _withdrawWithTokenId(_caller, _receiver, _owner, _assets, _shares);
    }

    /*//////////////////////////////////////////////////////////////
                       AvKatVault Functions
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IVaultNFT
    /// @dev Allows deposits even if `_tokenId` is already created in the escrow.
    ///      Shares are minted based on the amount locked for that tokenId in the escrow.
    function depositTokenId(uint256 _tokenId, address _receiver) public virtual whenNotPaused returns (uint256) {
        address sender = _msgSender();
        uint256 assets = _getTokenIdAmount(_tokenId);

        require(assets <= maxDeposit(_receiver), "ERC4626: deposit more than max");
        uint256 shares = previewDeposit(assets);

        // Transfer NFT directly to strategy (not vault)
        // Reverts if the caller does not own a veNFT.
        // If `amount` on tokenId is 0, either merge or withdrawal occurred in which case
        // `transferFrom` will anyways fail.
        lockNft.transferFrom(sender, address(strategy), _tokenId);

        // Strategy handles merge to masterTokenId
        strategy.depositTokenId(_tokenId);

        _mint(_receiver, shares);

        emit Deposit(sender, _receiver, assets, shares);
        emit TokenIdDepositted(_tokenId, sender);

        return shares;
    }

    /// @inheritdoc IVaultNFT
    function withdrawTokenId(
        uint256 _assets,
        address _receiver,
        address _owner
    )
        public
        virtual
        whenNotPaused
        returns (uint256 tokenId)
    {
        uint256 shares = previewWithdraw(_assets);
        return _withdrawWithTokenId(_msgSender(), _receiver, _owner, _assets, shares);
    }

    /// @dev Core withdraw logic that both `_withdraw` and `withdrawTokenId` rely on.
    function _withdrawWithTokenId(
        address _caller,
        address _receiver,
        address _owner,
        uint256 _assets,
        uint256 _shares
    )
        internal
        returns (uint256 tokenId)
    {
        if (_caller != _owner) {
            _spendAllowance(_owner, _caller, _shares);
        }

        _burn(_owner, _shares);

        // Strategy handles split and transfer to receiver
        tokenId = strategy.withdraw(_receiver, _assets);

        emit TokenIdWithdrawn(tokenId, _receiver);
        emit Withdraw(_caller, _receiver, _owner, _assets, _shares);
    }

    /// @notice Allows to donate the assets only without minting shares.
    ///         This increases assets causing each share to cost more.
    /// @param _assets How much to donate.
    function donate(uint256 _assets) public virtual whenNotPaused {
        SafeERC20.safeTransferFrom(IERC20(asset()), _msgSender(), address(this), _assets);

        // Approve strategy so it can transfer `_assets`.
        IERC20(asset()).approve(address(strategy), _assets);

        // Strategy handles createLock and merge to masterTokenId
        strategy.deposit(_assets);

        emit AssetsDonated(_assets);
    }

    /// @inheritdoc IVaultNFT
    function recoverNFT(uint256 _tokenId, address _receiver) external virtual auth(SWEEPER_ROLE) {
        if (_tokenId == masterTokenId) {
            revert CannotTransferMasterToken();
        }

        lockNft.safeTransferFrom(address(this), _receiver, _tokenId);

        emit Sweep(_tokenId, _receiver);
    }

    /// @inheritdoc IVaultNFT
    function minMasterTokenInitAmount() public view virtual returns (uint256) {
        return 1e6;
    }

    /// @dev Internal function to change the vault's active strategy.
    ///      1. Sets new strategy (uses defaultStrategy if _strategy is address(0))
    ///      2. Retrieves master token from old strategy via retireStrategy()
    ///      3. Transfers master token to new strategy via receiveMasterToken()
    ///      Requirements:
    ///      - Master token must be initialized (masterTokenId != 0)
    ///      - New strategy must be different from current strategy
    /// @param _strategy Address of the new strategy contract.
    function _setStrategy(address _strategy) internal virtual {
        address currentStrategy = address(strategy);
        if (currentStrategy == _strategy) {
            revert SameStrategyNotAllowed();
        }

        // If new strategy being set is zero, use the default one.
        strategy = defaultStrategy;

        if (_strategy != address(0)) {
            strategy = IStrategy(_strategy);
        }

        // If the strategy was set, retire it and get masterTokenId back.
        if (currentStrategy != address(0)) {
            IStrategy(currentStrategy).retireStrategy();
        }

        // strategy can only be set if master token was already initialized.
        if (masterTokenId == 0) revert MasterTokenNotSet();

        _sendMasterTokenToStrategy();

        emit StrategySet(address(strategy));
    }

    /// @notice Sends master token to strategy.
    /// @dev Caller's responsibility to ensure that `strategy` and masterTokenId are both set.
    function _sendMasterTokenToStrategy() internal virtual {
        // transfer masterTokenId to new strategy
        lockNft.safeTransferFrom(address(this), address(strategy), masterTokenId);

        // let new strategy what the master token id is
        strategy.receiveMasterToken(masterTokenId);
    }

    /// @notice Returns the amount of ERC20 tokens locked in the escrow for a given token ID.
    /// @dev The current implementation fetches this information from `escrow`, but can be overridden if needed.
    /// @param _tokenId The token ID whose locked token balance is being retrieved.
    function _getTokenIdAmount(uint256 _tokenId) internal view virtual returns (uint256) {
        return escrow.locked(_tokenId).amount;
    }

    // =========== Upgrade Related Functions ===========
    function _authorizeUpgrade(address) internal virtual override auth(VAULT_ADMIN_ROLE) { }

    function implementation() external view returns (address) {
        return _getImplementation();
    }

    /// @dev Reserved storage space to allow for layout changes in the future.
    uint256[45] private __gap;
}
