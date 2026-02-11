// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.28;

interface INeuEntitlementV2 {
    event InitializedEntitlement(uint256 version, address defaultAdmin, address upgrader, address operator, address neuContract);
    event EntitlementContractAdded(address indexed entitlementContract);
    event EntitlementContractRemoved(address indexed entitlementContract);
    event InitializedEntitlementV2(address neuContract);

    function addEntitlementContract(address entitlementContract) external;
    function removeEntitlementContract(address entitlementContract) external;
    function hasEntitlement(address user) external view returns (bool);
    function hasEntitlementWithContract(address user, address entitlementContract) external view returns (bool);
    function userEntitlementContracts(address user) external view returns (address[] memory);
    function entitlementContractsV2(uint index) external view returns (address);
    function entitlementContractsLength() external view returns (uint256);
}