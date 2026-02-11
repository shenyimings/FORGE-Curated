// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6 <0.9;
pragma abicoder v2;

import {IDistributionToDelegators} from "@flarenetwork/flare-periphery-contracts/flare/IDistributionToDelegators.sol";
import {IRewardManager} from "@flarenetwork/flare-periphery-contracts/flare/IRewardManager.sol";
import {ICollateralPoolToken} from "./ICollateralPoolToken.sol";


interface ICollateralPool {
    event CPEntered(
        address indexed tokenHolder,
        uint256 amountNatWei,
        uint256 receivedTokensWei,
        uint256 timelockExpiresAt);

    event CPExited(
        address indexed tokenHolder,
        uint256 burnedTokensWei,
        uint256 receivedNatWei);

    event CPSelfCloseExited(
        address indexed tokenHolder,
        uint256 burnedTokensWei,
        uint256 receivedNatWei,
        uint256 closedFAssetsUBA);

    event CPFeeDebtPaid(
        address indexed tokenHolder,
        uint256 paidFeesUBA);

    event CPFeesWithdrawn(
        address indexed tokenHolder,
        uint256 withdrawnFeesUBA);

    event CPFeeDebtChanged(
        address indexed tokenHolder,
        int256 newFeeDebtUBA);

    // Emitted when asset manager forces payout from the pool
    event CPPaidOut(
        address indexed recipient,
        uint256 paidNatWei,
        uint256 burnedTokensWei);

    event CPClaimedReward(
        uint256 amountNatWei,
        uint8 rewardType);

    error OnlyAssetManager();
    error OnlyAgent();
    error AlreadyInitialized();
    error OnlyInternalUse();
    error PoolTokenAlreadySet();
    error AmountOfNatTooLow();
    error AmountOfCollateralTooLow();
    error DepositResultsInZeroTokens();
    error TokenShareIsZero();
    error TokenBalanceTooLow();
    error SentAmountTooLow();
    error CollateralRatioFallsBelowExitCR();
    error InvalidRecipientAddress();
    error RedemptionRequiresClosingTooManyTickets();
    error FreeFAssetBalanceTooSmall();
    error WithdrawZeroFAsset();
    error ZeroFAssetDebtPayment();
    error PaymentLargerThanFeeDebt();
    error FAssetAllowanceTooSmall();
    error TokenSupplyAfterExitTooLow();
    error CollateralAfterExitTooLow();
    error CannotDestroyPoolWithIssuedTokens();
    error EmergencyPauseActive();

    /**
     * Enters the collateral pool by depositing NAT.
     * The tokens have a timelock before which exiting or transferring tokens is not possible.
     * If there are some FAsset fees already in the pool, tokens also have some fee debt, which
     * has to be paid off to make tokens transferable (but they can be redeemed).
     */
    function enter()
        external payable
        returns (uint256 _receivedTokens, uint256 _timelockExpiresAt);

    /**
     * Exits the pool by redeeming the given amount of pool tokens for a share of NAT and f-asset fees.
     * Exiting with non-transferable tokens awards the user with NAT only, while transferable tokens also entitle
     * one to a share of f-asset fees. As there are multiple ways to split spending transferable and
     * non-transferable tokens, the method also takes a parameter called `_exitType`.
     * Exiting with collateral that sinks pool's collateral ratio below exit CR is not allowed and
     *  will revert. In that case, see selfCloseExit.
     * @param _tokenShare   The amount of pool tokens to be redeemed
     */
    function exit(uint256 _tokenShare)
        external
        returns (uint256 _natShare);

    /**
     * Exits the pool by redeeming the given amount of pool tokens and burning f-assets in a way that doesn't
     * endanger the pool collateral ratio. Specifically, if pool's collateral ratio is above exit CR, then
     * the method burns an amount of user's f-assets that do not lower collateral ratio below exit CR. If, on
     * the other hand, collateral pool is below exit CR, then the method burns an amount of user's f-assets
     * that preserve the pool's collateral ratio.
     * F-assets will be redeemed in collateral if their value does not exceed one lot, regardless of
     *  `_redeemToCollateral` value.
     * Method first tries to satisfy the condition by taking f-assets out of sender's f-asset fee share,
     *  specified by `_tokenShare`. If it is not enough it moves on to spending total sender's f-asset fees. If they
     *  are not enough, it takes from the sender's f-asset balance. Spending sender's f-asset fees means that
     *  transferable tokens are converted to non-transferable.
     * In case of self-close via redemption, the user can set executor to trigger possible default.
     * In this case, some NAT can be sent with transaction, to pay the executor's fee.
     * @param _tokenShare                   The amount of pool tokens to be liquidated
     * @param _redeemToCollateral           Specifies if redeemed f-assets should be exchanged to vault collateral
     *                                      by the agent
     * @param _redeemerUnderlyingAddress    Redeemer's address on the underlying chain
     * @param _executor                     The account that is allowed to execute redemption default
     */
    function selfCloseExit(
        uint256 _tokenShare,
        bool _redeemToCollateral,
        string memory _redeemerUnderlyingAddress,
        address payable _executor
    ) external payable;

    /**
     * Collect f-asset fees by locking an appropriate ratio of transferable tokens
     * @param _amount  The amount of f-asset fees to withdraw.
     *                 Must be positive and smaller or equal to the sender's fAsset fees.
     */
    function withdrawFees(uint256 _amount) external;

    /**
     * Exits the pool by redeeming the given amount of pool tokens for a share of NAT and f-asset fees.
     * Exiting with non-transferable tokens awards the user with NAT only, while transferable tokens also entitle
     * one to a share of f-asset fees. As there are multiple ways to split spending transferable and
     * non-transferable tokens, the method also takes a parameter called `_exitType`.
     * Exiting with collateral that sinks pool's collateral ratio below exit CR is not allowed and
     *  will revert. In that case, see selfCloseExit.
     * @param _tokenShare   The amount of pool tokens to be redeemed
     * @param _recipient    The address to which NATs and FAsset fees will be transferred
     */
    function exitTo(uint256 _tokenShare, address payable _recipient)
        external
        returns (uint256 _natShare);

    /**
     * Exits the pool by redeeming the given amount of pool tokens and burning f-assets in a way that doesn't
     * endanger the pool collateral ratio. Specifically, if pool's collateral ratio is above exit CR, then
     * the method burns an amount of user's f-assets that do not lower collateral ratio below exit CR. If, on
     * the other hand, collateral pool is below exit CR, then the method burns an amount of user's f-assets
     * that preserve the pool's collateral ratio.
     * F-assets will be redeemed in collateral if their value does not exceed one lot, regardless of
     *  `_redeemToCollateral` value.
     * Method first tries to satisfy the condition by taking f-assets out of sender's f-asset fee share,
     *  specified by `_tokenShare`. If it is not enough it moves on to spending total sender's f-asset fees. If they
     *  are not enough, it takes from the sender's f-asset balance. Spending sender's f-asset fees means that
     *  transferable tokens are converted to non-transferable.
     * In case of self-close via redemption, the user can set executor to trigger possible default.
     * In this case, some NAT can be sent with transaction, to pay the executor's fee.
     * @param _tokenShare                   The amount of pool tokens to be liquidated
     * @param _redeemToCollateral           Specifies if redeemed f-assets should be exchanged to vault collateral
     *                                      by the agent
     * @param _recipient                    The address to which NATs and FAsset fees will be transferred
     * @param _redeemerUnderlyingAddress    Redeemer's address on the underlying chain
     * @param _executor                     The account that is allowed to execute redemption default
     */
    function selfCloseExitTo(
        uint256 _tokenShare,
        bool _redeemToCollateral,
        address payable _recipient,
        string memory _redeemerUnderlyingAddress,
        address payable _executor
    ) external payable;

    /**
     * Collect f-asset fees by locking an appropriate ratio of transferable tokens
     * @param _amount       The amount of f-asset fees to withdraw.
     *                      Must be positive and smaller or equal to the sender's fAsset fees.
     * @param _recipient    The address to which FAsset fees will be transferred
     */
    function withdrawFeesTo(uint256 _amount, address _recipient) external;

    /**
     * Unlock pool tokens by paying f-asset fee debt
     * @param _fassets  The amount of debt f-asset fees to pay for
     */
    function payFAssetFeeDebt(uint256 _fassets) external;

    /**
     * Claim airdrops earned by holding wrapped native tokens in the pool.
     * NOTE: only the owner of the pool's corresponding agent vault may call this method.
     */
    function claimAirdropDistribution(
        IDistributionToDelegators _distribution,
        uint256 _month
    ) external
        returns(uint256 _claimedAmount);

    /**
     * Opt out of airdrops for wrapped native tokens in the pool.
     * NOTE: only the owner of the pool's corresponding agent vault may call this method.
     */
    function optOutOfAirdrop(
        IDistributionToDelegators _distribution
    ) external;

    /**
     * Delegate WNat vote power for the wrapped native tokens held in this vault.
     * NOTE: only the owner of the pool's corresponding agent vault may call this method.
     */
    function delegate(address _to, uint256 _bips) external;

    /**
     * Clear WNat delegation.
     */
    function undelegateAll() external;

    /**
     * Claim the rewards earned by delegating the vote power for the pool.
     * NOTE: only the owner of the pool's corresponding agent vault may call this method.
     */
    function claimDelegationRewards(
        IRewardManager _rewardManager,
        uint24 _lastRewardEpoch,
        IRewardManager.RewardClaimWithProof[] calldata _proofs
    ) external
        returns(uint256 _claimedAmount);

    /**
     * Get the ERC20 pool token used by this collateral pool
     */
    function poolToken()
        external view
        returns (ICollateralPoolToken);

    /**
     * Get the vault of the agent that owns this collateral pool
     */
    function agentVault()
        external view
        returns (address);

    /**
     * Get the exit collateral ratio in BIPS
     * This is the collateral ratio below which exiting the pool is not allowed
     */
    function exitCollateralRatioBIPS()
        external view
        returns (uint32);


    /**
     * Return total amount of collateral in the pool.
     * This can be different to WNat.balanceOf(poolAddress), because the collateral has to be tracked
     * to prevent unexpected deposit type of attacks on the pool.
     */
    function totalCollateral()
        external view
        returns (uint256);

    /**
     * Returns the f-asset fees belonging to this user.
     * This is the amount of f-assets the user can withdraw by burning transferable pool tokens.
     * @param _account User address
     */
    function fAssetFeesOf(address _account)
        external view
        returns (uint256);

    /**
     * Returns the total f-asset fees in the pool.
     * This can be different to FAsset.balanceOf(poolAddress), because the collateral has to be tracked
     * to prevent unexpected deposit type of attacks on the pool.
     */
    function totalFAssetFees()
        external view
        returns (uint256);

    /**
     * Returns the user's f-asset fee debt.
     * This is the amount of f-assets the user has to pay to make all pool tokens transferable.
     * The debt is created on entering the pool if the user doesn't provide the f-assets corresponding
     * to the share of the f-asset fees already in the pool.
     * @param _account User address
     */
    function fAssetFeeDebtOf(address _account)
        external view
        returns (int256);

    /**
     * Returns the total f-asset fee debt for all users.
     */
    function totalFAssetFeeDebt()
        external view
        returns (int256);

    /**
     * Get the amount of fassets that need to be burned to perform self close exit.
     */
    function fAssetRequiredForSelfCloseExit(uint256 _tokenAmountWei)
        external view
        returns (uint256);
}