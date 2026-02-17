// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import { Access } from "../access/Access.sol";
import { IOracle } from "../interfaces/IOracle.sol";
import { IRateOracle } from "../interfaces/IRateOracle.sol";
import { RateOracleStorageUtils } from "../storage/RateOracleStorageUtils.sol";

/// @title Oracle for fetching interest rates
/// @author kexley, @capLabs
/// @notice Admin can set the minimum interest rates and the restaker interest rates.
contract RateOracle is IRateOracle, Access, RateOracleStorageUtils {
    /// @dev Initialize the rate oracle
    /// @param _accessControl Access control address
    function __RateOracle_init(address _accessControl) internal onlyInitializing {
        __Access_init(_accessControl);
        __RateOracle_init_unchained();
    }

    /// @dev Initialize unchained
    function __RateOracle_init_unchained() internal onlyInitializing { }

    /// @notice Fetch the market rate for an asset being borrowed
    /// @param _asset Asset address
    /// @return rate Borrow interest rate
    function marketRate(address _asset) external returns (uint256 rate) {
        IOracle.OracleData memory data = getRateOracleStorage().marketOracleData[_asset];
        rate = _getRate(data.adapter, data.payload);
    }

    /// @notice View the utilization rate for an asset
    /// @param _asset Asset address
    /// @return rate Utilization rate
    function utilizationRate(address _asset) external returns (uint256 rate) {
        IOracle.OracleData memory data = getRateOracleStorage().utilizationOracleData[_asset];
        rate = _getRate(data.adapter, data.payload);
    }

    /// @notice View the benchmark rate for an asset
    /// @param _asset Asset address
    /// @return rate Benchmark rate
    function benchmarkRate(address _asset) external view returns (uint256 rate) {
        rate = getRateOracleStorage().benchmarkRate[_asset];
    }

    /// @notice View the restaker rate for an agent
    /// @param _agent Agent address
    /// @return rate Restaker rate
    function restakerRate(address _agent) external view returns (uint256 rate) {
        rate = getRateOracleStorage().restakerRate[_agent];
    }

    /// @notice View the market oracle data for an asset
    /// @param _asset Asset address
    /// @return data Oracle data for an asset
    function marketOracleData(address _asset) external view returns (IOracle.OracleData memory data) {
        data = getRateOracleStorage().marketOracleData[_asset];
    }

    /// @notice View the utilization oracle data for an asset
    /// @param _asset Asset address
    /// @return data Oracle data for an asset
    function utilizationOracleData(address _asset) external view returns (IOracle.OracleData memory data) {
        data = getRateOracleStorage().utilizationOracleData[_asset];
    }

    /// @notice Set a market source for an asset
    /// @param _asset Asset address
    /// @param _oracleData Oracle data
    function setMarketOracleData(address _asset, IOracle.OracleData calldata _oracleData)
        external
        checkAccess(this.setMarketOracleData.selector)
    {
        getRateOracleStorage().marketOracleData[_asset] = _oracleData;
        emit SetMarketOracleData(_asset, _oracleData);
    }

    /// @notice Set a utilization source for an asset
    /// @param _asset Asset address
    /// @param _oracleData Oracle data
    function setUtilizationOracleData(address _asset, IOracle.OracleData calldata _oracleData)
        external
        checkAccess(this.setUtilizationOracleData.selector)
    {
        getRateOracleStorage().utilizationOracleData[_asset] = _oracleData;
        emit SetUtilizationOracleData(_asset, _oracleData);
    }

    /// @notice Update the minimum interest rate for an asset
    /// @param _asset Asset address
    /// @param _rate New interest rate
    function setBenchmarkRate(address _asset, uint256 _rate) external checkAccess(this.setBenchmarkRate.selector) {
        getRateOracleStorage().benchmarkRate[_asset] = _rate;
        emit SetBenchmarkRate(_asset, _rate);
    }

    /// @notice Update the rate at which an agent accrues interest explicitly to pay restakers
    /// @param _agent Agent address
    /// @param _rate New interest rate
    function setRestakerRate(address _agent, uint256 _rate) external checkAccess(this.setRestakerRate.selector) {
        getRateOracleStorage().restakerRate[_agent] = _rate;
        emit SetRestakerRate(_agent, _rate);
    }

    /// @dev Calculate rate using an adapter and payload but do not revert on errors
    /// @param _adapter Adapter for calculation logic
    /// @param _payload Encoded call to adapter with all required data
    /// @return rate Calculated rate
    function _getRate(address _adapter, bytes memory _payload) private returns (uint256 rate) {
        (bool success, bytes memory returnedData) = _adapter.call(_payload);
        if (success) rate = abi.decode(returnedData, (uint256));
    }
}
