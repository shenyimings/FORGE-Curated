// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ERC20, ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import { OAppMessenger } from "./OAppMessenger.sol";

/// @title PreMainnetVault
/// @author @capLabs
/// @notice Vault for pre-mainnet campaign
/// @dev Underlying asset is deposited on this contract and LayerZero is used to bridge across a
/// minting message to the testnet. The campaign has a maximum timestamp after which transfers are
/// enabled to prevent the owner from unduly locking assets.
contract PreMainnetVault is ERC20Permit, OAppMessenger {
    using SafeERC20 for IERC20Metadata;

    /// @notice Underlying asset
    IERC20Metadata public immutable asset;

    /// @notice Underlying asset decimals
    uint8 private immutable assetDecimals;

    /// @notice Maximum end timestamp for the campaign after which transfers are enabled
    uint256 public immutable maxCampaignEnd;

    /// @dev Bool for if the transfers are unlocked before the campaign ends
    bool private unlocked;

    /// @dev Zero amounts are not allowed for minting
    error ZeroAmount();

    /// @dev Zero addresses are not allowed for minting
    error ZeroAddress();

    /// @dev Transfers not yet enabled
    error TransferNotEnabled();

    /// @dev The campaign has ended
    error CampaignEnded();

    /// @dev Deposit underlying asset
    event Deposit(address indexed user, uint256 amount);

    /// @dev Withdraw underlying asset
    event Withdraw(address indexed user, uint256 amount);

    /// @dev Transfers enabled
    event TransferEnabled();

    /// @dev Initialize the token with the underlying asset and bridge info
    /// @param _asset Underlying asset
    /// @param _lzEndpoint Local layerzero endpoint
    /// @param _dstEid Destination lz EID
    /// @param _maxCampaignLength Max campaign length in seconds
    constructor(address _asset, address _lzEndpoint, uint32 _dstEid, uint256 _maxCampaignLength)
        ERC20("Boosted cUSD", "bcUSD")
        ERC20Permit("Boosted cUSD")
        OAppMessenger(_lzEndpoint, _dstEid, IERC20Metadata(_asset).decimals())
        Ownable(msg.sender)
    {
        asset = IERC20Metadata(_asset);
        assetDecimals = asset.decimals();
        maxCampaignEnd = block.timestamp + _maxCampaignLength;
    }

    /// @notice Deposit underlying asset to mint cUSD on MegaETH Testnet
    /// @param _amount Amount of underlying asset to deposit
    /// @param _destReceiver Receiver of the assets on MegaETH Testnet
    /// @param _refundAddress The address to receive any excess fee values sent to the endpoint if the call fails on the destination chain
    function deposit(uint256 _amount, address _destReceiver, address _refundAddress) external payable {
        if (_amount == 0) revert ZeroAmount();
        if (_destReceiver == address(0)) revert ZeroAddress();

        if (transferEnabled()) revert CampaignEnded();

        asset.safeTransferFrom(msg.sender, address(this), _amount);

        _mint(msg.sender, _amount);

        _sendMessage(_destReceiver, _amount, _refundAddress);

        emit Deposit(msg.sender, _amount);
    }

    /// @notice Withdraw underlying asset after campaign ends
    /// @param _amount Amount of underlying asset to withdraw
    /// @param _receiver Receiver of the withdrawn underlying assets
    function withdraw(uint256 _amount, address _receiver) external {
        if (_amount == 0) revert ZeroAmount();
        if (_receiver == address(0)) revert ZeroAddress();

        _burn(msg.sender, _amount);

        asset.safeTransfer(_receiver, _amount);

        emit Withdraw(msg.sender, _amount);
    }

    /// @notice Override decimals to return decimals of underlying asset
    /// @return decimals Asset decimals
    function decimals() public view override returns (uint8) {
        return assetDecimals;
    }

    /// @notice Transfers enabled
    /// @return enabled Bool for whether transfers are enabled
    function transferEnabled() public view returns (bool enabled) {
        enabled = unlocked || block.timestamp > maxCampaignEnd;
    }

    /// @notice Enable transfers before campaign ends
    function enableTransfer() external onlyOwner {
        unlocked = true;
        emit TransferEnabled();
    }

    /// @dev Override _update to disable transfer before campaign ends
    /// @param _from From address
    /// @param _to To address
    /// @param _value Amount to transfer
    function _update(address _from, address _to, uint256 _value) internal override {
        if (!transferEnabled() && _from != address(0)) revert TransferNotEnabled();
        super._update(_from, _to, _value);
    }
}
