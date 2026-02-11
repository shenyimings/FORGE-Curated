// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { IOracle } from "./IOracle.sol";

interface IRateOracle {
    /// @custom:storage-location erc7201:cap.storage.RateOracle
    struct RateOracleStorage {
        mapping(address => IOracle.OracleData) marketOracleData;
        mapping(address => IOracle.OracleData) utilizationOracleData;
        mapping(address => uint256) benchmarkRate;
        mapping(address => uint256) restakerRate;
    }

    /// @notice Fetch the market rate for an asset being borrowed
    /// @dev Rate value is encoded in ray (27 decimals) and encodes yearly rates
    /// @param _asset Asset address
    /// @return rate Borrow interest rate
    function marketRate(address _asset) external returns (uint256 rate);

    /// @notice View the utilization rate for an asset
    /// @dev Rate value is encoded in ray (27 decimals) and encodes yearly rates
    /// @param _asset Asset address
    /// @return rate Utilization rate
    function utilizationRate(address _asset) external returns (uint256 rate);

    /// @notice View the benchmark rate for an asset
    /// @dev Rate value is encoded in ray (27 decimals) and encodes yearly rates
    /// @param _asset Asset address
    /// @return rate Benchmark rate
    function benchmarkRate(address _asset) external view returns (uint256 rate);

    /// @notice View the restaker rate for an agent
    /// @dev Rate value is encoded in ray (27 decimals) and encodes yearly rates
    /// @param _agent Agent address
    /// @return rate Restaker rate
    function restakerRate(address _agent) external view returns (uint256 rate);

    /// @notice View the market oracle data for an asset
    /// @param _asset Asset address
    /// @return data Oracle data for an asset
    function marketOracleData(address _asset) external view returns (IOracle.OracleData memory data);

    /// @notice View the utilization oracle data for an asset
    /// @param _asset Asset address
    /// @return data Oracle data for an asset
    function utilizationOracleData(address _asset) external view returns (IOracle.OracleData memory data);

    /// @notice Set a market source for an asset
    /// @param _asset Asset address
    /// @param _oracleData Oracle data
    function setMarketOracleData(address _asset, IOracle.OracleData calldata _oracleData) external;

    /// @notice Set a utilization source for an asset
    /// @param _asset Asset address
    /// @param _oracleData Oracle data
    function setUtilizationOracleData(address _asset, IOracle.OracleData calldata _oracleData) external;

    /// @notice Update the minimum interest rate for an asset
    /// @dev Rate value is encoded in ray (27 decimals) and encodes yearly rates
    /// @param _asset Asset address
    /// @param _rate New interest rate
    function setBenchmarkRate(address _asset, uint256 _rate) external;

    /// @notice Update the rate at which an agent accrues interest explicitly to pay restakers
    /// @dev Rate value is encoded in ray (27 decimals) and encodes yearly rates
    /// @param _agent Agent address
    /// @param _rate New interest rate
    function setRestakerRate(address _agent, uint256 _rate) external;

    /// @dev Set market oracle data
    event SetMarketOracleData(address asset, IOracle.OracleData data);

    /// @dev Set utilization oracle data
    event SetUtilizationOracleData(address asset, IOracle.OracleData data);

    /// @dev Set benchmark rate
    /// @dev Rate value is encoded in ray (27 decimals) and encodes yearly rates
    event SetBenchmarkRate(address asset, uint256 rate);

    /// @dev Set restaker rate
    /// @dev Rate value is encoded in ray (27 decimals) and encodes yearly rates
    event SetRestakerRate(address agent, uint256 rate);
}
