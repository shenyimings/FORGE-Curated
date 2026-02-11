// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { OFTUpgradeable } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oft/OFTUpgradeable.sol";
import { FreezeThawModule } from "contracts/modules/FreezeThawModule.sol";
import { PauseModule } from "contracts/modules/PauseModule.sol";
import { EIP3009Module } from "contracts/modules/EIP3009Module.sol";
import { PermitModule } from "contracts/modules/PermitModule.sol";
import { SendParam } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oft/interfaces/IOFT.sol";
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

contract FrxUSDOFTUpgradeable is OFTUpgradeable, EIP3009Module, PermitModule, FreezeThawModule, PauseModule {
    constructor(address _lzEndpoint) OFTUpgradeable(_lzEndpoint) {
        _disableInitializers();
    }

    function version() public pure returns (string memory) {
        return "1.1.0";
    }
    
    /// @dev overrides state where previous OFT versions were named the legacy "FRAX"
    function name() public pure override returns (string memory) {
        return "Frax USD";
    }

    /// @dev overrides state where previous OFT versions were named the legacy "FRAX"
    function symbol() public pure override returns (string memory) {
        return "frxUSD";
    }

    // Admin

    /// @dev This method is called specifically when deploying a new OFT
    function initialize(address _delegate) external reinitializer(3) {
        __OFT_init(name(), symbol(), _delegate);
        __EIP712_init(name(), version());
        
        __Ownable_init();
        _transferOwnership(_delegate);
    }
        
    /// @dev This method is called specifically when upgrading an existing OFT
    function initializeV110() external reinitializer(3) {
        __EIP712_init(name(), version());
    }

    /// @notice External admin gated function to add a freezer role to an account
    /// @param account The account to be added as a freezer
    /// @dev Added in v1.1.0
    function addFreezer(address account) external onlyOwner {
        _addFreezer(account);
    }

    /// @notice External admin gated function to remove a freezer role from an account
    /// @param account The account to be removed as a freezer
    /// @dev Added in v1.1.0
    function removeFreezer(address account) external onlyOwner {
        _removeFreezer(account);
    }

    /// @notice External admin gated function to unfreeze a set of accounts
    /// @param accounts Array of accounts to be unfrozen
    /// @dev Added in v1.1.0
    function thawMany(address[] memory accounts) external onlyOwner {
        _thawMany(accounts);
    }

    /// @notice External admin gated function to unfreeze an account
    /// @param account The account to be unfrozen
    /// @dev Added in v1.1.0
    function thaw(address account) external onlyOwner {
        _thaw(account);
    }

    /// @notice External admin gated function to batch freeze a set of accounts
    /// @param accounts Array of accounts to be frozen
    /// @dev Added in v1.1.0
    function freezeMany(address[] memory accounts) external {
        if (!isFreezer(msg.sender) && msg.sender != owner()) revert NotFreezer();
        _freezeMany(accounts);
    }

    /// @notice External admin gated function to freeze a given account
    /// @param account The account to be
    /// @dev Added in v1.1.0
    function freeze(address account) external {
        if (!isFreezer(msg.sender) && msg.sender != owner()) revert NotFreezer();
        _freeze(account);
    }

    /// @notice External admin gated function to batch burn balance from a set of accounts
    /// @param accounts Array of accounts whose balances will be burned
    /// @param amounts Array of amounts corresponding to the balances to be burned
    /// @dev Added in v1.1.0
    /// @dev if `amount` == 0, entire balance will be burned
    function burnMany(address[] memory accounts, uint256[] memory amounts) external onlyOwner {
        uint lenOwner = accounts.length;
        if (accounts.length != amounts.length) revert ArrayMisMatch();
        for (uint i; i < lenOwner; ++i) {
            if (amounts[i] == 0) amounts[i] = balanceOf(accounts[i]);
            _burn(accounts[i], amounts[i]);
        }
    }

    /// @notice External admin gated function to burn balance from a given account
    /// @param account  The account whose balance will be burned
    /// @param amount The amount of balance to burn
    /// @dev Added in v1.1.0
    /// @dev if `amount` == 0, entire balance will be burned
    function burn(address account, uint256 amount) external onlyOwner {
        if (amount == 0) amount = balanceOf(account);
        _burn(account, amount);
    }

    /// @notice External admin gated pause function
    /// @dev Added in v1.1.0
    function pause() external onlyOwner {
        _pause();
    }

    /// @notice External admin gated unpause function
    /// @dev Added in v1.1.0
    function unpause() external onlyOwner {
        _unpause();
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        if (msg.sender != owner()) {
            if (
                isPaused() ||
                isFrozen(to) || isFrozen(from) || isFrozen(msg.sender)
            ) revert BeforeTokenTransferBlocked();
        }
        super._beforeTokenTransfer(from, to, amount);
    }

    // Helper views

    function toLD(uint64 _amountSD) external view returns (uint256 amountLD) {
        return _toLD(_amountSD);
    }

    function toSD(uint256 _amountLD) external view returns (uint64 amountSD) {
        return _toSD(_amountLD);
    }

    function removeDust(uint256 _amountLD) public view returns (uint256 amountLD) {
        return _removeDust(_amountLD);
    }

    function debitView(uint256 _amountLD, uint256 _minAmountLD, uint32 _dstEid) external view returns (uint256 amountSentLD, uint256 amountReceivedLD) {
        /// @dev: _dstEid is unused in _debitView
        return _debitView(_amountLD, _minAmountLD, _dstEid);
    }

    function buildMsgAndOptions(
        SendParam calldata _sendParam,
        uint256 _amountLD
    ) external view returns (bytes memory message, bytes memory options) {
        return _buildMsgAndOptions(_sendParam, _amountLD);
    }

    //==============================================================================
    // Overrides
    //==============================================================================

    /// @dev supports EIP3009
    function _transfer(address from, address to, uint256 amount) internal override(EIP3009Module, ERC20Upgradeable) {
        return ERC20Upgradeable._transfer(from, to, amount);
    }

    /// @dev supports EIP2612
    function _approve(address owner, address spender, uint256 amount) internal override(PermitModule, ERC20Upgradeable) {
        return ERC20Upgradeable._approve(owner, spender, amount);
    }
    
    /* ========== ERRORS ========== */
    error ArrayMisMatch();
    error BeforeTokenTransferBlocked();
}
