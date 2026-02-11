// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.23;

import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {FixedPointMathLib as FPML} from "solady/utils/FixedPointMathLib.sol";

import {fatBERA as FatBERA} from "./fatBERA.sol";

contract StakedFatBERAV2 is ERC4626Upgradeable, PausableUpgradeable, UUPSUpgradeable, AccessControlUpgradeable {
    /* ───────────────────────────────────────────────────────────────────────────
        EVENTS
    ─────────────────────────────────────────────────────────────────────────── */
    event Compounded(uint256 amount);
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

        WBERA.approve(address(fatBERA), type(uint256).max);
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
        exitFee = _exitFee;
    }

    function setTreasury(address _treasury) public onlyRole(ADMIN_ROLE) {
        treasury = _treasury;
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
        if (caller != owner) {
            _spendAllowance(owner, caller, shares);
        }

        // trasury can exit for no fee
        uint256 feeToUse = caller == treasury ? 0 : exitFee;
        // exit fees on the shares
        uint256 exitFeeInShares = FPML.mulDiv(shares, feeToUse, 10000);
        uint256 finalShares = shares - exitFeeInShares;
        // update assets by the same proportion
        uint256 finalAssets = assets - FPML.mulDiv(assets, feeToUse, 10000);

        _transfer(owner, treasury, exitFeeInShares);
        _burn(owner, finalShares);
        SafeERC20.safeTransfer(IERC20(asset()), receiver, finalAssets);

        emit Withdraw(caller, receiver, owner, finalAssets, finalShares);
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
        return super.withdraw(assets, receiver, owner);
    }

    function redeem(uint256 shares, address receiver, address owner) public override whenNotPaused returns (uint256) {
        return super.redeem(shares, receiver, owner);
    }

    /* ───────────────────────────────────────────────────────────────────────────
        PUBLIC VIEW LOGIC
    ─────────────────────────────────────────────────────────────────────────── */
    function previewWithdraw(uint256 assets) public view override returns (uint256) {
        uint256 result = super.previewWithdraw(assets);
        return result - FPML.mulDiv(result, exitFee, 10000);
    }

    /**
     * @dev See {IERC4626-previewRedeem}.
     */
    function previewRedeem(uint256 shares) public view override returns (uint256) {
        uint256 result = super.previewRedeem(shares);
        return result - FPML.mulDiv(result, exitFee, 10000);
    }
}
