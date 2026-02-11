// SPDX-License-Identifier: MIT
pragma solidity >=0.8.18;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IPool {
    /**
     * @notice Gets the current live balances of the pool as fixed point, 18-decimal numbers.
     * @dev Note that live balances will not necessarily be accurate if the pool is in Recovery Mode.
     * Withdrawals in Recovery Mode do not make external calls (including those necessary for updating live balances),
     * so if there are withdrawals, raw and live balances will be out of sync until Recovery Mode is disabled.
     *
     * @return balancesLiveScaled18 Token balances after paying yield fees, applying decimal scaling and rates
     */
    function getCurrentLiveBalances() external view returns (uint256[] memory balancesLiveScaled18);

    /**
     * @dev Returns the value of bpt tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @notice Gets the tokens registered in the pool.
     * @return tokens List of tokens in the pool, sorted in registration order
     */
    function getTokens() external view returns (IERC20[] memory tokens);

    // function approve(address spender, uint256 amount) external returns (bool);
}
