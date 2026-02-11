// SPDX-License-Identifier: ISC
pragma solidity 0.8.25;

/**
 * @title An interface allowing the deposit of assets into a new ICollateral contract for benefit of a specified account.
 * @dev This function may be used to transfer account assets from one ICollateral contract to another as an upgrade.
 */
interface ICollateralDepositTarget {
    /**
     * @notice Deposits assets from the calling contract into the implementing target on behalf of users.
     * @dev The calling contract should iterate and approve _amounts of all Tokens in _tokenAddresses to be transferred
     * by the implementing contract.
     * @dev The implementing contract MUST iterate and transfer each of the Tokens in _tokenAddresses and transfer the
     * _amounts to itself from the calling contract or revert if that is not possible.
     * @param _accountAddress The address of the account to be credited assets in the implementing contract.
     * @param _tokenAddresses The list of addresses of the Tokens to transfer. Indexes must correspond to _amounts.
     * @param _amounts The list of amounts of the Tokens to transfer. Indexes must correspond to _tokenAddresses.
     */
    function depositToAccount(
        address _accountAddress,
        address[] calldata _tokenAddresses,
        uint256[] calldata _amounts
    ) external;
}
