// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.29;

import {TradeType} from "./ITradingModule.sol";

/// Each withdraw request manager contract is responsible for managing withdraws of a token
/// from a specific token (i.e. wstETH, weETH, sUSDe, etc). Each yield strategy can call the
/// appropriate withdraw request manager to initiate a withdraw of a given yield token.

struct StakingTradeParams {
    TradeType tradeType;
    uint256 minPurchaseAmount;
    bytes exchangeData;
    uint16 dexId;
    bytes stakeData;
}

struct WithdrawRequest {
    uint256 requestId;
    uint120 yieldTokenAmount;
    uint120 sharesAmount;
}

struct TokenizedWithdrawRequest {
    uint120 totalYieldTokenAmount;
    uint120 totalWithdraw;
    bool finalized;
}

interface IWithdrawRequestManager {
    event ApprovedVault(address indexed vault, bool indexed isApproved);
    event InitiateWithdrawRequest(
        address indexed account,
        address indexed vault,
        uint256 yieldTokenAmount,
        uint256 sharesAmount,
        uint256 requestId
    );

    event WithdrawRequestTokenized(
        address indexed from,
        address indexed to,
        uint256 indexed requestId,
        uint256 sharesAmount
    );

    /// @notice Returns the token that will be the result of staking
    /// @return yieldToken the yield token of the withdraw request manager
    function YIELD_TOKEN() external view returns (address);

    /// @notice Returns the token that will be the result of the withdraw request
    /// @return withdrawToken the withdraw token of the withdraw request manager
    function WITHDRAW_TOKEN() external view returns (address);

    /// @notice Returns the token that will be used to stake
    /// @return stakingToken the staking token of the withdraw request manager
    function STAKING_TOKEN() external view returns (address);

    /// @notice Returns whether a vault is approved to initiate withdraw requests
    /// @param vault the vault to check the approval for
    /// @return isApproved whether the vault is approved
    function isApprovedVault(address vault) external view returns (bool);

    /// @notice Returns whether a vault has a pending withdraw request
    /// @param vault the vault to check the pending withdraw request for
    /// @param account the account to check the pending withdraw request for
    /// @return isPending whether the vault has a pending withdraw request
    function isPendingWithdrawRequest(address vault, address account) external view returns (bool);

    /// @notice Sets whether a vault is approved to initiate withdraw requests
    /// @param vault the vault to set the approval for
    /// @param isApproved whether the vault is approved
    function setApprovedVault(address vault, bool isApproved) external;

    /// @notice Stakes the deposit token to the yield token and transfers it back to the vault
    /// @dev Only approved vaults can stake tokens
    /// @param depositToken the token to stake, will be transferred from the vault
    /// @param amount the amount of tokens to stake
    /// @param data additional data for the stake
    function stakeTokens(address depositToken, uint256 amount, bytes calldata data) external returns (uint256 yieldTokensMinted);

    /// @notice Initiates a withdraw request
    /// @dev Only approved vaults can initiate withdraw requests
    /// @param account the account to initiate the withdraw request for
    /// @param yieldTokenAmount the amount of yield tokens to withdraw
    /// @param sharesAmount the amount of shares to withdraw, used to mark the shares to
    /// yield token ratio at the time of the withdraw request
    /// @param data additional data for the withdraw request
    /// @return requestId the request id of the withdraw request
    function initiateWithdraw(
        address account,
        uint256 yieldTokenAmount,
        uint256 sharesAmount,
        bytes calldata data
    ) external returns (uint256 requestId);

    /// @notice Attempts to redeem active withdraw requests during vault exit
    /// @param account the account to finalize and redeem the withdraw request for
    /// @param withdrawYieldTokenAmount the amount of yield tokens to withdraw
    /// @param sharesToBurn the amount of shares to burn for the yield token
    /// @return tokensWithdrawn amount of withdraw tokens redeemed from the withdraw requests
    /// @return finalized whether the withdraw request was finalized
    function finalizeAndRedeemWithdrawRequest(
        address account,
        uint256 withdrawYieldTokenAmount,
        uint256 sharesToBurn
    ) external returns (uint256 tokensWithdrawn, bool finalized);

    /// @notice Finalizes withdraw requests outside of a vault exit. This may be required in cases if an
    /// account is negligent in exiting their vault position and letting the withdraw request sit idle
    /// could result in losses. The withdraw request is finalized and stored in a tokenized withdraw request
    /// where the account has the full claim on the withdraw.
    /// @dev No access control is enforced on this function but no tokens are transferred off the request
    /// manager either.
    function finalizeRequestManual(
        address vault,
        address account
    ) external returns (uint256 tokensWithdrawn, bool finalized);

    /// @notice If an account has an illiquid withdraw request, this method will tokenize their
    /// claim on it during liquidation.
    /// @dev Only approved vaults can tokenize withdraw requests
    /// @param from the account that is being liquidated
    /// @param to the liquidator
    /// @param sharesAmount the amount of shares to the liquidator
    function tokenizeWithdrawRequest(
        address from,
        address to,
        uint256 sharesAmount
    ) external returns (bool didTokenize);

    /// @notice Allows the emergency exit role to rescue tokens from the withdraw request manager
    /// @param cooldownHolder the cooldown holder to rescue tokens from
    /// @param token the token to rescue
    /// @param receiver the receiver of the rescued tokens
    /// @param amount the amount of tokens to rescue
    function rescueTokens(address cooldownHolder, address token, address receiver, uint256 amount) external;

    /// @notice Returns whether a withdraw request can be finalized
    /// @param requestId the request id of the withdraw request
    /// @return canFinalize whether the withdraw request can be finalized
    function canFinalizeWithdrawRequest(uint256 requestId) external view returns (bool);

    /// @notice Returns the withdraw request and tokenized withdraw request for an account
    /// @param vault the vault to get the withdraw request for
    /// @param account the account to get the withdraw request for
    /// @return w the withdraw request
    /// @return s the tokenized withdraw request
    function getWithdrawRequest(address vault, address account) external view returns (WithdrawRequest memory w, TokenizedWithdrawRequest memory s);

    /// @notice Returns the value of a withdraw request in terms of the asset
    /// @param vault the vault to get the withdraw request for
    /// @param account the account to get the withdraw request for
    /// @param asset the asset to get the value for
    /// @param shares the amount of shares to get the value for
    /// @return hasRequest whether the account has a withdraw request
    /// @return value the value of the withdraw request in terms of the asset
    function getWithdrawRequestValue(address vault, address account, address asset, uint256 shares) external view returns (bool hasRequest, uint256 value);
}
