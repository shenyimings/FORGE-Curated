// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {OFT} from "@layerzerolabs/oft-evm/contracts/OFT.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";


import {ERC20Pausable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";


import "./TransferLimiter.sol";

contract asBTC is TransferLimiter, OFT, AccessControl, ERC20Pausable, ERC20Permit {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant MINTER_AND_BURN_ROLE = keccak256("MINTER_AND_BURN_ROLE");

    constructor(
        string memory _name,
        string memory _symbol,
        TransferLimit[] memory _transferLimitConfigs,
        address _lzEndpoint,
        address _defaultAdmin,
        address _timelockAddress
    ) OFT(_name, _symbol, _lzEndpoint, _defaultAdmin) Ownable(_timelockAddress) ERC20Permit(_name){
        _grantRole(DEFAULT_ADMIN_ROLE, _timelockAddress);
        _grantRole(ADMIN_ROLE, _defaultAdmin);

        _setTransferLimitConfigs(_transferLimitConfigs);

    }

    /**
     * @dev Sets the transfer limit configurations based on TransferLimit array. Only callable by the owner or the rate limiter.
   * @param _transferLimitConfigs An array of TransferLimit structures defining the transfer limits.
   */
    function setTransferLimitConfigs(TransferLimit[] calldata _transferLimitConfigs) external onlyRole(ADMIN_ROLE) {
        _setTransferLimitConfigs(_transferLimitConfigs);
    }

    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    function mint(address to, uint256 amount) external onlyRole(MINTER_AND_BURN_ROLE) {
        require(amount > 0, "ERC20: mint zero amount");
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyRole(MINTER_AND_BURN_ROLE) {
        require(amount > 0, "ERC20: burn zero amount");
        _burn(from, amount);
    }

    function _update(address from, address to, uint256 value) internal virtual override(ERC20, ERC20Pausable) {
        ERC20Pausable._update(from, to, value);
    }

    /**
     * @dev Burns tokens from the sender's specified balance.
     * @param _from The address to debit the tokens from.
     * @param _amountLD The amount of tokens to send in local decimals.
     * @param _minAmountLD The minimum amount to send in local decimals.
     * @param _dstEid The destination chain ID.
     * @return amountSentLD The amount sent in local decimals.
     * @return amountReceivedLD The amount received in local decimals on the remote.
     */

    function _debit(
        address _from,
        uint256 _amountLD,
        uint256 _minAmountLD,
        uint32 _dstEid
    ) internal virtual override returns (uint256 amountSentLD, uint256 amountReceivedLD) {
        // remove dust before checking
        uint256 _amount = _removeDust(_amountLD);
        _checkAndUpdateTransferLimit(_dstEid, _amount, _from);
        return super._debit(_from, _amountLD, _minAmountLD, _dstEid);
    }
}
