// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

import { RateLimitConfig, RateLimitDirection, RateLimitAccountingType } from "./ISkyRateLimiter.sol";

/**
 * @title ISkyOFT
 * @notice Interface for the SkyOFTCore contract, which manages cross-chain transfer rate limits and fees.
 * @dev This interface defines the core functionalities of the SkyOFT system, including rate limit management,
 * pauser management, and fee withdrawal.
 */
interface ISkyOFT {
    // Events
    event FeesWithdrawn(address indexed to, uint256 amountLD);
    event PauserSet(address indexed pauser, bool canPause);

    // Errors
    error PauserIdempotent(address pauser);
    error InsufficientFeeBalance(uint256 amountLD, uint256 feeBalance);
    error OnlyPauser(address caller);

    // @dev Global variable view function definitions.
    function feeBalance() external view returns (uint256 amountLD);
    function pausers(address _pauser) external view returns (bool canPause);

    /**
     * @notice Sets the cross-chain tx rate limits for specific endpoints based on provided configurations.
     * It allows configuration of rate limits either for outbound and inbound directions.
     * This method is designed to be called by contract admins for updating the system's rate limiting behavior.
     *
     * @notice WARNING: Changing rate limits without first calling resetRateLimits() MIGHT result in unexpected behavior.
     * DYOR on Rate Limits across every VM to ensure compatibility.
     * Especially consider inflight decay rates when reducing limits.
     *
     * @param rateLimitConfigsInbound Array of INBOUND `RateLimitConfig` structs that specify new rate limit settings.
     * @param rateLimitConfigsOutbound Array of OUTBOUND `RateLimitConfig` structs that specify new rate limit settings.
     *
     * @dev Each struct includes an endpoint ID, the limit value, and the window duration.
     * @dev The direction (inbound or outbound) specifies whether the eid passed should be considered a srcEid or dstEid.
     */
    function setRateLimits(
        RateLimitConfig[] calldata rateLimitConfigsInbound,
        RateLimitConfig[] calldata rateLimitConfigsOutbound
    ) external;

    /**
     * @notice Resets the rate limits for the given endpoint ids.
     * @param eidsInbound The endpoint ids to reset the rate limits for inbound.
     * @param eidsOutbound The endpoint ids to reset the rate limits for outbound.
     */
    function resetRateLimits(uint32[] calldata eidsInbound, uint32[] calldata eidsOutbound) external;

    /**
     * @notice Sets the rate limit accounting type.
     * @param rateLimitAccountingType The new rate limit accounting type.
     * @dev You may want to call `resetRateLimits` after changing the rate limit accounting type.
     */
    function setRateLimitAccountingType(RateLimitAccountingType rateLimitAccountingType) external;

    /**
     * @notice Sets the pauser status for a given address.
     * @param _pauser The address to set the pauser status for.
     * @param _canPause Boolean indicating ability to pause cross-chain transfers.
     */
    function setPauser(address _pauser, bool _canPause) external;

    /**
     * @notice Pauses the contract if the caller is a pauser.
     * @dev Only pausers can pause the contract.
     */
    function pause() external;

    /**
     * @notice Unpauses the contract.
     * @dev Only the owner can unpause the contract.
     */
    function unpause() external;

    /**
     * @notice Withdraws accumulated fees to a specified address.
     * @param to The address to which the fees will be withdrawn.
     * @param amountLD The amount of tokens to withdraw in local decimals.
     *
     * @dev This also allows for owner to rescue tokens that are otherwise burned/lost.
     */
    function withdrawFees(address to, uint256 amountLD) external;

}
