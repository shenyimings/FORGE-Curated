// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

interface IStrategy {
    event StrategySupplied(
        address indexed user, address indexed referral, uint256 ethAmount, uint256 stv, uint256 wstethToMint, bytes data
    );
    event StrategyExitRequested(address indexed user, bytes32 requestId, uint256 wsteth, bytes data);
    event StrategyExitFinalized(address indexed user, bytes32 requestId, uint256 wsteth);

    function SUPPLY_PAUSE_ROLE() external pure returns (bytes32);

    /**
     * @notice Initializes the strategy
     * @param _admin The admin address
     * @param _supplyPauser The supply pauser address (zero for none)
     */
    function initialize(address _admin, address _supplyPauser) external;

    /**
     * @notice Returns the address of the pool
     * @return The address of the pool
     */
    function POOL() external view returns (address);

    /**
     * @notice Supplies wstETH to the strategy
     * @param _referral The referral address
     * @param _wstethToMint The amount of wstETH to mint
     * @param _params The parameters for the supply
     * @return stv The minted amount of stv
     */
    function supply(address _referral, uint256 _wstethToMint, bytes calldata _params)
        external
        payable
        returns (uint256 stv);

    /**
     * @notice Returns the remaining minting capacity shares of a user
     * @param _user The user to get the remaining minting capacity shares for
     * @param _ethToFund The amount of ETH to fund
     * @return stethShares The remaining minting capacity shares
     */
    function remainingMintingCapacitySharesOf(address _user, uint256 _ethToFund)
        external
        view
        returns (uint256 stethShares);

    /**
     * @notice Requests exit from the strategy
     * @param _wsteth The amount of wstETH to request exit for
     * @param _params The parameters for the exit
     * @return requestId The Strategy request id
     */
    function requestExitByWsteth(uint256 _wsteth, bytes calldata _params) external returns (bytes32 requestId);

    /**
     * @notice Finalizes exit from the strategy
     * @param requestId The Strategy request id
     */
    function finalizeRequestExit(bytes32 requestId) external;

    /**
     * @notice Burns wstETH to reduce the user's minted stETH shares obligation
     * @param _wstethToBurn The amount of wstETH to burn
     */
    function burnWsteth(uint256 _wstethToBurn) external;

    /**
     * @notice Requests a withdrawal from the Withdrawal Queue
     * @param _recipient The address to receive the withdrawal
     * @param _stvToWithdraw The amount of stv to withdraw
     * @param _stethSharesToRebalance The amount of stETH shares to rebalance
     * @return requestId The Withdrawal Queue request ID
     */
    function requestWithdrawalFromPool(address _recipient, uint256 _stvToWithdraw, uint256 _stethSharesToRebalance)
        external
        returns (uint256 requestId);

    /**
     * @notice Returns the amount of wstETH of a user
     * @param _user The user to get the wstETH for
     * @return wsteth The amount of wstETH
     */
    function wstethOf(address _user) external view returns (uint256);

    /**
     * @notice Returns the amount of stv of a user
     * @param _user The user to get the stv for
     * @return stv The amount of stv
     */
    function stvOf(address _user) external view returns (uint256);

    /**
     * @notice Returns the amount of minted stETH shares of a user
     * @param _user The user to get the minted stETH shares for
     * @return mintedStethShares The amount of minted stETH shares
     */
    function mintedStethSharesOf(address _user) external view returns (uint256 mintedStethShares);
}
