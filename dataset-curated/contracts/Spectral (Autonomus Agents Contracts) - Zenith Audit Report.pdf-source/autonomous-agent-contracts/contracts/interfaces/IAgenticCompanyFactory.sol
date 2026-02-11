// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

interface IAgenticCompanyFactory is IERC165 {
    event CompanyCreated(address indexed company, address indexed owner);

    error InvalidBeaconAddress();
    error BeaconNotDeployed();
    error InvalidFactoryOwnerAddress();
    error InvalidImplementationAddress();
    error ImplementationNotDeployed();

    function initialize(address beacon, address initialFactoryOwner) external;
    function createCompany(string calldata companyName, address agentToken) external returns (address company_);
    function getAllCompanies() external view returns (address[] memory companies_);
    function version() external view returns (uint64 version_);
    function COMPANY_BEACON() external view returns (address beacon_);
    function companyCount() external view returns (uint256 count_);
    function getCompanyAddressAtIndex(uint256 index) external view returns (address companyAddress_);
    function isCompany(address maybeCompany) external view returns (bool isCompany_);
}
