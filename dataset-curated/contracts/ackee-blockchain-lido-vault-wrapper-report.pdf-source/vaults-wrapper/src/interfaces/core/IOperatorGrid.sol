// SPDX-License-Identifier: MIT
pragma solidity >=0.8.25;

import {IAccessControlEnumerable} from "@openzeppelin/contracts/access/extensions/IAccessControlEnumerable.sol";

interface IOperatorGrid is IAccessControlEnumerable {
    event GroupAdded(address indexed nodeOperator, uint256 shareLimit);
    event GroupShareLimitUpdated(address indexed nodeOperator, uint256 shareLimit);
    event TierAdded(
        address indexed nodeOperator,
        uint256 indexed tierId,
        uint256 shareLimit,
        uint256 reserveRatioBP,
        uint256 forcedRebalanceThresholdBP,
        uint256 infraFeeBP,
        uint256 liquidityFeeBP,
        uint256 reservationFeeBP
    );
    event TierChanged(address indexed vault, uint256 indexed tierId, uint256 shareLimit);
    event TierUpdated(
        uint256 indexed tierId,
        uint256 shareLimit,
        uint256 reserveRatioBP,
        uint256 forcedRebalanceThresholdBP,
        uint256 infraFeeBP,
        uint256 liquidityFeeBP,
        uint256 reservationFeeBP
    );
    event VaultJailStatusUpdated(address indexed vault, bool isInJail);

    struct TierParams {
        uint256 shareLimit;
        uint256 reserveRatioBP;
        uint256 forcedRebalanceThresholdBP;
        uint256 infraFeeBP;
        uint256 liquidityFeeBP;
        uint256 reservationFeeBP;
    }

    struct Tier {
        address operator;
        uint96 shareLimit;
        uint96 liabilityShares;
        uint16 reserveRatioBP;
        uint16 forcedRebalanceThresholdBP;
        uint16 infraFeeBP;
        uint16 liquidityFeeBP;
        uint16 reservationFeeBP;
    }

    function LIDO_LOCATOR() external view returns (address);
    function REGISTRY_ROLE() external view returns (bytes32);
    function DEFAULT_TIER_ID() external view returns (uint256);
    function DEFAULT_TIER_OPERATOR() external view returns (address);

    function tier(uint256 _tierId) external view returns (Tier memory);

    function tiersCount() external view returns (uint256);

    function effectiveShareLimit(address _vault) external view returns (uint256);

    function isVaultInJail(address _vault) external view returns (bool);

    function vaultTierInfo(address _vault)
        external
        view
        returns (
            address nodeOperator,
            uint256 tierId,
            uint256 shareLimit,
            uint256 reserveRatioBP,
            uint256 forcedRebalanceThresholdBP,
            uint256 infraFeeBP,
            uint256 liquidityFeeBP,
            uint256 reservationFeeBP
        );

    function alterTiers(uint256[] calldata _tierIds, TierParams[] calldata _tierParams) external;

    function registerTiers(address _nodeOperator, TierParams[] calldata _tiers) external;

    function registerGroup(address _nodeOperator, uint256 _shareLimit) external;
}
