// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.25;

import "../interfaces/vaults/IERC4626Vault.sol";
import {VaultControl} from "./VaultControl.sol";

abstract contract ERC4626Vault is VaultControl, ERC4626Upgradeable, IERC4626Vault {
    bytes32[16] private _reserved; // Reserved storage space for backward compatibility.

    /**
     * @notice Initializes the ERC4626 vault with the provided settings, including admin, limits, pause states, and token details.
     * @param _admin The address of the admin to be granted control over the vault.
     * @param _limit The initial deposit limit for the vault.
     * @param _depositPause The initial state of the `depositPause` flag.
     * @param _withdrawalPause The initial state of the `withdrawalPause` flag.
     * @param _depositWhitelist The initial state of the `depositWhitelist` flag.
     * @param _asset The address of the underlying ERC20 asset for the ERC4626 vault.
     * @param _name The name of the ERC20 token representing shares of the vault.
     * @param _symbol The symbol of the ERC20 token representing shares of the vault.
     *
     * @custom:effects
     * - Initializes the vault control settings, including admin, limits, and pause states, via `__initializeVaultControl`.
     * - Initializes the ERC20 token properties with the provided `_name` and `_symbol`.
     * - Initializes the ERC4626 vault with the provided underlying asset (`_asset`).
     *
     * @dev This function is protected by the `onlyInitializing` modifier, ensuring it is only called during the initialization phase of the contract.
     */
    function __initializeERC4626(
        address _admin,
        uint256 _limit,
        bool _depositPause,
        bool _withdrawalPause,
        bool _depositWhitelist,
        address _asset,
        string memory _name,
        string memory _symbol
    ) internal onlyInitializing {
        __initializeVaultControl(_admin, _limit, _depositPause, _withdrawalPause, _depositWhitelist);
        __ERC20_init(_name, _symbol);
        __ERC4626_init(IERC20(_asset));
    }

    /// @inheritdoc IERC4626
    function maxMint(address account)
        public
        view
        virtual
        override(ERC4626Upgradeable, IERC4626)
        returns (uint256)
    {
        uint256 assets = maxDeposit(account);
        if (assets == type(uint256).max) {
            return type(uint256).max;
        }
        return convertToShares(assets);
    }

    /// @inheritdoc IERC4626
    function maxDeposit(address account)
        public
        view
        virtual
        override(ERC4626Upgradeable, IERC4626)
        returns (uint256)
    {
        if (depositPause()) {
            return 0;
        }
        if (depositWhitelist() && !isDepositorWhitelisted(account)) {
            return 0;
        }
        uint256 limit_ = limit();
        if (limit_ == type(uint256).max) {
            return type(uint256).max;
        }
        uint256 assets_ = totalAssets();
        return limit_ >= assets_ ? limit_ - assets_ : 0;
    }

    /// @inheritdoc IERC4626
    function maxWithdraw(address account)
        public
        view
        virtual
        override(ERC4626Upgradeable, IERC4626)
        returns (uint256)
    {
        if (withdrawalPause()) {
            return 0;
        }
        return super.maxWithdraw(account);
    }

    /// @inheritdoc IERC4626
    function maxRedeem(address account)
        public
        view
        virtual
        override(ERC4626Upgradeable, IERC4626)
        returns (uint256)
    {
        if (withdrawalPause()) {
            return 0;
        }
        return super.maxRedeem(account);
    }

    /// @inheritdoc IERC4626Vault
    function deposit(uint256 assets, address receiver, address referral)
        public
        virtual
        returns (uint256 shares)
    {
        shares = deposit(assets, receiver);
        emit ReferralDeposit(assets, receiver, referral);
    }

    /// @inheritdoc IERC4626
    function deposit(uint256 assets, address receiver)
        public
        virtual
        override(ERC4626Upgradeable, IERC4626)
        nonReentrant
        returns (uint256)
    {
        return super.deposit(assets, receiver);
    }

    /// @inheritdoc IERC4626
    function mint(uint256 shares, address receiver)
        public
        virtual
        override(ERC4626Upgradeable, IERC4626)
        nonReentrant
        returns (uint256)
    {
        return super.mint(shares, receiver);
    }

    /// @inheritdoc IERC4626
    function withdraw(uint256 assets, address receiver, address owner)
        public
        virtual
        override(ERC4626Upgradeable, IERC4626)
        nonReentrant
        returns (uint256)
    {
        return super.withdraw(assets, receiver, owner);
    }

    /// @inheritdoc IERC4626
    function redeem(uint256 shares, address receiver, address owner)
        public
        virtual
        override(ERC4626Upgradeable, IERC4626)
        nonReentrant
        returns (uint256)
    {
        return super.redeem(shares, receiver, owner);
    }
}
