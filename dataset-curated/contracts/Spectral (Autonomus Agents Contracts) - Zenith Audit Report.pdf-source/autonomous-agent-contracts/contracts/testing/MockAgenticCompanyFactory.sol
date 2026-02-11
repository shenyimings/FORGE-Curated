// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import "./MockAgenticCompany.sol";
import "../interfaces/IOctoDistributor.sol";

contract MockAgenticCompanyFactory {
    mapping(address => uint256) public companies;
    address[] public companiesList;
    address public ansResolver;
    IOctoDistributor public octoDistributor;
    address public specToken;
    address public usdcToken;

    constructor(address _ansResolver, address _octoDistributor, address _specToken, address _usdcToken) {
        ansResolver = _ansResolver;
        octoDistributor = IOctoDistributor(_octoDistributor);
        specToken = _specToken;
        usdcToken = _usdcToken;
    }

    function createCompany() external returns (address) {
        MockAgenticCompany company = new MockAgenticCompany(ansResolver, address(octoDistributor), specToken, usdcToken);
        companiesList.push(address(company));
        companies[address(company)] = companiesList.length;
        return address(company);
    }

    function isCompany(address company) external view returns (bool) {
        return companies[company] != 0;
    }

    function getCompanyAddressAtIndex(uint256 index) external view returns (address) {
        require(index < companiesList.length, "Invalid index");
        return companiesList[index];
    }

    function companyCount() external view returns (uint256) {
        return companiesList.length;
    }
}