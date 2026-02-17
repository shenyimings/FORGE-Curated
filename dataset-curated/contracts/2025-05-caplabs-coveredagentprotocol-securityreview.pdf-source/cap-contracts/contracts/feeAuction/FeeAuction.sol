// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { Access } from "../access/Access.sol";

import { IAuctionCallback } from "../interfaces/IAuctionCallback.sol";

import { IFeeAuction } from "../interfaces/IFeeAuction.sol";
import { FeeAuctionStorageUtils } from "../storage/FeeAuctionStorageUtils.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { IERC20, SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title Fee Auction
/// @author kexley, @capLabs
/// @notice Fees are sold via a dutch auction
contract FeeAuction is IFeeAuction, UUPSUpgradeable, Access, FeeAuctionStorageUtils {
    using SafeERC20 for IERC20;

    /// @dev Disable initializers on the implementation
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialize the fee auction
    /// @param _accessControl Access control address
    /// @param _paymentToken Payment token address
    /// @param _paymentRecipient Payment recipient address
    /// @param _duration Duration of auction in seconds
    /// @param _minStartPrice Minimum start price in payment token decimals
    function initialize(
        address _accessControl,
        address _paymentToken,
        address _paymentRecipient,
        uint256 _duration,
        uint256 _minStartPrice
    ) external initializer {
        __Access_init(_accessControl);
        __UUPSUpgradeable_init();

        FeeAuctionStorage storage $ = get();
        $.paymentToken = _paymentToken;
        $.paymentRecipient = _paymentRecipient;
        $.startPrice = _minStartPrice;
        $.startTimestamp = block.timestamp;
        if (_duration == 0) revert NoDuration();
        $.duration = _duration;
        $.minStartPrice = _minStartPrice;
    }

    /// @notice Current price in the payment token, linearly decays toward 0 over time
    /// @return price Current price
    function currentPrice() public view returns (uint256 price) {
        FeeAuctionStorage storage $ = get();
        uint256 elapsed = block.timestamp - $.startTimestamp;
        if (elapsed > $.duration) elapsed = $.duration;
        price = $.startPrice * (1e27 - (elapsed * 1e27 / $.duration)) / 1e27;
    }

    /// @notice Buy fees in exchange for the payment token
    /// @dev Starts new auction where start price is double the settled price of this one
    /// @param _assets Assets to buy
    /// @param _receiver Receiver address for the assets
    /// @param _callback Optional callback data
    function buy(address[] calldata _assets, address _receiver, bytes calldata _callback) external {
        uint256 price = currentPrice();
        FeeAuctionStorage storage $ = get();
        $.startTimestamp = block.timestamp;

        uint256 newStartPrice = price * 2;
        if (newStartPrice < $.minStartPrice) newStartPrice = $.minStartPrice;
        $.startPrice = newStartPrice;

        uint256[] memory balances = _transferOutAssets(_assets, _receiver);

        if (_callback.length > 0) IAuctionCallback(msg.sender).auctionCallback(_assets, balances, price, _callback);

        IERC20($.paymentToken).safeTransferFrom(msg.sender, $.paymentRecipient, price);

        emit Buy(msg.sender, price, _assets, balances);
    }

    /// @notice Set the start price of the current auction
    /// @dev This will affect the current price, use with caution
    /// @param _startPrice New start price
    function setStartPrice(uint256 _startPrice) external checkAccess(this.setStartPrice.selector) {
        FeeAuctionStorage storage $ = get();
        $.startPrice = _startPrice;
        emit SetStartPrice(_startPrice);
    }

    /// @notice Set duration of auctions
    /// @dev This will affect the current price, use with caution
    /// @param _duration New duration in seconds
    function setDuration(uint256 _duration) external checkAccess(this.setDuration.selector) {
        if (_duration == 0) revert NoDuration();
        FeeAuctionStorage storage $ = get();
        $.duration = _duration;
        emit SetDuration(_duration);
    }

    /// @notice Set minimum start price
    /// @param _minStartPrice New minimum start price
    function setMinStartPrice(uint256 _minStartPrice) external checkAccess(this.setMinStartPrice.selector) {
        FeeAuctionStorage storage $ = get();
        $.minStartPrice = _minStartPrice;
        emit SetMinStartPrice(_minStartPrice);
    }

    /// @dev Transfer all specified assets to the receiver from this address
    /// @param _assets Asset addresses
    /// @param _receiver Receiver address
    /// @return balances Balances transferred to receiver
    function _transferOutAssets(address[] calldata _assets, address _receiver)
        internal
        returns (uint256[] memory balances)
    {
        uint256 assetsLength = _assets.length;
        balances = new uint256[](assetsLength);
        for (uint256 i; i < assetsLength; ++i) {
            address asset = _assets[i];
            balances[i] = IERC20(asset).balanceOf(address(this));
            if (balances[i] > 0) IERC20(asset).safeTransfer(_receiver, balances[i]);
        }
    }

    /// @notice Get the payment token address
    /// @return token Address of the token used for payments
    function paymentToken() external view returns (address token) {
        token = get().paymentToken;
    }

    /// @notice Get the payment recipient address
    /// @return recipient Address that receives the payments
    function paymentRecipient() external view returns (address recipient) {
        recipient = get().paymentRecipient;
    }

    /// @notice Get the current start price
    /// @return price Current start price in payment token decimals
    function startPrice() external view returns (uint256 price) {
        price = get().startPrice;
    }

    /// @notice Get the start timestamp of the current auction
    /// @return timestamp Timestamp when the current auction started
    function startTimestamp() external view returns (uint256 timestamp) {
        timestamp = get().startTimestamp;
    }

    /// @notice Get the auction duration
    /// @return auctionDuration Duration in seconds
    function duration() external view returns (uint256 auctionDuration) {
        auctionDuration = get().duration;
    }

    /// @notice Get the minimum start price
    /// @return price Minimum start price in payment token decimals
    function minStartPrice() external view returns (uint256 price) {
        price = get().minStartPrice;
    }

    /// @dev Only admin can upgrade
    function _authorizeUpgrade(address) internal view override checkAccess(bytes4(0)) { }
}
