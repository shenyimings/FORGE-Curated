// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title Burner Events
/// @notice Events used in the Burner contract
library BurnerEvents {
    /// @notice Emitted when a burn is successful
    /// @param user The user who burned the tokens
    /// @param totalAmountOut The total amount of tokens burned
    /// @param feeAmount The amount of fees collected
    event BurnSuccess(
        address indexed user,
        uint256 totalAmountOut, 
        uint256 feeAmount
    );

    /// @notice Emitted when a swap is successful
    /// @param user The user who swapped the tokens
    /// @param tokenIn The token that was swapped
    /// @param amountIn The amount of tokens swapped
    /// @param amountOut The amount of tokens received
    event SwapSuccess(
        address indexed user, 
        address indexed tokenIn, 
        uint256 amountIn, 
        uint256 amountOut
    );

    /// @notice Emitted when a swap fails
    /// @param user The user who swapped the tokens
    /// @param tokenIn The token that was swapped
    /// @param amountIn The amount of tokens swapped
    /// @param reason The reason the swap failed
    event SwapFailed(
        address indexed user, 
        address indexed tokenIn, 
        uint256 amountIn, 
        string reason
    );

    /// @notice Emitted when a bridge call is successful
    /// @param user The user who called the bridge
    /// @param returnData The data returned by the bridge
    /// @param amountAfterFee The amount of tokens received after fees
    /// @param bridgeFee The amount of fees collected
    event BridgeSuccess(
        address indexed user, 
        bytes returnData, 
        uint256 amountAfterFee, 
        uint256 bridgeFee
    );

    /// @notice Emitted when a referrer fee is paid
    /// @param user The user who paid the referrer fee
    /// @param referrer The referrer who received the fee
    /// @param amount The amount of fees paid
    event ReferrerFeePaid(
        address indexed user, 
        address indexed referrer, 
        uint256 amount
    );

    /// @notice Emitted when the minimum gas for a swap is changed
    /// @param newMinGasForSwap The new minimum gas before swap
    event MinGasForSwapChanged(
        uint32 newMinGasForSwap
    );

    /// @notice Emitted when the maximum number of tokens that can be burned in one transaction is changed
    /// @param newMaxTokensPerBurn The new maximum number of tokens that can be burned in one transaction
    event MaxTokensPerBurnChanged(
        uint32 newMaxTokensPerBurn
    );

    /// @notice Emitted when the burn fee divisor is changed
    /// @param newBurnFeeDivisor The new burn fee divisor
    event BurnFeeDivisorChanged(
        uint256 newBurnFeeDivisor
    );

    /// @notice Emitted when the bridge fee divisor is changed
    /// @param newBridgeFeeDivisor The new bridge fee divisor
    event BridgeFeeDivisorChanged(
        uint256 newBridgeFeeDivisor
    );

    /// @notice Emitted when the referrer fee share is changed
    /// @param newReferrerFeeShare The new referrer fee share
    event ReferrerFeeShareChanged(
        uint8 newReferrerFeeShare
    );

    /// @notice Emitted when a partner is added
    /// @param partner The partner address
    event PartnerAdded(
        address indexed partner
    );

    /// @notice Emitted when a partner is removed
    /// @param partner The partner address
    event PartnerRemoved(
        address indexed partner
    );

    /// @notice Emitted when a partner fee divisor is changed
    /// @param partner The partner address
    /// @param newFeeShare The new fee share
    event PartnerFeeShareChanged(
        address indexed partner, 
        uint8 newFeeShare
    );

    /// @notice Emitted when the Router is changed
    /// @param newRouter The new Router address
    event RouterChanged(
        address indexed newRouter
    );

    /// @notice Emitted when the Permit2 contract is changed
    /// @param newPermit2 The new Permit2 address
    event Permit2Changed(
        address indexed newPermit2
    );

    /// @notice Emitted when the fee collector is changed
    /// @param newFeeCollector The new fee collector address
    event FeeCollectorChanged(
        address indexed newFeeCollector
    );

    /// @notice Emitted when the bridge address is changed
    /// @param newBridgeAddress The new bridge address
    event BridgeAddressChanged(
        address indexed newBridgeAddress
    );

    /// @notice Emitted when the bridge is paused
    /// @param newPauseBridge The new pause bridge status
    event PauseBridgeChanged(
        bool newPauseBridge
    );

    /// @notice Emitted when the referral is paused
    /// @param newPauseReferral The new pause referral status
    event PauseReferralChanged(
        bool newPauseReferral
    );

    /// @notice Emitted when the admin is changed
    /// @param newAdmin The new admin address
    event AdminChanged(
        address indexed newAdmin
    );
}