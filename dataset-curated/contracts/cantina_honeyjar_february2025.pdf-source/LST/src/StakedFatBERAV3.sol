// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {FixedPointMathLib as FPML} from "solady/utils/FixedPointMathLib.sol";

import {fatBERA as FatBERA} from "./fatBERA.sol";

contract StakedFatBERAV3 is ERC4626Upgradeable, PausableUpgradeable, UUPSUpgradeable, AccessControlUpgradeable {
    /* ───────────────────────────────────────────────────────────────────────────
        EVENTS
    ─────────────────────────────────────────────────────────────────────────── */
    event Compounded(uint256 amount);
    event ExitFeeUpdated(uint256 oldExitFee, uint256 newExitFee);
    event TreasuryUpdated(address oldTreasury, address newTreasury);
    /* ───────────────────────────────────────────────────────────────────────────
        CONSTANTS
    ─────────────────────────────────────────────────────────────────────────── */

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant ADMIN_ROLE = DEFAULT_ADMIN_ROLE;
    IERC20 public constant WBERA = IERC20(0x6969696969696969696969696969696969696969);

    /* ───────────────────────────────────────────────────────────────────────────
        STORAGE
    ─────────────────────────────────────────────────────────────────────────── */
    FatBERA public fatBERA;
    uint256 public exitFee;
    address public treasury;
    /* ───────────────────────────────────────────────────────────────────────────
        CONSTRUCTOR
    ─────────────────────────────────────────────────────────────────────────── */
    /// @custom:oz-upgrades-unsafe-allow constructor

    constructor() {
        _disableInitializers();
    }
    /* ───────────────────────────────────────────────────────────────────────────
        INITIALIZER
    ─────────────────────────────────────────────────────────────────────────── */

    function initialize(address _owner, address _fatBERA) external initializer {
        fatBERA = FatBERA(_fatBERA);
        __UUPSUpgradeable_init();
        __ERC4626_init(IERC20(_fatBERA));
        __ERC20_init("Extra FatBERA", "xfatBERA");
        __Pausable_init();
        __AccessControl_init();

        _grantRole(ADMIN_ROLE, _owner);

        IERC20(WBERA).approve(address(fatBERA), type(uint256).max);
    }

    function _authorizeUpgrade(address) internal override onlyRole(ADMIN_ROLE) {}
    /* ───────────────────────────────────────────────────────────────────────────
        ADMIN LOGIC
    ─────────────────────────────────────────────────────────────────────────── */

    function pause() public onlyRole(ADMIN_ROLE) {
        _pause();
    }

    function unpause() public onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    function setExitFee(uint256 _exitFee) public onlyRole(ADMIN_ROLE) {
        require(_exitFee < 10000, "invalid fee");
        uint256 old = exitFee;
        exitFee = _exitFee;
        emit ExitFeeUpdated(old, _exitFee);
    }

    function setTreasury(address _treasury) public onlyRole(ADMIN_ROLE) {
        address old = treasury;
        treasury = _treasury;
        emit TreasuryUpdated(old, _treasury);
    }
    /*────────────────────────────────────────────────────────────────────────────
        OPERATOR LOGIC
    ────────────────────────────────────────────────────────────────────────────*/

    function compound() public onlyRole(OPERATOR_ROLE) {
        fatBERA.claimRewards(address(this));
        uint256 amount = fatBERA.deposit(WBERA.balanceOf(address(this)), address(this));
        emit Compounded(amount);
    }
    /*────────────────────────────────────────────────────────────────────────────
        INTERNAL LOGIC
    ────────────────────────────────────────────────────────────────────────────*/

    function _withdraw(address caller, address receiver, address owner, uint256 assets, uint256 shares)
        internal
        override
    {
        uint256 feeToUse = owner == treasury ? 0 : exitFee;

        uint256 feeInShares = _calculateShareFee(shares, feeToUse);
        uint256 sharesAfterFee = shares - feeInShares;
        if (feeInShares > 0 && treasury != address(0) && treasury != address(this)) {
            _transfer(owner, treasury, feeInShares);
        }

        super._withdraw(caller, receiver, owner, assets, sharesAfterFee);
    }

    /*────────────────────────────────────────────────────────────────────────────
        FEE CALCULATION HELPER
    ────────────────────────────────────────────────────────────────────────────*/

    /// @dev Calculates fee on shares, rounded up to favor the vault, mirroring OZ's Math.Rounding.Ceil.
    function _calculateShareFee(uint256 shares, uint256 feeBasisPoints) private pure returns (uint256) {
        if (feeBasisPoints == 0 || shares == 0) return 0;
        return FPML.mulDivUp(shares, feeBasisPoints, 10000);
    }
    /* ───────────────────────────────────────────────────────────────────────────
        PUBLIC LOGIC
    ─────────────────────────────────────────────────────────────────────────── */

    function deposit(uint256 assets, address receiver) public override whenNotPaused returns (uint256) {
        return super.deposit(assets, receiver);
    }

    function mint(uint256 shares, address receiver) public override whenNotPaused returns (uint256) {
        return super.mint(shares, receiver);
    }

    function withdraw(uint256 assets, address receiver, address owner)
        public
        override
        whenNotPaused
        returns (uint256)
    {
        if (owner == treasury) {
            uint256 maxAssets = maxWithdraw(owner);
            require(assets <= maxAssets, "ERC4626: withdraw more than max");

            // Use rounding up to ensure at least 1 share is burned for any non-zero asset amount
            uint256 shares = _convertToShares(assets, Math.Rounding.Ceil);
            _withdraw(_msgSender(), receiver, owner, assets, shares);

            return shares;
        }
        return super.withdraw(assets, receiver, owner);
    }

    function redeem(uint256 shares, address receiver, address owner) public override whenNotPaused returns (uint256) {
        if (owner == treasury) {
            uint256 maxShares = maxRedeem(owner);
            require(shares <= maxShares, "ERC4626: redeem more than max");

            uint256 assets = _convertToAssets(shares, Math.Rounding.Ceil);
            _withdraw(_msgSender(), receiver, owner, assets, shares);

            return assets;
        }
        return super.redeem(shares, receiver, owner);
    }

    /// @dev Override to account for share-based exit fees so that
    /// assets <= maxWithdraw(owner) is guaranteed not to revert for non-treasury users.
    function maxWithdraw(address owner) public view override returns (uint256) {
        if (owner == treasury) {
            return super.maxWithdraw(owner);
        }
        uint256 userShares = balanceOf(owner);
        if (userShares == 0) return 0;
        return previewRedeem(userShares);
    }

    /* ───────────────────────────────────────────────────────────────────────────
        PUBLIC VIEW LOGIC
    ─────────────────────────────────────────────────────────────────────────── */
    /**
     * @dev See {IERC4626-previewWithdraw}.
     * Returns shares needed to withdraw the specified NET assets (after fees).
     * The user specifies what they want to receive, we calculate total shares needed.
     */
    function previewWithdraw(uint256 assets) public view override returns (uint256) {
        uint256 sharesNeeded = super.previewWithdraw(assets);
        if (exitFee == 0) return sharesNeeded;
        return FPML.mulDivUp(sharesNeeded, 10000, 10000 - exitFee);
    }

    /**
     * @dev See {IERC4626-previewRedeem}. 
     * Returns the NET assets after fees - what the user will actually receive.
     */
    function previewRedeem(uint256 shares) public view override returns (uint256) {
        if (exitFee == 0) return super.previewRedeem(shares);

        uint256 feeInShares = _calculateShareFee(shares, exitFee);
        uint256 sharesAfterFee = shares - feeInShares;
        return super.previewRedeem(sharesAfterFee);
    }
}
