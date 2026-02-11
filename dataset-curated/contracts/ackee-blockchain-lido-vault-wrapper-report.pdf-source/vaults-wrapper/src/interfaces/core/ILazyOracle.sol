// SPDX-FileCopyrightText: 2025 Lido <info@lido.fi>
// SPDX-License-Identifier: MIT

pragma solidity >=0.8.25;

/**
 * Interface to connect AccountingOracle with LazyOracle and force type consistency
 */
interface ILazyOracle {
    struct QuarantineInfo {
        uint256 startTimestamp;
        uint256 totalValueBeforeQuarantine;
        uint256 totalValueDuringQuarantine;
    }

    struct VaultInfo {
        address vault;
        uint256 totalValue;
        uint256 liabilityShares;
        uint256 cumulativeLidoFees;
        bool isQuarantined;
        QuarantineInfo quarantine;
    }

    function updateReportData(
        uint256 _vaultsDataTimestamp,
        uint256 _vaultsDataRefSlot,
        bytes32 _vaultsDataTreeRoot,
        string memory _vaultsDataReportCid
    ) external;

    function updateVaultData(
        address _vault,
        uint256 _totalValue,
        uint256 _cumulativeLidoFees,
        uint256 _liabilityShares,
        uint256 _maxLiabilityShares,
        uint256 _slashingReserve,
        bytes32[] calldata _proof
    ) external;

    function latestReportTimestamp() external view returns (uint256);
    function latestReportData()
        external
        view
        returns (uint256 timestamp, uint256 refSlot, bytes32 treeRoot, string memory reportCid);

    function quarantinePeriod() external view returns (uint256);
    function maxRewardRatioBP() external view returns (uint256);
    function maxLidoFeeRatePerSecond() external view returns (uint256);
    function vaultQuarantine(address _vault) external view returns (QuarantineInfo memory);
    function vaultsCount() external view returns (uint256);
    function batchVaultsInfo(uint256 _offset, uint256 _limit) external view returns (VaultInfo[] memory);
    function removeVaultQuarantine(address _vault) external;
    function updateSanityParams(uint256 _quarantinePeriod, uint256 _maxRewardRatioBP, uint256 _maxLidoFeeRatePerSecond)
        external;
}
