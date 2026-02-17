// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

interface IRestakerDebtToken {
    /// @custom:storage-location erc7201:cap.storage.RestakerDebt
    struct RestakerDebtTokenStorage {
        address oracle;
        address debtToken;
        address asset;
        uint8 decimals;
        uint256 totalSupply;
        mapping(address => uint256) interestPerSecond;
        mapping(address => uint256) lastAgentUpdate;
        uint256 totalInterestPerSecond;
        uint256 lastUpdate;
    }

    /// @dev Operation not supported
    error OperationNotSupported();

    /// @notice Initialize the debt token with the underlying asset
    /// @param _accessControl Access control address
    /// @param _oracle Oracle address
    /// @param _debtToken Principal debt token
    /// @param _asset Asset address
    function initialize(address _accessControl, address _oracle, address _debtToken, address _asset) external;

    /// @notice Update the interest per second of the agent and the scaled total supply
    /// @dev Left permissionless
    /// @param _agent Agent address to update interest rate for
    function update(address _agent) external;

    /// @notice Burn the debt token, only callable by the lender
    /// @dev All underlying token transfers are handled by the lender instead of this contract
    /// @param _agent Agent address that will have it's debt repaid
    /// @param _amount Amount of underlying asset to repay to lender
    /// @return actualRepaid Actual amount repaid
    function burn(address _agent, uint256 _amount) external returns (uint256 actualRepaid);

    /// @notice Average rate of all restakers weighted by debt
    /// @param rate Average rate
    function averageRate() external view returns (uint256 rate);

    /// @notice Get the current state for a restaker/agent
    /// @param _agent The address of the agent/restaker
    /// @return _interestPerSecond The current interest rate per second for the agent
    /// @return _lastUpdate The timestamp of the last update for this agent
    function agent(address _agent) external view returns (uint256 _interestPerSecond, uint256 _lastUpdate);

    /// @notice Get the oracle address
    /// @return _oracle The oracle address
    function oracle() external view returns (address _oracle);

    /// @notice Get the debt token address
    /// @return _debtToken The debt token address
    function debtToken() external view returns (address _debtToken);

    /// @notice Get the asset address
    /// @return _asset The asset address
    function asset() external view returns (address _asset);

    /// @notice Get the total interest per second
    /// @return _totalInterestPerSecond The total interest per second
    function totalInterestPerSecond() external view returns (uint256 _totalInterestPerSecond);

    /// @notice Get the last update timestamp
    /// @return _lastUpdate The last update timestamp
    function lastUpdate() external view returns (uint256 _lastUpdate);
}
