// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6 <0.9;


library RedemptionRequestInfo {
    enum Status {
        ACTIVE,                 // waiting for confirmation/default
        DEFAULTED_UNCONFIRMED,  // default called, failed or late payment can still be confirmed
        // final statuses - there can be no valid payment for this redemption anymore
        SUCCESSFUL,             // successful payment confirmed
        DEFAULTED_FAILED,       // payment failed   (default was paid)
        BLOCKED,                // payment blocked
        REJECTED                // redemption request rejected due to invalid redeemer's address
    }

    struct Data {
        // The id used for confirming or defaulting the request.
        uint64 redemptionRequestId;

        // Redemption status. Note that on payment confirmation the request is deleted, so there is no success status.
        RedemptionRequestInfo.Status status;

        // The redeemed agent vault.
        address agentVault;

        // Native redeemer address - the address that receives collateral in case of default.
        address redeemer;

        // The underlying address to which the redeemed assets should be paid by the agent.
        string paymentAddress;

        // Payment reference that must be part of the agent's redemption payment.
        bytes32 paymentReference;

        // The amount of the FAsset the redeemer has burned. Note that this is not the amount of underlying
        // the redeemer will receive - the redemption payment amount is this minus the underlyingFeeUBA.
        uint128 valueUBA;

        // The redemption fee that remain on agent's underlying address.
        // Part of it will be reminted as pool fee share and the rest becomes the agent's free underlying.
        uint128 feeUBA;

        // Proportional part of the underlyingFeeUBA that is re-minted on successful redemption
        // and goes to the collateral pool.
        uint16 poolFeeShareBIPS;

        // The underlying block (approximate - as known by the asset manager) when the request occurred.
        uint64 firstUnderlyingBlock;

        // The last underlying block and timestamp for redemption payment. Redemption is defaulted if
        // there is no payment by the time BOTH lastUnderlyingBlock and lastUnderlyingTimestamp have passed.
        uint64 lastUnderlyingBlock;
        uint64 lastUnderlyingTimestamp;

        // The native (Flare/Songbird) chain timestamp when the request occurred.
        uint64 timestamp;

        // True if redemption was created by a selfCloseExit on the collateral pool.
        bool poolSelfClose;

        // True if redemption was initiated by an agent for transfer to core vault.
        bool transferToCoreVault;

        // The executor, optionally assigned by the redeemer to execute the default if needed.
        // (Only redeemer, agent or executor may execute the default.)
        address executor;

        // The fee in NAT that the executor receives if they successfully call default.
        uint256 executorFeeNatWei;
    }
}
