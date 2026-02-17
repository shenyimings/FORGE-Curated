// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { Access } from "../access/Access.sol";

import { IStakedCap } from "../interfaces/IStakedCap.sol";
import { StakedCapStorageUtils } from "../storage/StakedCapStorageUtils.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ERC20PermitUpgradeable } from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {
    ERC20Upgradeable,
    ERC4626Upgradeable
} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import { IERC20, IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/// @title Staked Cap Token
/// @author kexley, @capLabs
/// @notice Slow releasing yield-bearing token that distributes the yield accrued from agents
/// borrowing from the underlying assets.
/// @dev Calling notify permissionlessly will start the linear unlock
contract StakedCap is
    IStakedCap,
    UUPSUpgradeable,
    ERC4626Upgradeable,
    ERC20PermitUpgradeable,
    Access,
    StakedCapStorageUtils
{
    /// @dev Disable initializers on the implementation
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialize the staked cap token by matching the name and symbol of the underlying
    /// @param _accessControl Address of the access control
    /// @param _asset Address of the cap token
    /// @param _lockDuration Duration in seconds for profit locking
    function initialize(address _accessControl, address _asset, uint256 _lockDuration) external initializer {
        string memory _name = string.concat("s", IERC20Metadata(_asset).name());
        string memory _symbol = string.concat("s", IERC20Metadata(_asset).symbol());

        __ERC4626_init(IERC20(_asset));
        __ERC20_init(_name, _symbol);
        __ERC20Permit_init(_name);
        __Access_init(_accessControl);
        __UUPSUpgradeable_init();
        getStakedCapStorage().lockDuration = _lockDuration;
    }

    /// @notice Override the decimals function to match underlying decimals
    /// @return _decimals Decimals of the staked cap token
    function decimals() public view override(ERC20Upgradeable, ERC4626Upgradeable) returns (uint8 _decimals) {
        _decimals = ERC4626Upgradeable.decimals();
    }

    /// @notice Notify the yield to start vesting
    function notify() external {
        uint256 total = IERC20(asset()).balanceOf(address(this));
        StakedCapStorage storage $ = getStakedCapStorage();
        if (total > $.storedTotal) {
            uint256 diff = total - $.storedTotal;
            $.totalLocked = lockedProfit() + diff;
            $.storedTotal = total;
            $.lastNotify = block.timestamp;

            emit Notify(msg.sender, diff);
        }
    }

    /// @notice Remaining locked profit after a notification
    /// @return locked Amount remaining to be vested
    function lockedProfit() public view returns (uint256 locked) {
        StakedCapStorage storage $ = getStakedCapStorage();
        if ($.lockDuration == 0) return 0;
        uint256 elapsed = block.timestamp - $.lastNotify;
        uint256 remaining = elapsed < $.lockDuration ? $.lockDuration - elapsed : 0;
        locked = $.totalLocked * remaining / $.lockDuration;
    }

    /// @notice Total vested cap tokens on this contract
    /// @return total Total amount of vested cap tokens
    function totalAssets() public view override returns (uint256 total) {
        total = getStakedCapStorage().storedTotal - lockedProfit();
    }

    /// @dev Overridden to update the total assets including unvested tokens
    /// @param _caller Caller of the deposit
    /// @param _receiver Receiver of the staked cap tokens
    /// @param _assets Amount of cap tokens to pull from the caller
    /// @param _shares Amount of staked cap tokens to send to receiver
    function _deposit(address _caller, address _receiver, uint256 _assets, uint256 _shares) internal override {
        super._deposit(_caller, _receiver, _assets, _shares);
        getStakedCapStorage().storedTotal += _assets;
    }

    /// @dev Overridden to reduce the total assets including unvested tokens
    /// @param _caller Caller of the withdrawal
    /// @param _receiver Receiver of the cap tokens
    /// @param _owner Owner of the staked cap tokens being burnt
    /// @param _assets Amount of cap tokens to send to the receiver
    /// @param _shares Amount of staked cap tokens to burn from the owner
    function _withdraw(address _caller, address _receiver, address _owner, uint256 _assets, uint256 _shares)
        internal
        override
    {
        super._withdraw(_caller, _receiver, _owner, _assets, _shares);
        getStakedCapStorage().storedTotal -= _assets;
    }

    /// @dev Only admin can upgrade implementation
    function _authorizeUpgrade(address) internal view override checkAccess(bytes4(0)) { }
}
