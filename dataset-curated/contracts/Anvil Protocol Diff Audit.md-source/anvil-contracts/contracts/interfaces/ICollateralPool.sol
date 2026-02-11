// SPDX-License-Identifier: ISC
pragma solidity 0.8.25;

/**
 * @title The interface that should be implemented by all collateral pools using ICollateral's pooling functions.
 */
interface ICollateralPool {
    /**
     * @notice Gets the provided account's pool balance in the provided token. This should be calculated based on the
     * account's stake in the pool, multiplied by the pool's balance of the token in question.
     * In many cases, some or all of this amount will be staked, locked, or otherwise inaccessible by the account at the
     * time of the call, but the account's current portion of the pool will still be returned.
     *
     * Note: if staked, locked, or otherwise inaccessible, the account's pool balance may be at risk of future seizure.
     * That is to say that the value returned from this function may not be the future withdrawable balance for the account.
     * @param _accountAddress The address of the account for which the pool balance will be returned.
     * @param _tokenAddress The address of the token for which the account pool balance will be returned.
     * @return _balance The balance of the account in the pool at this moment in time.
     */
    function getAccountPoolBalance(
        address _accountAddress,
        address _tokenAddress
    ) external view returns (uint256 _balance);
}
