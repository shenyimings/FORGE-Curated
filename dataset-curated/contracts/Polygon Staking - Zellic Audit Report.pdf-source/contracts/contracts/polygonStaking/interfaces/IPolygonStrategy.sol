// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

interface IPolygonStrategy {
    function depositQueuedTokens(
        uint256[] calldata _vaultIds,
        uint256[] calldata _amounts
    ) external;

    function unbond(uint256 _toUnbond) external;

    function forceUnbond(uint256[] calldata _vaultIds, uint256[] calldata _amounts) external;

    function unstakeClaim(uint256[] calldata _vaultIds) external;

    function restakeRewards(uint256[] calldata _vaultIds) external;

    function totalQueued() external view returns (uint256);

    function getVaults() external view returns (address[] memory);

    function validatorRemoval() external view returns (bool, uint64, uint128);

    function numVaultsUnbonding() external view returns (uint256);
}
