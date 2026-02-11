// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title Wrapped RAIN Vault (wRAIN)
/// @notice
/// - Underlying: reflective / fee-on-transfer RAIN.
/// - Shares: non-reflective ERC20 (wRAIN), ERC4626 interface.
/// - Deposits: user specifies `assets` as max RAIN to pull, vault mints
///   1:1 vs net RAIN received (after tax).
/// - Redeem/withdraw: shares represent pro-rata claim on total RAIN
///   including reflections.
contract WrappedRainVault is ERC4626, ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    /// @param _underlying The reflective RAIN token.
    constructor(IERC20 _underlying)
        ERC20("Wrapped Rain Coin", "WRAIN")
        ERC4626(_underlying)
        Ownable(msg.sender)
    {}

    /// @notice Total underlying RAIN held (includes reflections).
    function totalAssets() public view override returns (uint256) {
        return IERC20(asset()).balanceOf(address(this));
    }

    /// @notice Convert assets -> shares (nominal 1:1).
    /// @dev Deposit actually mints based on net received, so this is an upper bound.
    function convertToShares(uint256 assets)
        public
        pure
        override
        returns (uint256)
    {
        return assets;
    }

    /// @notice Convert shares -> assets (pro-rata claim).
    function convertToAssets(uint256 shares)
        public
        view
        override
        returns (uint256)
    {
        uint256 supply = totalSupply();
        uint256 assets = totalAssets();

        if (supply == 0 || assets == 0) {
            return shares;
        }

        return (shares * assets) / supply;
    }

    /// @notice Preview shares for a deposit of up to `assets` RAIN.
    /// @dev Ignores transfer tax; actual mint is based on net received.
    function previewDeposit(uint256 assets)
        public
        pure
        override
        returns (uint256)
    {
        return convertToShares(assets);
    }

    /// @notice Mint-by-shares is not supported with fee-on-transfer underlying.
    function previewMint(uint256 /*shares*/)
        public
        pure
        override
        returns (uint256)
    {
        return type(uint256).max;
    }

    /// @notice Preview assets received when redeeming `shares`.
    function previewRedeem(uint256 shares)
        public
        view
        override
        returns (uint256)
    {
        return convertToAssets(shares);
    }

    /// @notice Preview shares needed to withdraw `assets` (ceil-rounded).
    function previewWithdraw(uint256 assets)
        public
        view
        override
        returns (uint256)
    {
        uint256 supply = totalSupply();
        uint256 total = totalAssets();

        if (supply == 0 || total == 0) {
            return assets;
        }

        uint256 numerator = assets * supply;
        return (numerator + total - 1) / total;
    }

    // ------------------------------------------------------------------------
    // Limits
    // ------------------------------------------------------------------------

    function maxDeposit(address)
        public
        pure
        override
        returns (uint256)
    {
        return type(uint256).max;
    }

    function maxMint(address)
        public
        pure
        override
        returns (uint256)
    {
        return 0;
    }

    function maxWithdraw(address owner)
        public
        view
        override
        returns (uint256)
    {
        return convertToAssets(balanceOf(owner));
    }

    function maxRedeem(address owner)
        public
        view
        override
        returns (uint256)
    {
        return balanceOf(owner);
    }

    // ------------------------------------------------------------------------
    // Core ERC4626 operations
    // ------------------------------------------------------------------------

    /// @notice Deposit RAIN and mint wRAIN to `receiver`.
    /// @param assets Max RAIN to pull from msg.sender.
    function deposit(uint256 assets, address receiver)
        public
        override
        nonReentrant
        returns (uint256 shares)
    {
        require(assets > 0, "wRAIN: zero assets");
        require(receiver != address(0), "wRAIN: receiver zero");

        IERC20 _asset = IERC20(asset());

        uint256 balanceBefore = totalAssets();
        _asset.safeTransferFrom(msg.sender, address(this), assets);
        uint256 balanceAfter = totalAssets();

        uint256 received = balanceAfter - balanceBefore;
        require(received > 0, "wRAIN: no tokens received");

        shares = received;
        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, received, shares);
    }

    /// @notice Mint by specifying `shares` is disabled.
    function mint(uint256 /*shares*/, address /*receiver*/)
        public
        pure
        override
        returns (uint256)
    {
        revert("wRAIN: mint not supported");
    }

    /// @notice Withdraw `assets` RAIN to `receiver`, burning shares from `owner`.
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    )
        public
        override
        nonReentrant
        returns (uint256 shares)
    {
        require(assets > 0, "wRAIN: zero assets");
        require(receiver != address(0), "wRAIN: receiver zero");
        require(owner != address(0), "wRAIN: owner zero");

        uint256 supply = totalSupply();
        uint256 total = totalAssets();
        require(supply > 0 && total > 0, "wRAIN: empty vault");
        require(total >= assets, "wRAIN: insufficient assets");

        uint256 numerator = assets * supply;
        shares = (numerator + total - 1) / total; // ceil

        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }

        _burn(owner, shares);
        IERC20(asset()).safeTransfer(receiver, assets);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);
    }

    /// @notice Redeem `shares` wRAIN, sending pro-rata RAIN to `receiver`.
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    )
        public
        override
        nonReentrant
        returns (uint256 assets)
    {
        require(shares > 0, "wRAIN: zero shares");
        require(receiver != address(0), "wRAIN: receiver zero");
        require(owner != address(0), "wRAIN: owner zero");

        uint256 supply = totalSupply();
        uint256 total = totalAssets();
        require(supply > 0 && total > 0, "wRAIN: empty vault");

        if (msg.sender != owner) {
            _spendAllowance(owner, msg.sender, shares);
        }

        assets = (shares * total) / supply;

        _burn(owner, shares);
        IERC20(asset()).safeTransfer(receiver, assets);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);
    }
}
