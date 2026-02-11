// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ILazyOracle} from "../../src/interfaces/core/ILazyOracle.sol";

contract MockLazyOracle is ILazyOracle {
    uint256 private _latestReportTimestamp;

    function latestReportTimestamp() external view returns (uint256) {
        return _latestReportTimestamp;
    }

    function mock__updateLatestReportTimestamp(uint256 _timestamp) external {
        _latestReportTimestamp = _timestamp;
    }

    function updateReportData(
        uint256 _vaultsDataTimestamp,
        uint256 _vaultsDataRefSlot,
        bytes32 _vaultsDataTreeRoot,
        string memory _vaultsDataReportCid
    ) external {}

    function updateVaultData(
        address _vault,
        uint256 _totalValue,
        uint256 _cumulativeLidoFees,
        uint256 _liabilityShares,
        uint256 _maxLiabilityShares,
        uint256 _slashingReserve,
        bytes32[] calldata _proof
    ) external {}

    function latestReportData()
        external
        view
        returns (uint256 timestamp, uint256 refSlot, bytes32 treeRoot, string memory reportCid)
    {}

    function quarantinePeriod() external pure returns (uint256) {
        return 0;
    }

    function maxRewardRatioBP() external pure returns (uint256) {
        return 0;
    }

    function maxLidoFeeRatePerSecond() external pure returns (uint256) {
        return 0;
    }

    function vaultQuarantine(address) external pure returns (QuarantineInfo memory) {
        return QuarantineInfo({startTimestamp: 0, totalValueBeforeQuarantine: 0, totalValueDuringQuarantine: 0});
    }

    function vaultsCount() external pure returns (uint256) {
        return 0;
    }

    function batchVaultsInfo(uint256, uint256) external pure returns (VaultInfo[] memory) {
        return new VaultInfo[](0);
    }

    function removeVaultQuarantine(address) external {}

    function updateSanityParams(uint256, uint256, uint256) external {}
}
