// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import { OFTUpgradeable } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oft/OFTUpgradeable.sol";
import { SendParam } from "@fraxfinance/layerzero-v2-upgradeable/oapp/contracts/oft/interfaces/IOFT.sol";

import {EIP3009Module} from "contracts/modules/EIP3009Module.sol";
import {PermitModule} from "contracts/modules/PermitModule.sol";

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

contract SFrxUSDOFTUpgradeable is OFTUpgradeable, EIP3009Module, PermitModule {
    constructor(address _lzEndpoint) OFTUpgradeable(_lzEndpoint) {
        _disableInitializers();
    }

   function version() public pure returns (string memory) {
        return "1.1.0";
    }

    // Admin
    /// @dev This method is called specifically when upgrading an existing OFT
    function initializeV110() external reinitializer(3) {
        __EIP712_init(name(), version());
    }


    function name() public pure override returns (string memory) {
        return "Staked Frax USD";
    }

    function symbol() public pure override returns (string memory) {
        return "sfrxUSD";
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
}
